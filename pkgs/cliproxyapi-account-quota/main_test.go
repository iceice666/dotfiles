package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestSchedulerExcludesAccountAtReserveBoundary(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.fetchProviderQuota = func(_ string, credential authCredential, _ time.Duration) (quotaObservation, error) {
		used := 79.0
		if credential.AccessToken == "blocked" {
			used = 80
		}
		return quotaObservation{Applicable: true, UtilizedPercent: used, ResetAt: now.Add(fiveHours)}, nil
	}
	quota.loadCredentials = staticCredentials(map[string]string{
		"claude-a": "blocked",
		"claude-b": "available",
	})

	response := pickResponse(t, quota, schedulerPickRequest{
		Provider: "claude",
		Model:    "claude-sonnet-4-6",
		Candidates: []schedulerAuthCandidate{
			{ID: "claude-a", Provider: "claude", Priority: 0},
			{ID: "claude-b", Provider: "claude", Priority: 0},
		},
	})
	if !response.Handled || response.AuthID != "claude-b" {
		t.Fatalf("expected scheduler to select claude-b, got %#v", response)
	}
}

func TestSchedulerAppliesPerAccountReserveOverrides(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.config.ReservePercent = 20
	quota.config.ReserveByAuthID = map[string]float64{"claude-lenient": 5}
	quota.loadCredentials = staticCredentials(map[string]string{
		"claude-strict":  "token-strict",
		"claude-lenient": "token-lenient",
	})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		return quotaObservation{Applicable: true, UtilizedPercent: 90, ResetAt: now.Add(fiveHours)}, nil
	}

	response := pickResponse(t, quota, schedulerPickRequest{
		Provider: "claude",
		Candidates: []schedulerAuthCandidate{
			{ID: "claude-strict", Provider: "claude"},
			{ID: "claude-lenient", Provider: "claude"},
		},
	})
	if !response.Handled || response.AuthID != "claude-lenient" {
		t.Fatalf("expected the 5%% reserve account to stay eligible at 90%% usage, got %#v", response)
	}
}

func TestSchedulerLeavesZeroReserveAccountsUnmanaged(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.config.ReservePercent = 0
	quota.config.ReserveByAuthID = map[string]float64{"claude-a": 20}
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	var polled []string
	var polledMu sync.Mutex
	quota.fetchProviderQuota = func(provider string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		polledMu.Lock()
		polled = append(polled, provider)
		polledMu.Unlock()
		return quotaObservation{Applicable: true, UtilizedPercent: 99, ResetAt: now.Add(fiveHours)}, nil
	}

	response := pickResponse(t, quota, schedulerPickRequest{
		Provider: "codex",
		Candidates: []schedulerAuthCandidate{
			{ID: "codex-a", Provider: "codex"},
			{ID: "codex-b", Provider: "codex"},
		},
	})
	if response.Handled {
		t.Fatalf("expected unreserved Codex accounts to delegate to the built-in scheduler, got %#v", response)
	}
	polledMu.Lock()
	defer polledMu.Unlock()
	if len(polled) != 0 {
		t.Fatalf("expected no usage polling for unreserved accounts, got %v", polled)
	}
}

func TestSchedulerOverrideKeyIgnoresJSONSuffixAndCase(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.config.ReservePercent = 0
	quota.config.ReserveByAuthID = map[string]float64{"claude-a": 20}
	quota.loadCredentials = staticCredentials(map[string]string{"Claude-A.json": "token-a"})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		return quotaObservation{Applicable: true, UtilizedPercent: 85, ResetAt: now.Add(fiveHours)}, nil
	}

	env := pickEnvelope(t, quota, schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "Claude-A.json", Provider: "claude"}},
	})
	if env.OK || env.Error == nil || env.Error.Code != "quota_reserved" {
		t.Fatalf("expected the override to match the auth file name, got %#v", env)
	}
}

func TestConfigureRejectsOutOfRangePerAccountReserve(t *testing.T) {
	quota := newQuotaLimiter()
	configYAML := []byte(fmt.Sprintf(
		"state_path: %q\nreserve_percent: 0\nreserve_percent_by_auth_id:\n  claude-a: 100\n",
		filepath.Join(t.TempDir(), "state.json"),
	))
	raw, errMarshal := json.Marshal(lifecycleRequest{ConfigYAML: configYAML})
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	if errConfigure := quota.configure(raw); errConfigure == nil {
		t.Fatal("expected a 100% per-account reserve to be rejected")
	}
}

