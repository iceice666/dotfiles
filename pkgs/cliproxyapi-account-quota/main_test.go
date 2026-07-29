package main

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"testing"
	"time"
)

func TestCodexReserveBlocksOnlyExhaustedAccount(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)

	handleUsageForTest(t, quota, usageRecord{
		Provider: "codex",
		AuthID:   "codex-a",
		ResponseHeaders: map[string][]string{
			"X-Codex-Primary-Used-Percent":   {"80"},
			"X-Codex-Primary-Window-Minutes": {"300"},
			"X-Codex-Primary-Reset-At":       {now.Add(2 * time.Hour).Format(time.RFC3339)},
		},
	})

	response := pickForTest(t, quota, schedulerPickRequest{
		Provider: "codex",
		Model:    "gpt-5.6-sol",
		Candidates: []schedulerAuthCandidate{
			{ID: "codex-a", Provider: "codex", Priority: 0},
			{ID: "codex-b", Provider: "codex", Priority: 0},
		},
	})
	if !response.OK {
		t.Fatalf("pick returned error: %+v", response.Error)
	}
	var decision schedulerPickResponse
	mustUnmarshal(t, response.Result, &decision)
	if !decision.Handled || decision.AuthID != "codex-b" {
		t.Fatalf("expected codex-b, got %+v", decision)
	}
}

func TestClaudeReserveRejectsWhenEveryAccountIsExhausted(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	reset := now.Add(90 * time.Minute).Format(time.RFC3339)

	for _, authID := range []string{"claude-a", "claude-b"} {
		handleUsageForTest(t, quota, usageRecord{
			Provider: "claude",
			AuthID:   authID,
			ResponseHeaders: map[string][]string{
				"Anthropic-Ratelimit-Unified-5h-Utilization": {"0.8"},
				"Anthropic-Ratelimit-Unified-5h-Reset":       {reset},
			},
		})
	}

	response := pickForTest(t, quota, schedulerPickRequest{
		Provider: "claude",
		Model:    "claude-sonnet-5",
		Candidates: []schedulerAuthCandidate{
			{ID: "claude-a", Provider: "claude"},
			{ID: "claude-b", Provider: "claude"},
		},
	})
	if response.OK || response.Error == nil || response.Error.Code != "quota_reserved" {
		t.Fatalf("expected quota_reserved, got %+v", response)
	}
}

func TestExpiredQuotaReturnsControlToBuiltinScheduler(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	handleUsageForTest(t, quota, usageRecord{
		Provider: "codex",
		AuthID:   "codex-a",
		ResponseHeaders: map[string][]string{
			"X-Codex-Primary-Used-Percent": {"95"},
			"X-Codex-Primary-Reset-At":     {now.Add(time.Minute).Format(time.RFC3339)},
		},
	})
	quota.now = func() time.Time { return now.Add(2 * time.Minute) }

	response := pickForTest(t, quota, schedulerPickRequest{
		Provider:   "codex",
		Model:      "gpt-5.6-sol",
		Candidates: []schedulerAuthCandidate{{ID: "codex-a", Provider: "codex"}},
	})
	if !response.OK {
		t.Fatalf("pick returned error: %+v", response.Error)
	}
	var decision schedulerPickResponse
	mustUnmarshal(t, response.Result, &decision)
	if decision.Handled {
		t.Fatalf("expected builtin scheduler delegation, got %+v", decision)
	}
}

func TestBlockedStateSurvivesReconfigure(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	statePath := filepath.Join(t.TempDir(), "quota.json")
	quota := newQuotaLimiter()
	quota.now = func() time.Time { return now }
	configureForTest(t, quota, statePath)

	handleUsageForTest(t, quota, usageRecord{
		Provider: "claude",
		AuthID:   "claude-a",
		ResponseHeaders: map[string][]string{
			"Anthropic-Ratelimit-Unified-5h-Utilization": {"0.91"},
			"Anthropic-Ratelimit-Unified-5h-Reset":       {now.Add(time.Hour).Format(time.RFC3339)},
		},
	})

	reloaded := newQuotaLimiter()
	reloaded.now = func() time.Time { return now }
	configureForTest(t, reloaded, statePath)
	response := pickForTest(t, reloaded, schedulerPickRequest{
		Provider:   "claude",
		Model:      "claude-sonnet-5",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	})
	if response.OK || response.Error == nil || response.Error.Code != "quota_reserved" {
		t.Fatalf("expected persisted quota_reserved, got %+v", response)
	}
}

func configuredLimiter(t *testing.T, now time.Time) *quotaLimiter {
	t.Helper()
	quota := newQuotaLimiter()
	quota.now = func() time.Time { return now }
	configureForTest(t, quota, filepath.Join(t.TempDir(), "quota.json"))
	return quota
}

func configureForTest(t *testing.T, quota *quotaLimiter, statePath string) {
	t.Helper()
	configYAML := []byte(fmt.Sprintf("reserve_percent: 20\nstate_path: %q\n", statePath))
	raw, errMarshal := json.Marshal(lifecycleRequest{ConfigYAML: configYAML})
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	if errConfigure := quota.configure(raw); errConfigure != nil {
		t.Fatal(errConfigure)
	}
}

func handleUsageForTest(t *testing.T, quota *quotaLimiter, record usageRecord) {
	t.Helper()
	raw, errMarshal := json.Marshal(record)
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	if errUsage := quota.handleUsage(raw); errUsage != nil {
		t.Fatal(errUsage)
	}
}

func pickForTest(t *testing.T, quota *quotaLimiter, request schedulerPickRequest) envelope {
	t.Helper()
	raw, errMarshal := json.Marshal(request)
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	responseRaw, errPick := quota.pick(raw)
	if errPick != nil {
		t.Fatal(errPick)
	}
	var response envelope
	mustUnmarshal(t, responseRaw, &response)
	return response
}

func mustUnmarshal(t *testing.T, raw []byte, target any) {
	t.Helper()
	if errUnmarshal := json.Unmarshal(raw, target); errUnmarshal != nil {
		t.Fatal(errUnmarshal)
	}
}
