package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
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
		return fiveHourObservation(used, now.Add(fiveHours)), nil
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
		return fiveHourObservation(90, now.Add(fiveHours)), nil
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
		return fiveHourObservation(99, now.Add(fiveHours)), nil
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
		return fiveHourObservation(85, now.Add(fiveHours)), nil
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
	if got := quota.config.reservesFor("claude-a.json"); got != (accountReserves{FiveHour: 25, Weekly: 25}) {
		t.Fatalf("expected normalized override lookup to return 25 for both windows, got %#v", got)
	}
	if got := quota.config.reservesFor("codex-a.json"); got != (accountReserves{}) {
		t.Fatalf("expected unlisted accounts to fall back to 0, got %#v", got)
	}
}

func TestSchedulerReservesWeeklyWindow(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.config.ReservePercent = 20
	quota.loadCredentials = staticCredentials(map[string]string{
		"claude-a": "weekly-exhausted",
		"claude-b": "available",
	})
	quota.fetchProviderQuota = func(_ string, credential authCredential, _ time.Duration) (quotaObservation, error) {
		observation := quotaObservation{
			FiveHour: windowState{Applicable: true, UtilizedPercent: 10, ResetAt: now.Add(fiveHours)},
			Weekly:   windowState{Applicable: true, UtilizedPercent: 12, ResetAt: now.Add(sevenDays)},
		}
		if credential.AccessToken == "weekly-exhausted" {
			observation.Weekly.UtilizedPercent = 80
		}
		return observation, nil
	}

	response := pickResponse(t, quota, schedulerPickRequest{
		Provider: "claude",
		Candidates: []schedulerAuthCandidate{
			{ID: "claude-a", Provider: "claude"},
			{ID: "claude-b", Provider: "claude"},
		},
	})
	if !response.Handled || response.AuthID != "claude-b" {
		t.Fatalf("expected the weekly-exhausted account to be withheld despite a fresh five-hour window, got %#v", response)
	}
}

func TestSchedulerIgnoresWeeklyWindowWhenProviderReportsNone(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.config.ReservePercent = 20
	quota.loadCredentials = staticCredentials(map[string]string{"codex-a": "token-a"})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		return fiveHourObservation(10, now.Add(fiveHours)), nil
	}

	response := pickResponse(t, quota, schedulerPickRequest{
		Provider:   "codex",
		Candidates: []schedulerAuthCandidate{{ID: "codex-a", Provider: "codex"}},
	})
	if response.Handled {
		t.Fatalf("expected an account without a weekly limit to stay eligible, got %#v", response)
	}
}

func TestWeeklyReserveDefaultsToFiveHourReserve(t *testing.T) {
	quota := newQuotaLimiter()
	configYAML := []byte(fmt.Sprintf(
		"state_path: %q\nreserve_percent: 15\nreserve_percent_by_auth_id:\n  claude-a: 30\n",
		filepath.Join(t.TempDir(), "state.json"),
	))
	if errConfigure := quota.configure(lifecycleRaw(t, configYAML)); errConfigure != nil {
		t.Fatal(errConfigure)
	}
	if got := quota.config.reservesFor("codex-a"); got != (accountReserves{FiveHour: 15, Weekly: 15}) {
		t.Fatalf("expected the weekly reserve to inherit reserve_percent, got %#v", got)
	}
	if got := quota.config.reservesFor("claude-a"); got != (accountReserves{FiveHour: 30, Weekly: 30}) {
		t.Fatalf("expected a per-account reserve to cover both windows, got %#v", got)
	}
}

func TestWeeklyReserveOverridesTakePrecedence(t *testing.T) {
	quota := newQuotaLimiter()
	configYAML := []byte(fmt.Sprintf(
		"state_path: %q\nreserve_percent: 15\nweekly_reserve_percent: 40\n"+
			"reserve_percent_by_auth_id:\n  claude-a: 30\n"+
			"weekly_reserve_percent_by_auth_id:\n  \"Claude-A.json\": 55\n  claude-b: 5\n",
		filepath.Join(t.TempDir(), "state.json"),
	))
	if errConfigure := quota.configure(lifecycleRaw(t, configYAML)); errConfigure != nil {
		t.Fatal(errConfigure)
	}
	// Most specific wins: the per-account weekly override beats the
	// per-account reserve, which beats the global weekly reserve.
	if got := quota.config.reservesFor("claude-a"); got != (accountReserves{FiveHour: 30, Weekly: 55}) {
		t.Fatalf("expected the per-account weekly override to win, got %#v", got)
	}
	if got := quota.config.reservesFor("claude-b"); got != (accountReserves{FiveHour: 15, Weekly: 5}) {
		t.Fatalf("expected a weekly-only override to leave the five-hour reserve alone, got %#v", got)
	}
	if got := quota.config.reservesFor("codex-a"); got != (accountReserves{FiveHour: 15, Weekly: 40}) {
		t.Fatalf("expected the global weekly reserve to apply, got %#v", got)
	}
}

