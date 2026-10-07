#!/bin/bash

# ANSI color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
RESET='\033[0m'
DIM='\033[2m'

# Extract every field in ONE jq call. jq reads the JSON straight from stdin
# and prints shell-quoted assignments (via @sh), which eval turns into variables.
eval "$(jq -r '
  .context_window as $cw
  | $cw.current_usage as $u
  | @sh "current_dir=\(.workspace.current_dir // "")",
    @sh "model_name=\(.model.display_name // "")",
    @sh "effort_level=\(.effort.level // "")",
    @sh "has_usage=\(if $u == null then 0 else 1 end)",
    @sh "input_tokens=\($u.input_tokens // 0)",
    @sh "cache_creation=\($u.cache_creation_input_tokens // 0)",
    @sh "cache_read=\($u.cache_read_input_tokens // 0)",
    @sh "window_size=\($cw.context_window_size // 0)",
    @sh "five_hour=\(.rate_limits.five_hour.used_percentage // "")",
    @sh "seven_day=\(.rate_limits.seven_day.used_percentage // "")"
' 2>/dev/null)"

# Helpers assign into the variable named by $1 via printf -v, so calling them
# needs no $(...) subshell.

# fmt_k VAR N: format tokens with k suffix
fmt_k() {
  if [ "$2" -ge 1000 ]; then printf -v "$1" '%sk' "$(($2 / 1000))"; else printf -v "$1" '%s' "$2"; fi
}

# pct_color VAR PCT: color based on usage level
pct_color() {
  if [ "$2" -ge 80 ]; then printf -v "$1" '%s' "$RED"
  elif [ "$2" -ge 50 ]; then printf -v "$1" '%s' "$YELLOW"
  else printf -v "$1" '%s' "$GREEN"; fi
}

# Directory name, like basename but without forking: strip trailing slashes,
# take the last component, and fall back to "/" for the root
if [ -n "$current_dir" ]; then
  dir_name="${current_dir%"${current_dir##*[!/]}"}"
  dir_name="${dir_name##*/}"
  path_display="${DIM}dir${RESET} ${CYAN}${dir_name:-/}${RESET}"
else
  path_display="${DIM}dir${RESET} ${CYAN}~${RESET}"
fi

# Git branch and dirty count from a single git call.
# Porcelain v2 prints "# branch.head <name>" headers, then one line per change.
git_info=""
if [ -n "$current_dir" ] && git_out=$(git -C "$current_dir" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null); then
  branch="detached"
  dirty_count=0
  while IFS= read -r line; do
    case "$line" in
      "# branch.head (detached)") ;;
      "# branch.head "*) branch="${line#\# branch.head }" ;;
      "#"*) ;;
      ?*) dirty_count=$((dirty_count + 1)) ;;
    esac
  done <<< "$git_out"
  if [ "$dirty_count" -gt 0 ]; then
    git_info=" ${DIM}·${RESET} ${DIM}branch${RESET} ${YELLOW}${branch} (${dirty_count})${RESET}"
  else
    git_info=" ${DIM}·${RESET} ${DIM}branch${RESET} ${GREEN}${branch}${RESET}"
  fi
fi

# Context window percentage and cache write/read info
context_usage=""
cache_info=""
if [ "${has_usage:-0}" -eq 1 ]; then
  total_current=$((input_tokens + cache_creation + cache_read))

  if [ "$window_size" -gt 0 ]; then
    pct=$((total_current * 100 / window_size))

    # Color based on usage level
    if [ "$pct" -ge 80 ]; then
      ctx_color="$RED"
    elif [ "$pct" -ge 50 ]; then
      ctx_color="$YELLOW"
    else
      ctx_color="$MAGENTA"
    fi

    fmt_k tokens_display "$total_current"
    fmt_k window_display "$window_size"
    context_usage=" ${DIM}·${RESET} ${DIM}ctx${RESET} ${ctx_color}${tokens_display}/${window_display} (${pct}%)${RESET}"
  fi

  if [ "$cache_creation" -gt 0 ] || [ "$cache_read" -gt 0 ]; then
    fmt_k cache_write_display "$cache_creation"
    fmt_k cache_read_display "$cache_read"
    cache_info=" ${DIM}·${RESET} ${DIM}cache${RESET} ${GREEN}w:${cache_write_display}${RESET} ${GREEN}r:${cache_read_display}${RESET}"
  fi
fi

# Session usage (Claude.ai subscription rate limits)
session_parts=""
if [ -n "$five_hour" ]; then
  printf -v five_pct '%.0f' "$five_hour"
  pct_color s_color "$five_pct"
  session_parts="${s_color}5h:${five_pct}%${RESET}"
fi
if [ -n "$seven_day" ]; then
  printf -v week_pct '%.0f' "$seven_day"
  pct_color w_color "$week_pct"
  [ -n "$session_parts" ] && session_parts="${session_parts} "
  session_parts="${session_parts}${w_color}7d:${week_pct}%${RESET}"
fi
session_info=""
[ -n "$session_parts" ] && session_info=" ${DIM}·${RESET} ${DIM}session${RESET} ${session_parts}"

# Model + effort display
model_display="${BLUE}${model_name}${RESET}"
if [ -n "$effort_level" ]; then
  model_display="${model_display}${DIM}:${RESET}${MAGENTA}${effort_level}${RESET}"
fi

# Output the status line
echo -e "${path_display}${git_info} ${DIM}·${RESET} ${DIM}model${RESET} ${model_display}${context_usage}${cache_info}${session_info}"