func TestConfigureNormalizesPerAccountReserveKeys(t *testing.T) {
	quota := newQuotaLimiter()
	configYAML := []byte(fmt.Sprintf(
		"state_path: %q\nreserve_percent: 0\nreserve_percent_by_auth_id:\n  \"Claude-A.json\": 25\n",
		filepath.Join(t.TempDir(), "state.json"),
	))
	raw, errMarshal := json.Marshal(lifecycleRequest{ConfigYAML: configYAML})
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	if errConfigure := quota.configure(raw); errConfigure != nil {
		t.Fatal(errConfigure)
	}
	if got := quota.config.reserveFor("claude-a.json"); got != 25 {
		t.Fatalf("expected normalized override lookup to return 25, got %v", got)
	}
	if got := quota.config.reserveFor("codex-a.json"); got != 0 {
		t.Fatalf("expected unlisted accounts to fall back to 0, got %v", got)
	}
}

func TestSchedulerRejectsWhenEveryAccountIsReserved(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		return quotaObservation{Applicable: true, UtilizedPercent: 100, ResetAt: now.Add(fiveHours)}, nil
	}

	env := pickEnvelope(t, quota, schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	})
	if env.OK || env.Error == nil || env.Error.Code != "quota_reserved" || env.Error.HTTPStatus != 429 || !env.Error.Retryable {
		t.Fatalf("expected quota_reserved error, got %#v", env)
	}
}

func TestSchedulerFailsClosedWhenUsageLookupFails(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.loadCredentials = staticCredentials(map[string]string{"codex-a": "token-a"})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		return quotaObservation{}, errors.New("upstream unavailable")
	}

	env := pickEnvelope(t, quota, schedulerPickRequest{
		Provider:   "codex",
		Candidates: []schedulerAuthCandidate{{ID: "codex-a", Provider: "codex"}},
	})
	if env.OK || env.Error == nil || env.Error.Code != "quota_unavailable" || env.Error.HTTPStatus != 503 || !env.Error.Retryable {
		t.Fatalf("expected quota_unavailable error, got %#v", env)
	}
}

func TestSchedulerCanFailOpenWhenConfigured(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.config.FailClosed = false
	quota.loadCredentials = staticCredentials(map[string]string{"codex-a": "token-a"})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		return quotaObservation{}, errors.New("upstream unavailable")
	}

	response := pickResponse(t, quota, schedulerPickRequest{
		Provider:   "codex",
		Candidates: []schedulerAuthCandidate{{ID: "codex-a", Provider: "codex"}},
	})
	if response.Handled {
		t.Fatalf("expected built-in scheduler delegation, got %#v", response)
	}
}

func TestSchedulerCachesUsageObservations(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.loadCredentials = staticCredentials(map[string]string{"codex-a": "token-a"})
	var calls atomic.Int32
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		calls.Add(1)
		return quotaObservation{Applicable: true, UtilizedPercent: 25, ResetAt: now.Add(fiveHours)}, nil
	}
	request := schedulerPickRequest{
		Provider:   "codex",
		Candidates: []schedulerAuthCandidate{{ID: "codex-a", Provider: "codex"}},
	}

	pickResponse(t, quota, request)
	pickResponse(t, quota, request)
	if calls.Load() != 1 {
		t.Fatalf("expected one usage request inside cache interval, got %d", calls.Load())
	}
}

func TestSchedulerBacksOffAfterUsageLookupFailure(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.now = func() time.Time { return now }
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	var calls atomic.Int32
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		calls.Add(1)
		return quotaObservation{}, errors.New("usage endpoint returned HTTP 429")
	}
	request := schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	}

	pickEnvelope(t, quota, request)
	now = now.Add(59 * time.Minute)
	pickEnvelope(t, quota, request)
	if calls.Load() != 1 {
		t.Fatalf("expected one lookup during error backoff, got %d", calls.Load())
	}
	now = now.Add(time.Minute)
	pickEnvelope(t, quota, request)
	if calls.Load() != 2 {
		t.Fatalf("expected lookup retry after error backoff, got %d", calls.Load())
	}
}