func TestWeeklyOnlyReserveStillManagesAccount(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.config.ReservePercent = 0
	quota.config.WeeklyReservePercent = float64Ptr(20)
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		return weeklyObservation(85, now.Add(sevenDays)), nil
	}

	env := pickEnvelope(t, quota, schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	})
	if env.OK || env.Error == nil || env.Error.Code != "quota_reserved" {
		t.Fatalf("expected a weekly-only reserve to withhold the account, got %#v", env)
	}
}

func TestConfigureRejectsOutOfRangeWeeklyReserve(t *testing.T) {
	quota := newQuotaLimiter()
	configYAML := []byte(fmt.Sprintf(
		"state_path: %q\nweekly_reserve_percent: 100\n",
		filepath.Join(t.TempDir(), "state.json"),
	))
	if errConfigure := quota.configure(lifecycleRaw(t, configYAML)); errConfigure == nil {
		t.Fatal("expected a 100% weekly reserve to be rejected")
	}
}

func TestSchedulerRepollsWeeklyBlockBeforeItsReset(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.now = func() time.Time { return now }
	quota.config.ReservePercent = 20
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	var calls atomic.Int32
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		calls.Add(1)
		return weeklyObservation(85, now.Add(sevenDays)), nil
	}
	request := schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	}

	pickEnvelope(t, quota, request)
	now = now.Add(time.Hour)
	pickEnvelope(t, quota, request)
	if calls.Load() != 1 {
		t.Fatalf("expected a weekly-blocked account to stay cached within the cap, got %d lookups", calls.Load())
	}
	// A week-long block must not go unverified for a week: upstream weekly
	// utilization can fall before its advertised reset.
	now = now.Add(fiveHours)
	pickEnvelope(t, quota, request)
	if calls.Load() != 2 {
		t.Fatalf("expected a weekly-blocked account to be re-polled after the cap, got %d lookups", calls.Load())
	}
}

func TestSchedulerRepollsWhenFiveHourResetFreesWeeklyBlockedAccount(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.now = func() time.Time { return now }
	quota.config.ReservePercent = 20
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	var calls atomic.Int32
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		calls.Add(1)
		return quotaObservation{
			FiveHour: windowState{Applicable: true, UtilizedPercent: 90, ResetAt: now.Add(time.Hour)},
			Weekly:   windowState{Applicable: true, UtilizedPercent: 90, ResetAt: now.Add(sevenDays)},
		}, nil
	}
	request := schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	}

	pickEnvelope(t, quota, request)
	// The five-hour window resets first. The account stays blocked by the
	// weekly window, but the plugin must re-poll to learn the new five-hour
	// figure rather than waiting a week.
	now = now.Add(time.Hour)
	pickEnvelope(t, quota, request)
	if calls.Load() != 2 {
		t.Fatalf("expected a re-poll at the earlier of the two resets, got %d lookups", calls.Load())
	}
}

func TestSchedulerPollsReservedWindowWithoutResetOnTheNormalInterval(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.now = func() time.Time { return now }
	quota.config.ReservePercent = 20
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	var calls atomic.Int32
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		calls.Add(1)
		return weeklyObservation(85, time.Time{}), nil
	}
	request := schedulerPickRequest{
		Provider:   "claude",
		Candidates: []schedulerAuthCandidate{{ID: "claude-a", Provider: "claude"}},
	}

	pickEnvelope(t, quota, request)
	// Without an upstream reset there is nothing to wait for, so the account
	// falls back to the ordinary poll interval rather than the five-hour cap.
	now = now.Add(defaultPollInterval)
	pickEnvelope(t, quota, request)
	if calls.Load() != 2 {
		t.Fatalf("expected a reserved window without a reset to poll on the normal interval, got %d lookups", calls.Load())
	}
}

