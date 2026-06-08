#!/usr/bin/env bash
set -euo pipefail

# Read JSON input from stdin once
input="$(cat)"

# ---------------------------------------------------------------------------
# Helper: extract a jq field, returns empty string if null/missing
# ---------------------------------------------------------------------------
jqr() { jq -r "${1} // empty" <<<"$input"; }

SEP=" | "
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
MAGENTA='\033[35m'
RED='\033[31m'

# ---------------------------------------------------------------------------
# LINE 1 FIELDS
# ---------------------------------------------------------------------------

# Vim mode — only show when vim mode is active
vim_mode="$(jqr '.vim.mode')"

# Model display name
model="$(jqr '.model.display_name // .model.id')"
[[ -z "$model" ]] && model="unknown"

# Effort level — check .effort.level only (canonical field)
effort="$(jqr '.effort.level')"

# Thinking indicator
thinking="$(jqr '.thinking.enabled')"

# Context used percentage (pre-calculated)
used="$(jqr '.context_window.used_percentage')"

# ---------------------------------------------------------------------------
# LINE 2 FIELDS
# ---------------------------------------------------------------------------

# Current working directory
cwd="$(jqr '.workspace.current_dir // .workspace.project_dir // .cwd')"

# Workspace directory basename
dir=""
if [[ -n "$cwd" ]]; then
  dir="$(basename "$cwd")"
fi

# Repo owner/name — only if available
repo_owner="$(jqr '.workspace.repo.owner')"
repo_name="$(jqr '.workspace.repo.name')"
repo=""
if [[ -n "$repo_owner" && -n "$repo_name" ]]; then
  repo="${repo_owner}/${repo_name}"
fi

# Git branch — use worktree field first, then run git
branch="$(jqr '.worktree.branch // .workspace.git_worktree')"
if [[ -z "$branch" && -n "$cwd" ]]; then
  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch="$(
      git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null \
        || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null \
        || printf "detached"
    )"
  fi
fi

# Rate limits — only show when present (Claude.ai subscribers)
five_pct="$(jqr '.rate_limits.five_hour.used_percentage')"
week_pct="$(jqr '.rate_limits.seven_day.used_percentage')"

# ---------------------------------------------------------------------------
# Build LINE 1
# ---------------------------------------------------------------------------
line1_parts=()

if [[ -n "$vim_mode" ]]; then
  line1_parts+=("$(printf "${BOLD}${YELLOW}%s${RESET}" "$vim_mode")")
fi

# Model + effort + thinking
model_str="$model"
if [[ -n "$effort" ]]; then
  model_str="${model_str}:${effort}"
fi
if [[ "$thinking" == "true" ]]; then
  model_str="${model_str} (think)"
fi
line1_parts+=("$(printf "${CYAN}%s${RESET}" "$model_str")")

# Context used
if [[ -n "$used" ]]; then
  ctx_str="$(printf "context used:%.0f%%" "$used")"
  line1_parts+=("$(printf "${YELLOW}%s${RESET}" "$ctx_str")")
fi

# ---------------------------------------------------------------------------
# Build LINE 2
# ---------------------------------------------------------------------------
line2_parts=()

# Build [repo] cwd:branch as a single composite field
location=""
if [[ -n "$repo" ]]; then
  location+="$(printf "${DIM}[%s]${RESET} " "$repo")"
fi
if [[ -n "$dir" ]]; then
  location+="$(printf "${CYAN}%s${RESET}" "$dir")"
fi
if [[ -n "$branch" ]]; then
  location+="$(printf ":${MAGENTA}%s${RESET}" "$branch")"
fi
if [[ -n "$location" ]]; then
  line2_parts+=("$location")
fi

# Rate limits
rate_str=""
if [[ -n "$five_pct" ]]; then
  rate_str+="$(printf "5h:%.0f%%" "$five_pct")"
fi
if [[ -n "$week_pct" ]]; then
  [[ -n "$rate_str" ]] && rate_str+=" "
  rate_str+="$(printf "7d:%.0f%%" "$week_pct")"
fi
if [[ -n "$rate_str" ]]; then
  line2_parts+=("$(printf "${RED}%s${RESET}" "$rate_str")")
fi

# ---------------------------------------------------------------------------
# Join parts with separator and print
# ---------------------------------------------------------------------------
join_parts() {
  local sep="$1"; shift
  local result=""
  for part in "$@"; do
    if [[ -n "$result" ]]; then
      result+="${sep}${part}"
    else
      result="$part"
    fi
  done
  printf "%s" "$result"
}

all_parts=("${line1_parts[@]+"${line1_parts[@]}"}" "${line2_parts[@]+"${line2_parts[@]}"}")
line="$(join_parts "$SEP" "${all_parts[@]+"${all_parts[@]}"}")"

printf "%b" "$line"
