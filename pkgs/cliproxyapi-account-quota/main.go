package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef struct {
	void* ptr;
	size_t len;
} cliproxy_buffer;

typedef int (*cliproxy_host_call_fn)(void*, const char*, const uint8_t*, size_t, cliproxy_buffer*);
typedef void (*cliproxy_host_free_fn)(void*, size_t);

typedef struct {
	uint32_t abi_version;
	void* host_ctx;
	cliproxy_host_call_fn call;
	cliproxy_host_free_fn free_buffer;
} cliproxy_host_api;

typedef int (*cliproxy_plugin_call_fn)(char*, uint8_t*, size_t, cliproxy_buffer*);
typedef void (*cliproxy_plugin_free_fn)(void*, size_t);
typedef void (*cliproxy_plugin_shutdown_fn)(void);

typedef struct {
	uint32_t abi_version;
	cliproxy_plugin_call_fn call;
	cliproxy_plugin_free_fn free_buffer;
	cliproxy_plugin_shutdown_fn shutdown;
} cliproxy_plugin_api;

extern int cliproxyPluginCall(char*, uint8_t*, size_t, cliproxy_buffer*);
extern void cliproxyPluginFree(void*, size_t);
extern void cliproxyPluginShutdown(void);

static const cliproxy_host_api* stored_host;

static void store_host_api(const cliproxy_host_api* host) {
	stored_host = host;
}

static int call_host_api(const char* method, const uint8_t* request, size_t request_len, cliproxy_buffer* response) {
	if (stored_host == NULL || stored_host->call == NULL) {
		return -1;
	}
	return stored_host->call(stored_host->host_ctx, method, request, request_len, response);
}

static void free_host_buffer(void* ptr, size_t len) {
	if (stored_host != NULL && stored_host->free_buffer != NULL && ptr != NULL) {
		stored_host->free_buffer(ptr, len);
	}
}
*/
import "C"

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
	"unsafe"

	"gopkg.in/yaml.v3"
)

const (
	abiVersion                uint32 = 1
	schemaVersion             uint32 = 1
	stateVersion                     = 3
	pluginVersion                    = "0.5.0"
	fiveHours                        = 5 * time.Hour
	sevenDays                        = 7 * 24 * time.Hour
	defaultReservePercent            = 20.0
	defaultPollInterval              = 15 * time.Minute
	defaultErrorRetryInterval        = time.Hour
	defaultRequestTimeout            = 5 * time.Second
	defaultStatePath                 = "account-quota-state.json"
	claudeUsageURL                   = "https://api.anthropic.com/api/oauth/usage"
	codexUsageURL                    = "https://chatgpt.com/backend-api/wham/usage"
	maxUsageResponseBytes            = 1 << 20
)

const (
	methodPluginRegister    = "plugin.register"
	methodPluginReconfigure = "plugin.reconfigure"
	methodSchedulerPick     = "scheduler.pick"
	methodHostAuthList      = "host.auth.list"
	methodHostAuthGet       = "host.auth.get"
)

type envelope struct {
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *envelopeError  `json:"error,omitempty"`
}

type envelopeError struct {
	Code       string `json:"code"`
	Message    string `json:"message"`
	Retryable  bool   `json:"retryable,omitempty"`
	HTTPStatus int    `json:"http_status,omitempty"`
}

type lifecycleRequest struct {
	ConfigYAML []byte `json:"config_yaml"`
}

type pluginConfig struct {
	ReservePercent            float64            `yaml:"reserve_percent"`
	ReserveByAuthID           map[string]float64 `yaml:"reserve_percent_by_auth_id"`
	WeeklyReservePercent      *float64           `yaml:"weekly_reserve_percent"`
	WeeklyReserveByAuthID     map[string]float64 `yaml:"weekly_reserve_percent_by_auth_id"`
	StatePath                 string             `yaml:"state_path"`
	PollIntervalSeconds       int                `yaml:"poll_interval_seconds"`
	ErrorRetryIntervalSeconds int                `yaml:"error_retry_interval_seconds"`
	RequestTimeoutSeconds     int                `yaml:"request_timeout_seconds"`
	FailClosed                bool               `yaml:"fail_closed"`
}

// accountReserves holds the percentage withheld from each upstream rolling
// window for one account. A reserve of 0 leaves that window unmanaged.
type accountReserves struct {
	FiveHour float64
	Weekly   float64
}

// managed reports whether any window is reserved. An unmanaged account is never
// polled and never withheld.
func (r accountReserves) managed() bool {
	return r.FiveHour > 0 || r.Weekly > 0
}

// reservesFor resolves the reserved percentages for one upstream account,
// most specific setting first: a per-account weekly override beats the
// per-account reserve, which beats the global weekly reserve, which beats the
// global reserve. The weekly window therefore inherits whatever the five-hour
// window reserves unless something more specific overrides it.
func (c pluginConfig) reservesFor(authID string) accountReserves {
	key := normalizeAuthID(authID)
	reserves := accountReserves{FiveHour: c.ReservePercent, Weekly: c.ReservePercent}
	if c.WeeklyReservePercent != nil {
		reserves.Weekly = *c.WeeklyReservePercent
	}
	if reserve, exists := c.ReserveByAuthID[key]; exists {
		reserves.FiveHour = reserve
		reserves.Weekly = reserve
	}
	if reserve, exists := c.WeeklyReserveByAuthID[key]; exists {
		reserves.Weekly = reserve
	}
	return reserves
}

// normalizeAuthID accepts either the host auth file name or the same name
// without its .json suffix, so config keys can stay readable.
func normalizeAuthID(authID string) string {
	return strings.TrimSuffix(strings.ToLower(strings.TrimSpace(authID)), ".json")
}

type registration struct {
	SchemaVersion uint32                 `json:"schema_version"`
	Metadata      metadata               `json:"metadata"`
	Capabilities  registrationCapability `json:"capabilities"`
}