func TestSchedulerRejectsWhenEveryAccountIsReserved(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	quota.loadCredentials = staticCredentials(map[string]string{"claude-a": "token-a"})
	quota.fetchProviderQuota = func(_ string, _ authCredential, _ time.Duration) (quotaObservation, error) {
		return fiveHourObservation(100, now.Add(fiveHours)), nil
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
		return fiveHourObservation(25, now.Add(fiveHours)), nil
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
			return fiveHourObservation(25, now.Add(fiveHours)), nil
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
	if !status.Known || status.State.FiveHour.UtilizedPercent != 25 || status.Err == "" {
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
		return fiveHourObservation(85, now.Add(fiveHours)), nil
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

func TestPersistRoundTripsBothWindows(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	quota := configuredLimiter(t, now)
	statePath := filepath.Join(t.TempDir(), "state.json")
	quota.config.StatePath = statePath
	quota.statuses["claude-a"] = quotaStatus{
		Known: true,
		State: accountState{
			Provider:  "claude",
			FiveHour:  windowState{Applicable: true, UtilizedPercent: 12, ResetAt: now.Add(fiveHours)},
			Weekly:    windowState{Applicable: true, UtilizedPercent: 88, ResetAt: now.Add(sevenDays)},
			UpdatedAt: now,
		},
		CheckedAt: now,
	}
	if errPersist := quota.persist(); errPersist != nil {
		t.Fatal(errPersist)
	}

	reloaded, errLoad := loadPersistedState(statePath, now.Add(time.Minute))
	if errLoad != nil {
		t.Fatal(errLoad)
	}
	status := reloaded["claude-a"]
	if !status.State.FiveHour.Applicable || status.State.FiveHour.UtilizedPercent != 12 {
		t.Fatalf("five-hour window lost across a restart: %#v", status.State.FiveHour)
	}
	if !status.State.Weekly.Applicable || status.State.Weekly.UtilizedPercent != 88 {
		t.Fatalf("weekly window lost across a restart: %#v", status.State.Weekly)
	}
	if !accountReserved(status, accountReserves{FiveHour: 20, Weekly: 20}, now.Add(time.Minute)) {
		t.Fatal("expected the reloaded weekly block to still withhold the account")
	}
}

func TestLoadsPreWeeklyStateAsFiveHourWindow(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	statePath := filepath.Join(t.TempDir(), "state.json")
	legacy := fmt.Sprintf(`{
		"version": 2,
		"accounts": {
			"claude-a": {
				"known": true,
				"applicable": true,
				"state": {
					"provider": "claude",
					"utilized_percent": 85,
					"reset_at": %q,
					"updated_at": %q
				},
				"checked_at": %q
			}
		}
	}`, now.Add(time.Hour).Format(time.RFC3339Nano), now.Format(time.RFC3339Nano), now.Format(time.RFC3339Nano))
	if errWrite := os.WriteFile(statePath, []byte(legacy), 0o600); errWrite != nil {
		t.Fatal(errWrite)
	}

	statuses, errLoad := loadPersistedState(statePath, now)
	if errLoad != nil {
		t.Fatal(errLoad)
	}
	status, exists := statuses["claude-a"]
	if !exists || !status.Known {
		t.Fatalf("expected the pre-weekly observation to survive the upgrade, got %#v", status)
	}
	if !status.State.FiveHour.Applicable || status.State.FiveHour.UtilizedPercent != 85 {
		t.Fatalf("expected the legacy scalars to become the five-hour window, got %#v", status.State.FiveHour)
	}
	// Nothing upstream was ever observed about the weekly window, so it must
	// not be treated as a limit of 0% used.
	if status.State.Weekly.Applicable {
		t.Fatalf("expected the weekly window to stay unobserved, got %#v", status.State.Weekly)
	}
}

func TestExpiredWeeklyWindowInvalidatesCachedObservation(t *testing.T) {
	now := time.Date(2026, time.July, 29, 10, 0, 0, 0, time.UTC)
	status := quotaStatus{
		Known: true,
		State: accountState{
			FiveHour: windowState{Applicable: true, UtilizedPercent: 10, ResetAt: now.Add(fiveHours)},
			Weekly:   windowState{Applicable: true, UtilizedPercent: 90, ResetAt: now.Add(-time.Minute)},
		},
		CheckedAt: now.Add(-time.Hour),
	}
	if observationStillValid(status, now) {
		t.Fatal("expected a rolled-over weekly window to invalidate the cached observation")
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
		return quotaObservation{}, nil
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
		},
		"seven_day": {
			"utilization": 41,
			"resets_at": "2026-08-04T00:59:59.951713+00:00"
		},
		"seven_day_opus": null,
		"seven_day_sonnet": {
			"utilization": 97,
			"resets_at": "2026-08-03T03:00:00.951719+00:00"
		},
		"extra_usage": {"is_enabled": false}
	}`))
	if errParse != nil {
		t.Fatal(errParse)
	}
	if !observation.FiveHour.Applicable || observation.FiveHour.UtilizedPercent != 83.5 {
		t.Fatalf("unexpected Claude five-hour window: %#v", observation.FiveHour)
	}
	if got := observation.FiveHour.ResetAt.UTC().Format(time.RFC3339Nano); got != "2026-07-29T11:09:59.808464Z" {
		t.Fatalf("unexpected Claude five-hour reset: %s", got)
	}
	// seven_day_sonnet sits at 97% but is model-scoped, so it must not leak
	// into the account-wide weekly window.
	if !observation.Weekly.Applicable || observation.Weekly.UtilizedPercent != 41 {
		t.Fatalf("unexpected Claude weekly window: %#v", observation.Weekly)
	}
	if got := observation.Weekly.ResetAt.UTC().Format(time.RFC3339Nano); got != "2026-08-04T00:59:59.951713Z" {
		t.Fatalf("unexpected Claude weekly reset: %s", got)
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
	if !observation.FiveHour.Applicable || observation.FiveHour.UtilizedPercent != 0 || !observation.FiveHour.ResetAt.IsZero() {
		t.Fatalf("unexpected unused Claude five-hour window: %#v", observation.FiveHour)
	}
	if observation.Weekly.Applicable {
		t.Fatalf("expected an absent seven_day window to stay inapplicable, got %#v", observation.Weekly)
	}
}

func TestParseCodexWindowsByAdvertisedLength(t *testing.T) {
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
	if !observation.FiveHour.Applicable || observation.FiveHour.UtilizedPercent != 82 {
		t.Fatalf("unexpected Codex five-hour window: %#v", observation.FiveHour)
	}
	if !observation.FiveHour.ResetAt.Equal(now.Add(15 * time.Minute)) {
		t.Fatalf("unexpected Codex five-hour reset: %s", observation.FiveHour.ResetAt)
	}
	if !observation.Weekly.Applicable || observation.Weekly.UtilizedPercent != 17 {
		t.Fatalf("unexpected Codex weekly window: %#v", observation.Weekly)
	}
	if !observation.Weekly.ResetAt.Equal(time.Unix(1785902990, 0)) {
		t.Fatalf("unexpected Codex weekly reset: %s", observation.Weekly.ResetAt)
	}
}

func TestParseCodexWithoutFiveHourWindowKeepsWeekly(t *testing.T) {
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
	if observation.FiveHour.Applicable {
		t.Fatalf("expected a weekly-only response to leave the five-hour window inapplicable, got %#v", observation.FiveHour)
	}
	if !observation.Weekly.Applicable || observation.Weekly.UtilizedPercent != 17 {
		t.Fatalf("expected the weekly window to be observed, got %#v", observation.Weekly)
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

func float64Ptr(value float64) *float64 {
	return &value
}

func lifecycleRaw(t *testing.T, configYAML []byte) []byte {
	t.Helper()
	raw, errMarshal := json.Marshal(lifecycleRequest{ConfigYAML: configYAML})
	if errMarshal != nil {
		t.Fatal(errMarshal)
	}
	return raw
}

func fiveHourObservation(used float64, resetAt time.Time) quotaObservation {
	return quotaObservation{
		FiveHour: windowState{Applicable: true, UtilizedPercent: used, ResetAt: resetAt},
	}
}

func weeklyObservation(used float64, resetAt time.Time) quotaObservation {
	return quotaObservation{
		Weekly: windowState{Applicable: true, UtilizedPercent: used, ResetAt: resetAt},
	}
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
