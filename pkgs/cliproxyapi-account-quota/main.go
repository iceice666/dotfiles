package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef struct {
	void* ptr;
	size_t len;
} cliproxy_buffer;

typedef struct {
	uint32_t abi_version;
	void* host_ctx;
	void* call;
	void* free_buffer;
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
*/
import "C"

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"gopkg.in/yaml.v3"
)

const (
	abiVersion            uint32 = 1
	schemaVersion         uint32 = 1
	pluginVersion                = "0.1.0"
	fiveHours                    = 5 * time.Hour
	codexWindowMinutes           = 300
	defaultReservePercent        = 20.0
	defaultStatePath             = "account-quota-state.json"
)

const (
	methodPluginRegister    = "plugin.register"
	methodPluginReconfigure = "plugin.reconfigure"
	methodSchedulerPick     = "scheduler.pick"
	methodUsageHandle       = "usage.handle"
)

type envelope struct {
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *envelopeError  `json:"error,omitempty"`
}

type envelopeError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type lifecycleRequest struct {
	ConfigYAML []byte `json:"config_yaml"`
}

type pluginConfig struct {
	ReservePercent float64 `yaml:"reserve_percent"`
	StatePath      string  `yaml:"state_path"`
}

type registration struct {
	SchemaVersion uint32                 `json:"schema_version"`
	Metadata      metadata               `json:"metadata"`
	Capabilities  registrationCapability `json:"capabilities"`
}

type registrationCapability struct {
	Scheduler   bool `json:"scheduler"`
	UsagePlugin bool `json:"usage_plugin"`
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

type usageRecord struct {
	Provider        string
	AuthID          string
	ResponseHeaders map[string][]string
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

type quotaLimiter struct {
	mu     sync.Mutex
	config pluginConfig
	states map[string]accountState
	cursor map[string]int
	now    func() time.Time
}

var limiter = newQuotaLimiter()

func main() {}

func newQuotaLimiter() *quotaLimiter {
	return &quotaLimiter{
		config: pluginConfig{
			ReservePercent: defaultReservePercent,
			StatePath:      defaultStatePath,
		},
		states: make(map[string]accountState),
		cursor: make(map[string]int),
		now:    time.Now,
	}
}

//export cliproxy_plugin_init
func cliproxy_plugin_init(_ *C.cliproxy_host_api, plugin *C.cliproxy_plugin_api) C.int {
	if plugin == nil {
		return 1
	}
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
	case methodUsageHandle:
		if errUsage := limiter.handleUsage(request); errUsage != nil {
			return nil, errUsage
		}
		return okEnvelope(struct{}{})
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
			},
		},
		Capabilities: registrationCapability{
			Scheduler:   true,
			UsagePlugin: true,
		},
	}
}

func (l *quotaLimiter) configure(raw []byte) error {
	var req lifecycleRequest
	if len(raw) > 0 {
		if errUnmarshal := json.Unmarshal(raw, &req); errUnmarshal != nil {
			return fmt.Errorf("decode lifecycle request: %w", errUnmarshal)
		}
	}

	cfg := pluginConfig{
		ReservePercent: defaultReservePercent,
		StatePath:      defaultStatePath,
	}
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

	states, errLoad := loadPersistedState(cfg.StatePath, l.now())
	if errLoad != nil {
		return errLoad
	}

	l.mu.Lock()
	l.config = cfg
	l.states = states
	l.cursor = make(map[string]int)
	l.mu.Unlock()
	return nil
}

func loadPersistedState(path string, now time.Time) (map[string]accountState, error) {
	states := make(map[string]accountState)
	raw, errRead := os.ReadFile(path)
	if errors.Is(errRead, os.ErrNotExist) {
		return states, nil
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
		states[id] = state
	}
	return states, nil
}

