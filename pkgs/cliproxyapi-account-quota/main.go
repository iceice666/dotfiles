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
	abiVersion            uint32 = 1
	schemaVersion         uint32 = 1
	pluginVersion                = "0.2.0"
	fiveHours                    = 5 * time.Hour
	defaultReservePercent        = 20.0
	defaultPollInterval          = 30 * time.Second
	defaultRequestTimeout        = 5 * time.Second
	defaultStatePath             = "account-quota-state.json"
	claudeUsageURL               = "https://api.anthropic.com/api/oauth/usage"
	codexUsageURL                = "https://chatgpt.com/backend-api/wham/usage"
	maxUsageResponseBytes        = 1 << 20
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
	ReservePercent        float64 `yaml:"reserve_percent"`
	StatePath             string  `yaml:"state_path"`
	PollIntervalSeconds   int     `yaml:"poll_interval_seconds"`
	RequestTimeoutSeconds int     `yaml:"request_timeout_seconds"`
	FailClosed            bool    `yaml:"fail_closed"`
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

type accountState struct {
	Provider        string    `json:"provider"`
	UtilizedPercent float64   `json:"utilized_percent"`
	ResetAt         time.Time `json:"reset_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type persistedState struct {
	Version  int                     `json:"version"`
	Accounts map[string]accountState `json:"accounts"`
}

type quotaStatus struct {
	Known      bool
	Applicable bool
	State      accountState
	CheckedAt  time.Time
	Err        string
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
	Applicable      bool
	UtilizedPercent float64
	ResetAt         time.Time
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
		ReservePercent:        defaultReservePercent,
		StatePath:             defaultStatePath,
		PollIntervalSeconds:   int(defaultPollInterval / time.Second),
		RequestTimeoutSeconds: int(defaultRequestTimeout / time.Second),
		FailClosed:            true,
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
					Description: "Percentage of each Codex or Claude five-hour quota reserved from proxy traffic.",
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
	if cfg.ReservePercent <= 0 || cfg.ReservePercent >= 100 || math.IsNaN(cfg.ReservePercent) {
		return fmt.Errorf("reserve_percent must be greater than 0 and less than 100")
	}
	if cfg.StatePath == "" {
		return errors.New("state_path is required")
	}
	if cfg.PollIntervalSeconds <= 0 {
		return errors.New("poll_interval_seconds must be greater than 0")
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

func loadPersistedState(path string, now time.Time) (map[string]quotaStatus, error) {
	statuses := make(map[string]quotaStatus)
	raw, errRead := os.ReadFile(path)
	if errors.Is(errRead, os.ErrNotExist) {
		return statuses, nil
	}
	if errRead != nil {
		return nil, fmt.Errorf("read quota state: %w", errRead)
	}

	var persisted persistedState
	if errUnmarshal := json.Unmarshal(raw, &persisted); errUnmarshal != nil {
		return nil, fmt.Errorf("decode quota state: %w", errUnmarshal)
	}
	if persisted.Version != 1 {
		return nil, fmt.Errorf("unsupported quota state version %d", persisted.Version)
	}
	for id, state := range persisted.Accounts {
		id = strings.TrimSpace(id)
		if id == "" || !isTargetProvider(state.Provider) || !state.ResetAt.After(now) {
			continue
		}
		statuses[id] = quotaStatus{
			Known:      true,
			Applicable: true,
			State:      state,
			CheckedAt:  state.UpdatedAt,
		}
	}
	return statuses, nil
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

	l.mu.Lock()
	defer l.mu.Unlock()

	threshold := 100 - l.config.ReservePercent
	blocked := 0
	unknown := 0
	eligible := make([]schedulerAuthCandidate, 0, len(req.Candidates))
	for _, candidate := range req.Candidates {
		if !isTargetProvider(candidate.Provider) {
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
		if status.Applicable && status.State.UtilizedPercent >= threshold {
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
			fmt.Sprintf("all %d eligible accounts reached the %.1f%% five-hour usage ceiling", blocked, threshold),
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
	before := blockedStates(l.statuses, 100-cfg.ReservePercent, now)
	stale := make([]schedulerAuthCandidate, 0, len(candidates))
	for _, candidate := range candidates {
		if !isTargetProvider(candidate.Provider) {
			continue
		}
		status, exists := l.statuses[candidate.ID]
		if !exists || now.Sub(status.CheckedAt) >= time.Duration(cfg.PollIntervalSeconds)*time.Second {
			stale = append(stale, candidate)
		}
	}
	l.mu.Unlock()
	if len(stale) == 0 {
		return
	}

	credentials := l.loadCredentials(stale)
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
					status.Applicable = observation.Applicable
					status.State = accountState{
						Provider:        normalizeProvider(candidate.Provider),
						UtilizedPercent: observation.UtilizedPercent,
						ResetAt:         observation.ResetAt,
						UpdatedAt:       now,
					}
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
	after := blockedStates(l.statuses, 100-l.config.ReservePercent, now)
	stateChanged := !sameBlockedStates(before, after)
	l.mu.Unlock()
	if stateChanged {
		_ = l.persist()
	}
}

func blockedStates(statuses map[string]quotaStatus, threshold float64, now time.Time) map[string]accountState {
	blocked := make(map[string]accountState)
	for id, status := range statuses {
		if status.Known && status.Applicable && status.State.UtilizedPercent >= threshold && status.State.ResetAt.After(now) {
			blocked[id] = status.State
		}
	}
	return blocked
}

func sameBlockedStates(left, right map[string]accountState) bool {
	if len(left) != len(right) {
		return false
	}
	for id, leftState := range left {
		rightState, exists := right[id]
		if !exists || normalizeProvider(leftState.Provider) != normalizeProvider(rightState.Provider) || !leftState.ResetAt.Equal(rightState.ResetAt) {
			return false
		}
	}
	return true
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

type claudeUsageResponse struct {
	FiveHour *struct {
		Utilization float64 `json:"utilization"`
		ResetsAt    string  `json:"resets_at"`
	} `json:"five_hour"`
}

func parseClaudeUsage(raw []byte) (quotaObservation, error) {
	var response claudeUsageResponse
	if errUnmarshal := json.Unmarshal(raw, &response); errUnmarshal != nil {
		return quotaObservation{}, fmt.Errorf("decode Claude usage: %w", errUnmarshal)
	}
	if response.FiveHour == nil {
		return quotaObservation{Applicable: false}, nil
	}
	var resetAt time.Time
	if rawReset := strings.TrimSpace(response.FiveHour.ResetsAt); rawReset != "" {
		parsed, errParse := time.Parse(time.RFC3339Nano, rawReset)
		if errParse != nil {
			return quotaObservation{}, fmt.Errorf("decode Claude five-hour reset: %w", errParse)
		}
		resetAt = parsed
	}
	if errValidate := validateUtilization(response.FiveHour.Utilization); errValidate != nil {
		return quotaObservation{}, fmt.Errorf("decode Claude five-hour utilization: %w", errValidate)
	}
	return quotaObservation{
		Applicable:      true,
		UtilizedPercent: response.FiveHour.Utilization,
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
	var selected *codexUsageWindow
	for _, window := range []*codexUsageWindow{response.RateLimit.PrimaryWindow, response.RateLimit.SecondaryWindow} {
		if window == nil || window.LimitWindowSeconds != int64(fiveHours/time.Second) {
			continue
		}
		if selected == nil || window.UsedPercent > selected.UsedPercent {
			selected = window
		}
	}
	if selected == nil {
		return quotaObservation{Applicable: false}, nil
	}
	if errValidate := validateUtilization(selected.UsedPercent); errValidate != nil {
		return quotaObservation{}, fmt.Errorf("decode Codex five-hour utilization: %w", errValidate)
	}
	var resetAt time.Time
	if selected.ResetAt > 0 {
		resetAt = time.Unix(selected.ResetAt, 0)
	} else if selected.ResetAfterSeconds > 0 {
		resetAt = now.Add(time.Duration(selected.ResetAfterSeconds) * time.Second)
	}
	return quotaObservation{
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
	accounts := blockedStates(l.statuses, 100-l.config.ReservePercent, now)
	persisted := persistedState{Version: 1, Accounts: accounts}
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