type registrationCapability struct {
	Scheduler bool `json:"scheduler"`
}

type metadata struct {
	Name             string
	Version          string
	Author           string
	GitHubRepository string
	Logo             string
	ConfigFields     []configField
}

type configField struct {
	Name        string
	Type        string
	EnumValues  []string
	Description string
}

type schedulerPickRequest struct {
	Provider   string
	Providers  []string
	Model      string
	Candidates []schedulerAuthCandidate
}

type schedulerAuthCandidate struct {
	ID       string
	Provider string
	Priority int
}

type schedulerPickResponse struct {
	AuthID          string
	DelegateBuiltin string
	Handled         bool
}

// windowState is one upstream rolling quota window. Applicable is false when
// the provider reports no such limit for the account, which is a definitive
// answer rather than a missing observation.
type windowState struct {
	Applicable      bool      `json:"applicable"`
	UtilizedPercent float64   `json:"utilized_percent"`
	ResetAt         time.Time `json:"reset_at"`
}

type accountState struct {
	Provider  string      `json:"provider"`
	FiveHour  windowState `json:"five_hour"`
	Weekly    windowState `json:"weekly"`
	UpdatedAt time.Time   `json:"updated_at"`
}

type persistedState struct {
	Version  int                             `json:"version"`
	Accounts map[string]persistedQuotaStatus `json:"accounts"`
}

type persistedQuotaStatus struct {
	Known     bool         `json:"known,omitempty"`
	State     accountState `json:"state"`
	CheckedAt time.Time    `json:"checked_at,omitempty"`
	RetryAt   time.Time    `json:"retry_at,omitempty"`
	Err       string       `json:"error,omitempty"`
}