func (l *quotaLimiter) pick(raw []byte) ([]byte, error) {
	var req schedulerPickRequest
	if errUnmarshal := json.Unmarshal(raw, &req); errUnmarshal != nil {
		return nil, fmt.Errorf("decode scheduler request: %w", errUnmarshal)
	}
	if len(req.Candidates) == 0 || !requestTargetsLimitedProvider(req) {
		return okEnvelope(schedulerPickResponse{Handled: false})
	}

	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	threshold := 100 - l.config.ReservePercent
	blocked := 0
	eligible := make([]schedulerAuthCandidate, 0, len(req.Candidates))
	stateChanged := false
	for _, candidate := range req.Candidates {
		state, exists := l.states[candidate.ID]
		if exists && !state.ResetAt.After(now) {
			delete(l.states, candidate.ID)
			exists = false
			stateChanged = true
		}
		if exists && providersMatch(state.Provider, candidate.Provider) && state.UtilizedPercent >= threshold {
			blocked++
			continue
		}
		eligible = append(eligible, candidate)
	}
	if stateChanged {
		_ = l.persistLocked(now)
	}
	if blocked == 0 {
		return okEnvelope(schedulerPickResponse{Handled: false})
	}
	if len(eligible) == 0 {
		return errorEnvelope(
			"quota_reserved",
			fmt.Sprintf("all %d eligible accounts reached the %.1f%% five-hour usage ceiling", blocked, threshold),
		), nil
	}

	selected := l.selectCandidate(req, eligible)
	return okEnvelope(schedulerPickResponse{AuthID: selected.ID, Handled: true})
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

func (l *quotaLimiter) handleUsage(raw []byte) error {
	var record usageRecord
	if errUnmarshal := json.Unmarshal(raw, &record); errUnmarshal != nil {
		return fmt.Errorf("decode usage record: %w", errUnmarshal)
	}
	record.AuthID = strings.TrimSpace(record.AuthID)
	record.Provider = normalizeProvider(record.Provider)
	if record.AuthID == "" || !isTargetProvider(record.Provider) {
		return nil
	}

	now := l.now()
	sample, ok := quotaSample(record.Provider, record.ResponseHeaders, now)
	if !ok {
		return nil
	}

	l.mu.Lock()
	defer l.mu.Unlock()

	threshold := 100 - l.config.ReservePercent
	previous, existed := l.states[record.AuthID]
	wasBlocked := existed && previous.UtilizedPercent >= threshold && previous.ResetAt.After(now)
	l.states[record.AuthID] = sample
	isBlocked := sample.UtilizedPercent >= threshold && sample.ResetAt.After(now)
	if wasBlocked != isBlocked || isBlocked {
		if errPersist := l.persistLocked(now); errPersist != nil {
			return errPersist
		}
	}
	return nil
}

func quotaSample(provider string, headers map[string][]string, now time.Time) (accountState, bool) {
	var utilizedRaw string
	var resetAt time.Time

	switch normalizeProvider(provider) {
	case "codex":
		if windowRaw := headerValue(headers, "x-codex-primary-window-minutes"); windowRaw != "" {
			window, errParse := strconv.ParseFloat(strings.TrimSpace(windowRaw), 64)
			if errParse != nil || math.Abs(window-codexWindowMinutes) > 0.01 {
				return accountState{}, false
			}
		}
		utilizedRaw = headerValue(headers, "x-codex-primary-used-percent")
		resetAt = firstResetTime(headers, now,
			"x-codex-primary-reset-at",
			"x-codex-primary-reset-after-seconds",
			"x-codex-primary-reset-in-seconds",
		)
	case "claude":
		utilizedRaw = headerValue(headers, "anthropic-ratelimit-unified-5h-utilization")
		resetAt = firstResetTime(headers, now, "anthropic-ratelimit-unified-5h-reset")
	default:
		return accountState{}, false
	}
	if utilizedRaw == "" {
		return accountState{}, false
	}

	utilized, errParse := strconv.ParseFloat(strings.TrimSpace(strings.TrimSuffix(utilizedRaw, "%")), 64)
	if errParse != nil || math.IsNaN(utilized) || utilized < 0 {
		return accountState{}, false
	}
	if normalizeProvider(provider) == "claude" && utilized <= 1 {
		utilized *= 100
	}
	if utilized > 100 {
		utilized = 100
	}
	if resetAt.IsZero() || !resetAt.After(now) {
		resetAt = now.Add(fiveHours)
	}
	return accountState{
		Provider:        normalizeProvider(provider),
		UtilizedPercent: utilized,
		ResetAt:         resetAt,
		UpdatedAt:       now,
	}, true
}

func firstResetTime(headers map[string][]string, now time.Time, names ...string) time.Time {
	for _, name := range names {
		value := headerValue(headers, name)
		if value == "" {
			continue
		}
		if strings.Contains(name, "after-seconds") || strings.Contains(name, "in-seconds") {
			seconds, errParse := strconv.ParseFloat(strings.TrimSpace(value), 64)
			if errParse == nil && seconds > 0 {
				return now.Add(time.Duration(seconds * float64(time.Second)))
			}
			continue
		}
		if parsed, errParse := time.Parse(time.RFC3339Nano, strings.TrimSpace(value)); errParse == nil {
			return parsed
		}
		if epoch, errParse := strconv.ParseFloat(strings.TrimSpace(value), 64); errParse == nil && epoch > 0 {
			if epoch > 1e12 {
				return time.UnixMilli(int64(epoch))
			}
			return time.Unix(int64(epoch), 0)
		}
	}
	return time.Time{}
}

func headerValue(headers map[string][]string, name string) string {
	for key, values := range headers {
		if !strings.EqualFold(strings.TrimSpace(key), name) || len(values) == 0 {
			continue
		}
		return strings.TrimSpace(values[0])
	}
	return ""
}

func normalizeProvider(provider string) string {
	provider = strings.ToLower(strings.TrimSpace(provider))
	if provider == "anthropic" {
		return "claude"
	}
	return provider
}

func isTargetProvider(provider string) bool {
	switch normalizeProvider(provider) {
	case "codex", "claude":
		return true
	default:
		return false
	}
}

func providersMatch(left, right string) bool {
	return normalizeProvider(left) == normalizeProvider(right)
}

func (l *quotaLimiter) persist() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.persistLocked(l.now())
}