func TestSchedulerKeepsValidObservationWhenRefreshFails(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.now = func() time.Time { return now }
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	var calls atomic.Int32
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		if calls.Add(1) == 1 {
			return quotaObservation{Applicable: true, UtilizedPercent: 25, ResetAt: now.Add(fiveHours)}, nil
		}
		return quotaObservation{}, errors.New("usage endpoint returned HTTP 429")
	}
	request := schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	}

	pickResponse(t, quota, request)
	now = now.Add(defaultPollInterval)
	pickResponse(t, quota, request)
	status := quota.statuses["claude-a"]
	if !status.Known || status.State.UtilizedPercent != 25 || status.Err == "" {
		t.Fatalf("expected cached observation with refresh error, got %#v", status)
	}
	now = now.Add(30 * time.Minute)
	pickResponse(t, quota, request)
	if calls.Load() != 2 {
		t.Fatalf("expected no lookup during error backoff, got %d", calls.Load())
	}
}

func TestSchedulerDoesNotPollReservedAccountBeforeReset(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.now = func() time.Time { return now }
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	var calls atomic.Int32
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		calls.Add(1)
		return quotaObservation{Applicable: true, UtilizedPercent: 85, ResetAt: now.Add(fiveHours)}, nil
	}
	request := schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	}

	pickEnvelope(t, quota, request)
	now = now.Add(time.Hour)
	pickEnvelope(t, quota, request)
	if calls.Load() != 1 {
		t.Fatalf("expected reserved account to remain cached until reset, got %d lookups", calls.Load())
	}
}

func TestPersistedErrorBackoffSurvivesRestart(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	statePath := filepath.Join(t.TempDir(), "state.json")
	quota := configuredLimiter(t, now)
	quota.config.StatePath = statePath
	quota.statuses["claude-a"] = quotaStatus{
		CheckedAt: now,
		RetryAt:   now.Add(time.Hour),
		Err:       "usage endpoint returned HTTP 429",
	}
	if errPersist := quota.persist(); errPersist != nil {
		t.Fatal(errPersist)
	}

	reloaded, errLoad := loadPersistedState(statePath, now.Add(time.Minute))
	if errLoad != nil {
		t.Fatal(errLoad)
	}
	status, exists := reloaded["claude-a"]
	if !exists || !status.RetryAt.Equal(now.Add(time.Hour)) || status.Err == "" {
		t.Fatalf("expected persisted error backoff, got %#v", status)
	}
	if shouldRefresh(status, true, quota.config, "claude-a", now.Add(time.Minute)) {
		t.Fatal("expected restarted plugin to retain the error backoff")
	}
}

func TestSchedulerPollsCandidatesConcurrently(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.loadCredentials = staticCredentials(map[string]string{
		"codex-a": "token-a",
		"codex-b": "token-b",
	})
	started := make(chan struct{}, 2)
	release := make(chan struct{})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		started <- struct{}{}
		<-release
		return quotaObservation{Applicable: false}, nil
	}

	done := make(chan struct{})
	go func() {
		defer close(done)
		pickResponse(t, quota, schedulerPickRequest{
			Provider: "codex",
			Candidates: []schedulerAuthCandidate{
				{ID: "codex-a", Provider: "codex"},
				{ID: "codex-b", Provider: "codex"},
			},
		})
	}()
	for range 2 {
		select {
		case <-started:
		case <-time.After(time.Second):
			t.Fatal("quota requests did not start concurrently")
		}
	}
	close(release)
	<-done
}

func TestParseClaudeUsage(t *testing.T) {
	observation, errParse := parseClaudeUsage([]byte(`{
		"five_hour": {
			"utilization": 83.5,
			"resets_at": "2026-07-29T11:09:59.808464+00:00"
		}
	}`))
	if errParse != nil {
		t.Fatal(errParse)
	}
	if !observation.Applicable || observation.UtilizedPercent != 83.5 {
		t.Fatalf("unexpected Claude observation: %#v", observation)
	}
	if got := observation.ResetAt.UTC().Format(time.RFC3339Nano); got != "2026-07-29T11:09:59.808464Z" {
		t.Fatalf("unexpected Claude reset: %s", got)
	}
}

func TestParseClaudeUnusedWindowWithoutReset(t *testing.T) {
	observation, errParse := parseClaudeUsage([]byte(`{
		"five_hour": {
			"utilization": 0,
			"resets_at": null
		}
	}`))
	if errParse != nil {
		t.Fatal(errParse)
	}
	if !observation.Applicable || observation.UtilizedPercent != 0 || !observation.ResetAt.IsZero() {
		t.Fatalf("unexpected unused Claude observation: %#v", observation)
	}
}