// accountStateV1 is the single-window account state written by plugin versions
// before weekly windows existed. Its scalars describe the five-hour window.
type accountStateV1 struct {
	Provider        string    `json:"provider"`
	UtilizedPercent float64   `json:"utilized_percent"`
	ResetAt         time.Time `json:"reset_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type persistedStateV1 struct {
	Version  int                       `json:"version"`
	Accounts map[string]accountStateV1 `json:"accounts"`
}

type persistedStateV2 struct {
	Version  int                               `json:"version"`
	Accounts map[string]persistedQuotaStatusV2 `json:"accounts"`
}

type persistedQuotaStatusV2 struct {
	Known      bool           `json:"known,omitempty"`
	Applicable bool           `json:"applicable,omitempty"`
	State      accountStateV1 `json:"state,omitempty"`
	CheckedAt  time.Time      `json:"checked_at,omitempty"`
	RetryAt    time.Time      `json:"retry_at,omitempty"`
	Err        string         `json:"error,omitempty"`
}

// migrateV1State lifts a pre-weekly observation into the windowed layout. The
// weekly window stays inapplicable until the next upstream poll fills it in.
func migrateV1State(state accountStateV1, applicable bool) accountState {
	return accountState{
		Provider: state.Provider,
		FiveHour: windowState{
			Applicable:      applicable,
			UtilizedPercent: state.UtilizedPercent,
			ResetAt:         state.ResetAt,
		},
		UpdatedAt: state.UpdatedAt,
	}
}

type quotaStatus struct {
	Known     bool
	State     accountState
	CheckedAt time.Time
	RetryAt   time.Time
	Err       string
}

type authCredential struct {
	AccessToken string `json:"access_token"`
	AccountID   string `json:"account_id"`
}

type credentialResult struct {
	Credential authCredential
	Err        error
}

type quotaObservation struct {
	FiveHour windowState
	Weekly   windowState
}

type credentialLoader func([]schedulerAuthCandidate) map[string]credentialResult
type quotaFetcher func(string, authCredential, time.Duration) (quotaObservation, error)

type quotaLimiter struct {
	mu                 sync.Mutex
	refreshMu          sync.Mutex
	config             pluginConfig
	statuses           map[string]quotaStatus
	cursor             map[string]int
	now                func() time.Time
	loadCredentials    credentialLoader
	fetchProviderQuota quotaFetcher
}

var limiter = newQuotaLimiter()

func main() {}

func defaultConfig() pluginConfig {
	return pluginConfig{
		ReservePercent:            defaultReservePercent,
		StatePath:                 defaultStatePath,
		PollIntervalSeconds:       int(defaultPollInterval / time.Second),
		ErrorRetryIntervalSeconds: int(defaultErrorRetryInterval / time.Second),
		RequestTimeoutSeconds:     int(defaultRequestTimeout / time.Second),
		FailClosed:                true,
	}
}

func newQuotaLimiter() *quotaLimiter {
	return &quotaLimiter{
		config:             defaultConfig(),
		statuses:           make(map[string]quotaStatus),
		cursor:             make(map[string]int),
		now:                time.Now,
		loadCredentials:    loadHostCredentials,
		fetchProviderQuota: fetchProviderQuota,
	}
}

//export cliproxy_plugin_init
func cliproxy_plugin_init(host *C.cliproxy_host_api, plugin *C.cliproxy_plugin_api) C.int {
	if host == nil || plugin == nil {
		return 1
	}
	C.store_host_api(host)
	plugin.abi_version = C.uint32_t(abiVersion)
	plugin.call = C.cliproxy_plugin_call_fn(C.cliproxyPluginCall)
	plugin.free_buffer = C.cliproxy_plugin_free_fn(C.cliproxyPluginFree)
	plugin.shutdown = C.cliproxy_plugin_shutdown_fn(C.cliproxyPluginShutdown)
	return 0
}

//export cliproxyPluginCall
func cliproxyPluginCall(method *C.char, request *C.uint8_t, requestLen C.size_t, response *C.cliproxy_buffer) C.int {
	if response != nil {
		response.ptr = nil
		response.len = 0
	}
	if method == nil {
		writeResponse(response, errorEnvelope("invalid_method", "method is required"))
		return 1
	}

	var requestBytes []byte
	if request != nil && requestLen > 0 {
		requestBytes = C.GoBytes(unsafe.Pointer(request), C.int(requestLen))
	}
	raw, errHandle := handleMethod(C.GoString(method), requestBytes)
	if errHandle != nil {
		writeResponse(response, errorEnvelope("plugin_error", errHandle.Error()))
		return 1
	}
	writeResponse(response, raw)
	return 0
}

//export cliproxyPluginFree
func cliproxyPluginFree(ptr unsafe.Pointer, _ C.size_t) {
	if ptr != nil {
		C.free(ptr)
	}
}

//export cliproxyPluginShutdown
func cliproxyPluginShutdown() {
	_ = limiter.persist()
}

func handleMethod(method string, request []byte) ([]byte, error) {
	switch method {
	case methodPluginRegister, methodPluginReconfigure:
		if errConfigure := limiter.configure(request); errConfigure != nil {
			return nil, errConfigure
		}
		return okEnvelope(pluginRegistration())
	case methodSchedulerPick:
		return limiter.pick(request)
	default:
		return errorEnvelope("unknown_method", "unknown method: "+method), nil
	}
}

func pluginRegistration() registration {
	return registration{
		SchemaVersion: schemaVersion,
		Metadata: metadata{
			Name:             "account-quota",
			Version:          pluginVersion,
			Author:           "iceice666",
			GitHubRepository: "https://github.com/iceice666/dotfiles",
			ConfigFields: []configField{
				{
					Name:        "reserve_percent",
					Type:        "number",
					Description: "Default percentage of each Codex or Claude rolling quota window reserved from proxy traffic. Applies to both the five-hour and the weekly window. 0 disables the reserve.",
				},
				{
					Name:        "reserve_percent_by_auth_id",
					Type:        "object",
					Description: "Per-account reserve overrides keyed by auth file name, with or without the .json suffix. Each override covers both windows and takes precedence over weekly_reserve_percent.",
				},
				{
					Name:        "weekly_reserve_percent",
					Type:        "number",
					Description: "Percentage of the weekly quota window reserved from proxy traffic. Defaults to reserve_percent. Accounts listed in reserve_percent_by_auth_id ignore this value; give them a weekly_reserve_percent_by_auth_id entry instead. Accounts whose provider reports no weekly limit are unaffected.",
				},
				{
					Name:        "weekly_reserve_percent_by_auth_id",
					Type:        "object",
					Description: "Per-account weekly reserve overrides keyed by auth file name. Takes precedence over every other reserve setting.",
				},
				{
					Name:        "state_path",
					Type:        "string",
					Description: "Persistent state file used for accounts blocked until their upstream reset time.",
				},
				{
					Name:        "poll_interval_seconds",
					Type:        "number",
					Description: "Maximum age of a successful or failed upstream quota observation.",
				},
				{
					Name:        "error_retry_interval_seconds",
					Type:        "number",
					Description: "Backoff after an upstream quota lookup fails, including HTTP 429 responses.",
				},
				{
					Name:        "request_timeout_seconds",
					Type:        "number",
					Description: "Timeout for each provider usage request.",
				},
				{
					Name:        "fail_closed",
					Type:        "boolean",
					Description: "Exclude accounts whose quota cannot be determined.",
				},
			},
		},
		Capabilities: registrationCapability{Scheduler: true},
	}
}

func (l *quotaLimiter) configure(raw []byte) error {
	var req lifecycleRequest
	if len(raw) > 0 {
		if errUnmarshal := json.Unmarshal(raw, &req); errUnmarshal != nil {
			return fmt.Errorf("decode lifecycle request: %w", errUnmarshal)
		}
	}

	cfg := defaultConfig()
	if len(req.ConfigYAML) > 0 {
		if errUnmarshal := yaml.Unmarshal(req.ConfigYAML, &cfg); errUnmarshal != nil {
			return fmt.Errorf("decode plugin config: %w", errUnmarshal)
		}
	}
	cfg.StatePath = strings.TrimSpace(cfg.StatePath)
	reserves, errReserves := normalizeReserveOverrides("reserve_percent_by_auth_id", cfg.ReserveByAuthID)
	if errReserves != nil {
		return errReserves
	}
	cfg.ReserveByAuthID = reserves
	weeklyReserves, errWeekly := normalizeReserveOverrides("weekly_reserve_percent_by_auth_id", cfg.WeeklyReserveByAuthID)
	if errWeekly != nil {
		return errWeekly
	}
	cfg.WeeklyReserveByAuthID = weeklyReserves
	if errValidate := validateReservePercent("reserve_percent", cfg.ReservePercent); errValidate != nil {
		return errValidate
	}
	if cfg.WeeklyReservePercent != nil {
		if errValidate := validateReservePercent("weekly_reserve_percent", *cfg.WeeklyReservePercent); errValidate != nil {
			return errValidate
		}
	}
	if cfg.StatePath == "" {
		return errors.New("state_path is required")
	}
	if cfg.PollIntervalSeconds <= 0 {
		return errors.New("poll_interval_seconds must be greater than 0")
	}
	if cfg.ErrorRetryIntervalSeconds <= 0 {
		return errors.New("error_retry_interval_seconds must be greater than 0")
	}
	if cfg.RequestTimeoutSeconds <= 0 {
		return errors.New("request_timeout_seconds must be greater than 0")
	}

	statuses, errLoad := loadPersistedState(cfg.StatePath, l.now())
	if errLoad != nil {
		return errLoad
	}

	l.mu.Lock()
	l.config = cfg
	l.statuses = statuses
	l.cursor = make(map[string]int)
	l.mu.Unlock()
	return nil
}

func normalizeReserveOverrides(field string, overrides map[string]float64) (map[string]float64, error) {
	normalized := make(map[string]float64, len(overrides))
	for authID, reserve := range overrides {
		key := normalizeAuthID(authID)
		if key == "" {
			return nil, fmt.Errorf("%s keys must not be empty", field)
		}
		if errValidate := validateReservePercent(fmt.Sprintf("%s[%q]", field, authID), reserve); errValidate != nil {
			return nil, errValidate
		}
		normalized[key] = reserve
	}
	return normalized, nil
}

func validateReservePercent(field string, reserve float64) error {
	if reserve < 0 || reserve >= 100 || math.IsNaN(reserve) {
		return fmt.Errorf("%s must be at least 0 and less than 100", field)
	}
	return nil
}

func loadPersistedState(path string, now time.Time) (map[string]quotaStatus, error) {
	statuses := make(map[string]quotaStatus)
	raw, errRead := os.ReadFile(path)
	if errors.Is(errRead, os.ErrNotExist) {
		return statuses, nil
	}
	if errRead != nil {
		return nil, fmt.Errorf("read quota state: %w", errRead)
	}

	var header struct {
		Version int `json:"version"`
	}
	if errUnmarshal := json.Unmarshal(raw, &header); errUnmarshal != nil {
		return nil, fmt.Errorf("decode quota state: %w", errUnmarshal)
	}
	switch header.Version {
	case 1:
		var persisted persistedStateV1
		if errUnmarshal := json.Unmarshal(raw, &persisted); errUnmarshal != nil {
			return nil, fmt.Errorf("decode quota state version 1: %w", errUnmarshal)
		}
		for id, state := range persisted.Accounts {
			id = strings.TrimSpace(id)
			if id == "" || !isTargetProvider(state.Provider) || !state.ResetAt.After(now) {
				continue
			}
			statuses[id] = quotaStatus{
				Known:     true,
				State:     migrateV1State(state, true),
				CheckedAt: state.UpdatedAt,
			}
		}
	case 2:
		var persisted persistedStateV2
		if errUnmarshal := json.Unmarshal(raw, &persisted); errUnmarshal != nil {
			return nil, fmt.Errorf("decode quota state version 2: %w", errUnmarshal)
		}
		for id, persistedStatus := range persisted.Accounts {
			id = strings.TrimSpace(id)
			if id == "" {
				continue
			}
			status := quotaStatus{
				Known:     persistedStatus.Known,
				State:     migrateV1State(persistedStatus.State, persistedStatus.Applicable),
				CheckedAt: persistedStatus.CheckedAt,
				RetryAt:   persistedStatus.RetryAt,
				Err:       persistedStatus.Err,
			}
			if retained, keep := retainLoadedStatus(status, now); keep {
				statuses[id] = retained
			}
		}
	case stateVersion:
		var persisted persistedState
		if errUnmarshal := json.Unmarshal(raw, &persisted); errUnmarshal != nil {
			return nil, fmt.Errorf("decode quota state version %d: %w", stateVersion, errUnmarshal)
		}
		for id, persistedStatus := range persisted.Accounts {
			id = strings.TrimSpace(id)
			if id == "" {
				continue
			}
			status := quotaStatus{
				Known:     persistedStatus.Known,
				State:     persistedStatus.State,
				CheckedAt: persistedStatus.CheckedAt,
				RetryAt:   persistedStatus.RetryAt,
				Err:       persistedStatus.Err,
			}
			if retained, keep := retainLoadedStatus(status, now); keep {
				statuses[id] = retained
			}
		}
	default:
		return nil, fmt.Errorf("unsupported quota state version %d", header.Version)
	}
	return statuses, nil
}

// retainLoadedStatus drops the parts of a persisted status that expired while
// the plugin was down, and reports whether anything worth keeping is left.
func retainLoadedStatus(status quotaStatus, now time.Time) (quotaStatus, bool) {
	if !status.RetryAt.After(now) {
		status.RetryAt = time.Time{}
		status.Err = ""
	}
	if status.Known && !observationStillValid(status, now) {
		status.Known = false
		status.State = accountState{}
	}
	return status, status.Known || status.RetryAt.After(now)
}

func (l *quotaLimiter) pick(raw []byte) ([]byte, error) {
	var req schedulerPickRequest
	if errUnmarshal := json.Unmarshal(raw, &req); errUnmarshal != nil {
		return nil, fmt.Errorf("decode scheduler request: %w", errUnmarshal)
	}
	if len(req.Candidates) == 0 || !requestTargetsLimitedProvider(req) {
		return okEnvelope(schedulerPickResponse{Handled: false})
	}

	l.refreshCandidates(req.Candidates)

	now := l.now()
	l.mu.Lock()
	defer l.mu.Unlock()

	blocked := 0
	unknown := 0
	eligible := make([]schedulerAuthCandidate, 0, len(req.Candidates))
	for _, candidate := range req.Candidates {
		if !isManagedCandidate(candidate, l.config) {
			eligible = append(eligible, candidate)
			continue
		}
		status, exists := l.statuses[candidate.ID]
		if !exists || !status.Known {
			if l.config.FailClosed {
				unknown++
				continue
			}
			eligible = append(eligible, candidate)
			continue
		}
		if accountReserved(status, l.config.reservesFor(candidate.ID), now) {
			blocked++
			continue
		}
		eligible = append(eligible, candidate)
	}
	if blocked == 0 && unknown == 0 {
		return okEnvelope(schedulerPickResponse{Handled: false})
	}
	if len(eligible) == 0 {
		if unknown > 0 {
			return statusErrorEnvelope(
				"quota_unavailable",
				fmt.Sprintf("quota could not be determined for %d eligible accounts", unknown),
				http.StatusServiceUnavailable,
				true,
			), nil
		}
		return statusErrorEnvelope(
			"quota_reserved",
			fmt.Sprintf("all %d eligible accounts reached a reserved usage ceiling", blocked),
			http.StatusTooManyRequests,
			true,
		), nil
	}

	selected := l.selectCandidate(req, eligible)
	return okEnvelope(schedulerPickResponse{AuthID: selected.ID, Handled: true})
}

func (l *quotaLimiter) refreshCandidates(candidates []schedulerAuthCandidate) {
	l.refreshMu.Lock()
	defer l.refreshMu.Unlock()

	now := l.now()
	l.mu.Lock()
	cfg := l.config
	stale := make([]schedulerAuthCandidate, 0, len(candidates))
	for _, candidate := range candidates {
		if !isManagedCandidate(candidate, cfg) {
			continue
		}
		status, exists := l.statuses[candidate.ID]
		if shouldRefresh(status, exists, cfg, candidate.ID, now) {
			stale = append(stale, candidate)
		}
	}
	l.mu.Unlock()
	if len(stale) == 0 {
		return
	}

	credentials := l.loadCredentials(stale)
	previous := make(map[string]quotaStatus, len(stale))
	l.mu.Lock()
	for _, candidate := range stale {
		previous[candidate.ID] = l.statuses[candidate.ID]
	}
	l.mu.Unlock()
	results := make(map[string]quotaStatus, len(stale))
	var resultsMu sync.Mutex
	var wait sync.WaitGroup
	wait.Add(len(stale))
	for _, candidate := range stale {
		candidate := candidate
		go func() {
			defer wait.Done()
			status := quotaStatus{CheckedAt: now}
			credential, ok := credentials[candidate.ID]
			if !ok {
				status.Err = "credential was not returned by the host"
			} else if credential.Err != nil {
				status.Err = credential.Err.Error()
			} else {
				observation, errFetch := l.fetchProviderQuota(
					normalizeProvider(candidate.Provider),
					credential.Credential,
					time.Duration(cfg.RequestTimeoutSeconds)*time.Second,
				)
				if errFetch != nil {
					status.Err = errFetch.Error()
				} else {
					status.Known = true
					status.State = accountState{
						Provider:  normalizeProvider(candidate.Provider),
						FiveHour:  observation.FiveHour,
						Weekly:    observation.Weekly,
						UpdatedAt: now,
					}
				}
			}
			if status.Err != "" {
				status.RetryAt = now.Add(time.Duration(cfg.ErrorRetryIntervalSeconds) * time.Second)
				if cached := previous[candidate.ID]; observationStillValid(cached, now) {
					status.Known = cached.Known
					status.State = cached.State
				}
			}
			resultsMu.Lock()
			results[candidate.ID] = status
			resultsMu.Unlock()
		}()
	}
	wait.Wait()

	l.mu.Lock()
	for id, status := range results {
		l.statuses[id] = status
	}
	l.mu.Unlock()
	_ = l.persist()
}

// isManagedCandidate reports whether the plugin polls and gates this candidate
// at all. pick and refreshCandidates must agree, or an account would be
// withheld on an observation the refresh loop never takes.
func isManagedCandidate(candidate schedulerAuthCandidate, cfg pluginConfig) bool {
	return isTargetProvider(candidate.Provider) && cfg.reservesFor(candidate.ID).managed()
}

func shouldRefresh(status quotaStatus, exists bool, cfg pluginConfig, authID string, now time.Time) bool {
	if !exists {
		return true
	}
	if !status.RetryAt.IsZero() {
		return !now.Before(status.RetryAt)
	}
	// Once any observed window has rolled over the whole observation is stale,
	// even if another window still withholds the account: the plugin would
	// otherwise keep a figure it can no longer vouch for, and discard it on the
	// next restart or failed refresh.
	if status.Known && !observationStillValid(status, now) {
		return true
	}
	// A reserved account cannot become eligible before the window that
	// reserved it rolls over, so wait for that instead of polling every
	// interval. With both windows reserved that is the earlier of the two
	// resets: the five-hour window can free the account while the weekly one
	// still holds it, and the plugin must observe that to keep the weekly block
	// accurate. The wait is capped at five hours because upstream weekly
	// utilization has been seen to fall before its advertised reset, and a
	// weekly reset can otherwise be a week away. A reserved window with no
	// reset time falls through to the ordinary poll interval.
	if reset, reserved := earliestReservedReset(status, cfg.reservesFor(authID), now); reserved && !reset.IsZero() {
		if capped := status.CheckedAt.Add(fiveHours); capped.Before(reset) {
			reset = capped
		}
		return !now.Before(reset)
	}
	return now.Sub(status.CheckedAt) >= time.Duration(cfg.PollIntervalSeconds)*time.Second
}

// observationStillValid reports whether a cached observation can still stand in
// for a fresh one. It expires once any applicable window has rolled over, since
// the utilization recorded for that window no longer describes the account.
func observationStillValid(status quotaStatus, now time.Time) bool {
	if !status.Known {
		return false
	}
	for _, window := range []windowState{status.State.FiveHour, status.State.Weekly} {
		if window.Applicable && !window.ResetAt.IsZero() && !window.ResetAt.After(now) {
			return false
		}
	}
	return true
}

// windowReserved reports whether one rolling window has consumed everything up
// to its reserve. A window whose reset time has passed is treated as free: the
// upstream counter has rolled over even though the plugin has not re-polled.
func windowReserved(window windowState, reserve float64, now time.Time) bool {
	return reserve > 0 &&
		window.Applicable &&
		window.UtilizedPercent >= 100-reserve &&
		(window.ResetAt.IsZero() || window.ResetAt.After(now))
}

// accountReserved withholds an account when any reserved window is exhausted.
// The windows are independent limits upstream, so the tighter one governs.
func accountReserved(status quotaStatus, reserves accountReserves, now time.Time) bool {
	if !status.Known {
		return false
	}
	return windowReserved(status.State.FiveHour, reserves.FiveHour, now) ||
		windowReserved(status.State.Weekly, reserves.Weekly, now)
}

// earliestReservedReset returns the soonest reset among the windows currently
// withholding the account, and whether any window withholds it at all. A zero
// reset time means a reserved window carries no upstream reset, so the caller
// cannot wait on it.
func earliestReservedReset(status quotaStatus, reserves accountReserves, now time.Time) (time.Time, bool) {
	var earliest time.Time
	reserved := false
	for _, window := range []struct {
		state   windowState
		reserve float64
	}{
		{status.State.FiveHour, reserves.FiveHour},
		{status.State.Weekly, reserves.Weekly},
	} {
		if !status.Known || !windowReserved(window.state, window.reserve, now) {
			continue
		}
		reserved = true
		if window.state.ResetAt.IsZero() {
			return time.Time{}, true
		}
		if earliest.IsZero() || window.state.ResetAt.Before(earliest) {
			earliest = window.state.ResetAt
		}
	}
	return earliest, reserved
}

func requestTargetsLimitedProvider(req schedulerPickRequest) bool {
	if isTargetProvider(req.Provider) {
		return true
	}
	for _, provider := range req.Providers {
		if isTargetProvider(provider) {
			return true
		}
	}
	for _, candidate := range req.Candidates {
		if isTargetProvider(candidate.Provider) {
			return true
		}
	}
	return false
}

func (l *quotaLimiter) selectCandidate(req schedulerPickRequest, candidates []schedulerAuthCandidate) schedulerAuthCandidate {
	highestPriority := candidates[0].Priority
	for _, candidate := range candidates[1:] {
		if candidate.Priority > highestPriority {
			highestPriority = candidate.Priority
		}
	}

	preferred := make([]schedulerAuthCandidate, 0, len(candidates))
	for _, candidate := range candidates {
		if candidate.Priority == highestPriority {
			preferred = append(preferred, candidate)
		}
	}
	sort.Slice(preferred, func(i, j int) bool { return preferred[i].ID < preferred[j].ID })

	key := strings.ToLower(strings.TrimSpace(req.Provider)) + "\x00" + strings.TrimSpace(req.Model)
	index := l.cursor[key] % len(preferred)
	l.cursor[key] = (index + 1) % len(preferred)
	return preferred[index]
}

func loadHostCredentials(candidates []schedulerAuthCandidate) map[string]credentialResult {
	results := make(map[string]credentialResult, len(candidates))
	rawList, errList := callHost(methodHostAuthList, struct{}{})
	if errList != nil {
		for _, candidate := range candidates {
			results[candidate.ID] = credentialResult{Err: fmt.Errorf("list host auth: %w", errList)}
		}
		return results
	}

	var list hostAuthListResponse
	if errUnmarshal := json.Unmarshal(rawList, &list); errUnmarshal != nil {
		for _, candidate := range candidates {
			results[candidate.ID] = credentialResult{Err: fmt.Errorf("decode host auth list: %w", errUnmarshal)}
		}
		return results
	}

	indices := make(map[string]string, len(list.Files)*2)
	for _, entry := range list.Files {
		if entry.ID != "" {
			indices[entry.ID] = entry.AuthIndex
		}
		if entry.AuthIndex != "" {
			indices[entry.AuthIndex] = entry.AuthIndex
		}
	}
	for _, candidate := range candidates {
		authIndex := strings.TrimSpace(indices[candidate.ID])
		if authIndex == "" {
			results[candidate.ID] = credentialResult{Err: errors.New("candidate is absent from host auth list")}
			continue
		}
		rawGet, errGet := callHost(methodHostAuthGet, hostAuthGetRequest{AuthIndex: authIndex})
		if errGet != nil {
			results[candidate.ID] = credentialResult{Err: fmt.Errorf("get host auth: %w", errGet)}
			continue
		}
		var response hostAuthGetResponse
		if errUnmarshal := json.Unmarshal(rawGet, &response); errUnmarshal != nil {
			results[candidate.ID] = credentialResult{Err: fmt.Errorf("decode host auth: %w", errUnmarshal)}
			continue
		}
		var credential authCredential
		if errUnmarshal := json.Unmarshal(response.JSON, &credential); errUnmarshal != nil {
			results[candidate.ID] = credentialResult{Err: fmt.Errorf("decode credential JSON: %w", errUnmarshal)}
			continue
		}
		if strings.TrimSpace(credential.AccessToken) == "" {
			results[candidate.ID] = credentialResult{Err: errors.New("credential has no access_token")}
			continue
		}
		results[candidate.ID] = credentialResult{Credential: credential}
	}
	return results
}

type hostAuthListResponse struct {
	Files []hostAuthFileEntry `json:"files"`
}

type hostAuthFileEntry struct {
	ID        string `json:"id,omitempty"`
	AuthIndex string `json:"auth_index,omitempty"`
}

type hostAuthGetRequest struct {
	AuthIndex string `json:"auth_index"`
}

type hostAuthGetResponse struct {
	JSON json.RawMessage `json:"json"`
}

func callHost(method string, payload any) (json.RawMessage, error) {
	rawPayload, errMarshal := json.Marshal(payload)
	if errMarshal != nil {
		return nil, fmt.Errorf("marshal host callback payload %s: %w", method, errMarshal)
	}
	cMethod := C.CString(method)
	defer C.free(unsafe.Pointer(cMethod))

	var response C.cliproxy_buffer
	var requestPtr *C.uint8_t
	if len(rawPayload) > 0 {
		cPayload := C.CBytes(rawPayload)
		if cPayload == nil {
			return nil, fmt.Errorf("allocate host callback payload %s", method)
		}
		defer C.free(cPayload)
		requestPtr = (*C.uint8_t)(cPayload)
	}
	callCode := C.call_host_api(cMethod, requestPtr, C.size_t(len(rawPayload)), &response)
	var rawResponse []byte
	if response.ptr != nil && response.len > 0 {
		rawResponse = C.GoBytes(response.ptr, C.int(response.len))
	}
	if response.ptr != nil {
		C.free_host_buffer(response.ptr, response.len)
	}
	if len(rawResponse) == 0 {
		return nil, fmt.Errorf("host callback %s returned no response, code=%d", method, int(callCode))
	}

	var env envelope
	if errUnmarshal := json.Unmarshal(rawResponse, &env); errUnmarshal != nil {
		return nil, fmt.Errorf("decode host callback envelope %s: %w", method, errUnmarshal)
	}
	if !env.OK {
		if env.Error != nil {
			return nil, fmt.Errorf("%s: %s", env.Error.Code, env.Error.Message)
		}
		return nil, fmt.Errorf("host callback %s failed", method)
	}
	if callCode != 0 {
		return nil, fmt.Errorf("host callback %s returned code=%d", method, int(callCode))
	}
	return append(json.RawMessage(nil), env.Result...), nil
}

func fetchProviderQuota(provider string, credential authCredential, timeout time.Duration) (quotaObservation, error) {
	client := &http.Client{Timeout: timeout}
	switch normalizeProvider(provider) {
	case "claude":
		return fetchClaudeQuota(client, credential)
	case "codex":
		return fetchCodexQuota(client, credential)
	default:
		return quotaObservation{}, fmt.Errorf("unsupported quota provider %q", provider)
	}
}

func fetchClaudeQuota(client *http.Client, credential authCredential) (quotaObservation, error) {
	req, errRequest := http.NewRequest(http.MethodGet, claudeUsageURL, nil)
	if errRequest != nil {
		return quotaObservation{}, errRequest
	}
	req.Header.Set("Authorization", "Bearer "+credential.AccessToken)
	req.Header.Set("anthropic-beta", "oauth-2025-04-20")
	body, errDo := doUsageRequest(client, req)
	if errDo != nil {
		return quotaObservation{}, errDo
	}
	return parseClaudeUsage(body)
}

func fetchCodexQuota(client *http.Client, credential authCredential) (quotaObservation, error) {
	req, errRequest := http.NewRequest(http.MethodGet, codexUsageURL, nil)
	if errRequest != nil {
		return quotaObservation{}, errRequest
	}
	req.Header.Set("Authorization", "Bearer "+credential.AccessToken)
	if accountID := strings.TrimSpace(credential.AccountID); accountID != "" {
		req.Header.Set("ChatGPT-Account-Id", accountID)
	}
	body, errDo := doUsageRequest(client, req)
	if errDo != nil {
		return quotaObservation{}, errDo
	}
	return parseCodexUsage(body, time.Now())
}

func doUsageRequest(client *http.Client, req *http.Request) ([]byte, error) {
	resp, errDo := client.Do(req)
	if errDo != nil {
		return nil, errDo
	}
	defer resp.Body.Close()
	body, errRead := io.ReadAll(io.LimitReader(resp.Body, maxUsageResponseBytes+1))
	if errRead != nil {
		return nil, errRead
	}
	if len(body) > maxUsageResponseBytes {
		return nil, errors.New("usage response exceeds 1 MiB")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("usage endpoint returned HTTP %d", resp.StatusCode)
	}
	return body, nil
}

// claudeUsageResponse covers the account-wide windows only. The model-scoped
// seven_day_opus and seven_day_sonnet limits are deliberately ignored: the
// scheduler decides per account, so folding a model-scoped limit in here would
// withhold an account from every model because one model is exhausted.
type claudeUsageResponse struct {
	FiveHour *claudeUsageWindow `json:"five_hour"`
	SevenDay *claudeUsageWindow `json:"seven_day"`
}

type claudeUsageWindow struct {
	Utilization float64 `json:"utilization"`
	ResetsAt    string  `json:"resets_at"`
}

func parseClaudeUsage(raw []byte) (quotaObservation, error) {
	var response claudeUsageResponse
	if errUnmarshal := json.Unmarshal(raw, &response); errUnmarshal != nil {
		return quotaObservation{}, fmt.Errorf("decode Claude usage: %w", errUnmarshal)
	}
	fiveHour, errFiveHour := parseClaudeWindow(response.FiveHour, "five-hour")
	if errFiveHour != nil {
		return quotaObservation{}, errFiveHour
	}
	weekly, errWeekly := parseClaudeWindow(response.SevenDay, "weekly")
	if errWeekly != nil {
		return quotaObservation{}, errWeekly
	}
	return quotaObservation{FiveHour: fiveHour, Weekly: weekly}, nil
}

func parseClaudeWindow(window *claudeUsageWindow, label string) (windowState, error) {
	if window == nil {
		return windowState{}, nil
	}
	if errValidate := validateUtilization(window.Utilization); errValidate != nil {
		return windowState{}, fmt.Errorf("decode Claude %s utilization: %w", label, errValidate)
	}
	var resetAt time.Time
	if rawReset := strings.TrimSpace(window.ResetsAt); rawReset != "" {
		parsed, errParse := time.Parse(time.RFC3339Nano, rawReset)
		if errParse != nil {
			return windowState{}, fmt.Errorf("decode Claude %s reset: %w", label, errParse)
		}
		resetAt = parsed
	}
	return windowState{
		Applicable:      true,
		UtilizedPercent: window.Utilization,
		ResetAt:         resetAt,
	}, nil
}

type codexUsageResponse struct {
	RateLimit *struct {
		PrimaryWindow   *codexUsageWindow `json:"primary_window"`
		SecondaryWindow *codexUsageWindow `json:"secondary_window"`
	} `json:"rate_limit"`
}

type codexUsageWindow struct {
	UsedPercent        float64 `json:"used_percent"`
	LimitWindowSeconds int64   `json:"limit_window_seconds"`
	ResetAt            int64   `json:"reset_at"`
	ResetAfterSeconds  int64   `json:"reset_after_seconds"`
}

func parseCodexUsage(raw []byte, now time.Time) (quotaObservation, error) {
	var response codexUsageResponse
	if errUnmarshal := json.Unmarshal(raw, &response); errUnmarshal != nil {
		return quotaObservation{}, fmt.Errorf("decode Codex usage: %w", errUnmarshal)
	}
	if response.RateLimit == nil {
		return quotaObservation{}, errors.New("Codex usage response has no rate_limit")
	}
	// Codex labels its windows primary and secondary rather than by duration,
	// and which one is the five-hour window varies by account, so match on the
	// advertised window length instead of the field name.
	windows := []*codexUsageWindow{response.RateLimit.PrimaryWindow, response.RateLimit.SecondaryWindow}
	fiveHour, errFiveHour := parseCodexWindow(windows, fiveHours, "five-hour", now)
	if errFiveHour != nil {
		return quotaObservation{}, errFiveHour
	}
	weekly, errWeekly := parseCodexWindow(windows, sevenDays, "weekly", now)
	if errWeekly != nil {
		return quotaObservation{}, errWeekly
	}
	return quotaObservation{FiveHour: fiveHour, Weekly: weekly}, nil
}

func parseCodexWindow(windows []*codexUsageWindow, length time.Duration, label string, now time.Time) (windowState, error) {
	var selected *codexUsageWindow
	for _, window := range windows {
		if window == nil || window.LimitWindowSeconds != int64(length/time.Second) {
			continue
		}
		if selected == nil || window.UsedPercent > selected.UsedPercent {
			selected = window
		}
	}
	if selected == nil {
		return windowState{}, nil
	}
	if errValidate := validateUtilization(selected.UsedPercent); errValidate != nil {
		return windowState{}, fmt.Errorf("decode Codex %s utilization: %w", label, errValidate)
	}
	var resetAt time.Time
	if selected.ResetAt > 0 {
		resetAt = time.Unix(selected.ResetAt, 0)
	} else if selected.ResetAfterSeconds > 0 {
		resetAt = now.Add(time.Duration(selected.ResetAfterSeconds) * time.Second)
	}
	return windowState{
		Applicable:      true,
		UtilizedPercent: selected.UsedPercent,
		ResetAt:         resetAt,
	}, nil
}

func validateUtilization(value float64) error {
	if math.IsNaN(value) || math.IsInf(value, 0) || value < 0 || value > 100 {
		return fmt.Errorf("value %.3f is outside 0..100", value)
	}
	return nil
}

func normalizeProvider(provider string) string {
	provider = strings.ToLower(strings.TrimSpace(provider))
	switch provider {
	case "anthropic", "claude":
		return "claude"
	case "openai-codex", "codex":
		return "codex"
	default:
		return provider
	}
}

func isTargetProvider(provider string) bool {
	provider = normalizeProvider(provider)
	return provider == "codex" || provider == "claude"
}

func (l *quotaLimiter) persist() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.persistLocked(l.now())
}

func (l *quotaLimiter) persistLocked(now time.Time) error {
	accounts := make(map[string]persistedQuotaStatus, len(l.statuses))
	for id, status := range l.statuses {
		if !status.Known && !status.RetryAt.After(now) {
			continue
		}
		accounts[id] = persistedQuotaStatus{
			Known:     status.Known,
			State:     status.State,
			CheckedAt: status.CheckedAt,
			RetryAt:   status.RetryAt,
			Err:       status.Err,
		}
	}
	persisted := persistedState{Version: stateVersion, Accounts: accounts}
	raw, errMarshal := json.MarshalIndent(persisted, "", "  ")
	if errMarshal != nil {
		return fmt.Errorf("encode quota state: %w", errMarshal)
	}
	raw = append(raw, '\n')

	directory := filepath.Dir(l.config.StatePath)
	if errMkdir := os.MkdirAll(directory, 0o750); errMkdir != nil {
		return fmt.Errorf("create quota state directory: %w", errMkdir)
	}
	temporary, errCreate := os.CreateTemp(directory, ".account-quota-*")
	if errCreate != nil {
		return fmt.Errorf("create temporary quota state: %w", errCreate)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if errChmod := temporary.Chmod(0o600); errChmod != nil {
		temporary.Close()
		return fmt.Errorf("set quota state permissions: %w", errChmod)
	}
	if _, errWrite := temporary.Write(raw); errWrite != nil {
		temporary.Close()
		return fmt.Errorf("write quota state: %w", errWrite)
	}
	if errSync := temporary.Sync(); errSync != nil {
		temporary.Close()
		return fmt.Errorf("sync quota state: %w", errSync)
	}
	if errClose := temporary.Close(); errClose != nil {
		return fmt.Errorf("close quota state: %w", errClose)
	}
	if errRename := os.Rename(temporaryPath, l.config.StatePath); errRename != nil {
		return fmt.Errorf("replace quota state: %w", errRename)
	}
	return nil
}

func okEnvelope(value any) ([]byte, error) {
	result, errMarshal := json.Marshal(value)
	if errMarshal != nil {
		return nil, errMarshal
	}
	return json.Marshal(envelope{OK: true, Result: result})
}

func statusErrorEnvelope(code, message string, status int, retryable bool) []byte {
	raw, _ := json.Marshal(envelope{
		OK: false,
		Error: &envelopeError{
			Code:       code,
			Message:    message,
			Retryable:  retryable,
			HTTPStatus: status,
		},
	})
	return raw
}

func errorEnvelope(code, message string) []byte {
	raw, _ := json.Marshal(envelope{
		OK: false,
		Error: &envelopeError{
			Code:    code,
			Message: message,
		},
	})
	return raw
}

func writeResponse(response *C.cliproxy_buffer, raw []byte) {
	if response == nil || len(raw) == 0 {
		return
	}
	ptr := C.CBytes(raw)
	if ptr == nil {
		return
	}
	response.ptr = ptr
	response.len = C.size_t(len(raw))
}