func (l *quotaLimiter) persistLocked(now time.Time) error {
	accounts := make(map[string]accountState)
	threshold := 100 - l.config.ReservePercent
	for id, state := range l.states {
		if state.UtilizedPercent < threshold || !state.ResetAt.After(now) {
			continue
		}
		accounts[id] = state
	}
	persisted := persistedState{Version: 1, Accounts: accounts}
	raw, errMarshal := json.MarshalIndent(persisted, "", "  ")
	if errMarshal != nil {
		return fmt.Errorf("encode quota state: %w", errMarshal)
	}
	raw = append(raw, '\n')

	path := l.config.StatePath
	dir := filepath.Dir(path)
	if errMkdir := os.MkdirAll(dir, 0o750); errMkdir != nil {
		return fmt.Errorf("create quota state directory: %w", errMkdir)
	}
	temp, errCreate := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-*")
	if errCreate != nil {
		return fmt.Errorf("create quota state: %w", errCreate)
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)

	if errChmod := temp.Chmod(0o600); errChmod != nil {
		temp.Close()
		return fmt.Errorf("secure quota state: %w", errChmod)
	}
	if _, errWrite := temp.Write(raw); errWrite != nil {
		temp.Close()
		return fmt.Errorf("write quota state: %w", errWrite)
	}
	if errSync := temp.Sync(); errSync != nil {
		temp.Close()
		return fmt.Errorf("sync quota state: %w", errSync)
	}
	if errClose := temp.Close(); errClose != nil {
		return fmt.Errorf("close quota state: %w", errClose)
	}
	if errRename := os.Rename(tempPath, path); errRename != nil {
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

func errorEnvelope(code, message string) []byte {
	raw, _ := json.Marshal(envelope{OK: false, Error: &envelopeError{Code: code, Message: message}})
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