func TestParseCodexFiveHourWindow(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	observation, errParse := parseCodexUsage([]byte(`{
		"rate_limit": {
			"primary_window": {
				"used_percent": 17,
				"limit_window_seconds": 604800,
				"reset_at": 1785902990
			},
			"secondary_window": {
				"used_percent": 82,
				"limit_window_seconds": 18000,
				"reset_after_seconds": 900
			}
		}
	}`), now)
	if errParse != nil {
		t.Fatal(errParse)
	}
	if !observation.Applicable || observation.UtilizedPercent != 82 {
		t.Fatalf("unexpected Codex observation: %#v", observation)
	}
	if !observation.ResetAt.Equal(now.Add(15 * time.Minute)) {
		t.Fatalf("unexpected Codex reset: %s", observation.ResetAt)
	}
}

func TestParseCodexWithoutFiveHourWindowIsNotApplicable(t *testing.T) {
	observation, errParse := parseCodexUsage([]byte(`{
		"rate_limit": {
			"primary_window": {
				"used_percent": 17,
				"limit_window_seconds": 604800,
				"reset_at": 1785902990
			}
		}
	}`), time.Now())
	if errParse != nil {
		t.Fatal(errParse)
	}
	if observation.Applicable {
		t.Fatalf("expected a seven-day-only response to be inapplicable, got %#v", observation)
	}
}

func TestConfigureDefaultsToFailClosed(t *testing.T) {
	quota := newQuotaLimiter()
	configYAML := []byte(fmt.Sprintf("state_path: %q\nreserve_percent: 20\n", filepath.Join(t.TempDir(), "state.json")))
	raw, errMarshal := json.Marshal(lifecycleRequest{ConfigYAML: configYAML})
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	if errConfigure := quota.configure(raw); errConfigure != nil {
		t.Fatal(errConfigure)
	}
	if !quota.config.FailClosed || quota.config.PollIntervalSeconds != 900 || quota.config.ErrorRetryIntervalSeconds != 3600 || quota.config.RequestTimeoutSeconds != 5 {
		t.Fatalf("unexpected defaults: %#v", quota.config)
	}
}

func TestConfigureAllowsExplicitFailOpen(t *testing.T) {
	quota := newQuotaLimiter()
	configYAML := []byte(fmt.Sprintf("state_path: %q\nfail_closed: false\n", filepath.Join(t.TempDir(), "state.json")))
	raw, errMarshal := json.Marshal(lifecycleRequest{ConfigYAML: configYAML})
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	if errConfigure := quota.configure(raw); errConfigure != nil {
		t.Fatal(errConfigure)
	}
	if quota.config.FailClosed {
		t.Fatal("expected explicit fail_closed: false to be retained")
	}
}

func configuredLimiter(t *testing.T, now time.Time) *quotaLimiter {
	t.Helper()
	quota := newQuotaLimiter()
	quota.now = func() time.Time { return now }
	quota.config = defaultConfig()
	quota.config.StatePath = filepath.Join(t.TempDir(), "state.json")
	return quota
}

func staticCredentials(tokens map[string]string) credentialLoader {
	return func(candidates []schedulerAuthCandidate) map[string]credentialResult {
		results := make(map[string]credentialResult, len(candidates))
		for _, candidate := range candidates {
			token, exists := tokens[candidate.ID]
			if !exists {
				results[candidate.ID] = credentialResult{Err: errors.New("missing test credential")}
				continue
			}
			results[candidate.ID] = credentialResult{Credential: authCredential{AccessToken: token}}
		}
		return results
	}
}

func pickResponse(t *testing.T, quota *quotaLimiter, request schedulerPickRequest) schedulerPickResponse {
	t.Helper()
	env := pickEnvelope(t, quota, request)
	if !env.OK {
		t.Fatalf("unexpected scheduler error: %#v", env.Error)
	}
	var response schedulerPickResponse
	if errUnmarshal := json.Unmarshal(env.Result, &response); errUnmarshal != nil {
		t.Fatal(errUnmarshal)
	}
	return response
}

func pickEnvelope(t *testing.T, quota *quotaLimiter, request schedulerPickRequest) envelope {
	t.Helper()
	rawRequest, errMarshal := json.Marshal(request)
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	rawResponse, errPick := quota.pick(rawRequest)
	if errPick != nil {
		t.Fatal(errPick)
	}
	var env envelope
	if errUnmarshal := json.Unmarshal(rawResponse, &env); errUnmarshal != nil {
		t.Fatal(errUnmarshal)
	}
	return env
}
