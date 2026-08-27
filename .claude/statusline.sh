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

# Read JSON input from stdin
input=$(cat)

# Extract values from JSON
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
model_name=$(echo "$input" | jq -r '.model.display_name')
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
context_window=$(echo "$input" | jq '.context_window')
rate_limits=$(echo "$input" | jq '.rate_limits')

# Get relative path or basename
if [ -n "$current_dir" ]; then
  path_display="${DIM}dir${RESET} ${CYAN}$(basename "$current_dir")${RESET}"
else
  path_display="${DIM}dir${RESET} ${CYAN}~${RESET}"
fi

# Get git branch and status (skip optional locks for performance)
git_info=""
if [ -d "$current_dir/.git" ] || git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$current_dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || echo "detached")

  # Check if there are changes (skip locks)
  dirty_count=$(git -C "$current_dir" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$dirty_count" -gt 0 ]; then
    git_info=" ${DIM}·${RESET} ${DIM}branch${RESET} ${YELLOW}${branch} (${dirty_count})${RESET}"
  else
    git_info=" ${DIM}·${RESET} ${DIM}branch${RESET} ${GREEN}${branch}${RESET}"
  fi
fi

# Calculate context window percentage
context_usage=""
current_usage=$(echo "$context_window" | jq '.current_usage')
if [ "$current_usage" != "null" ]; then
  input_tokens=$(echo "$current_usage" | jq '.input_tokens // 0')
  cache_creation=$(echo "$current_usage" | jq '.cache_creation_input_tokens // 0')
  cache_read=$(echo "$current_usage" | jq '.cache_read_input_tokens // 0')
  total_current=$((input_tokens + cache_creation + cache_read))

  window_size=$(echo "$context_window" | jq '.context_window_size')

  if [ "$window_size" -gt 0 ]; then
    pct=$((total_current * 100 / window_size))

    # Format tokens with k suffix
    if [ "$total_current" -ge 1000 ]; then
      tokens_display="$((total_current / 1000))k"
    else
      tokens_display="${total_current}"
    fi

    if [ "$window_size" -ge 1000 ]; then
      window_display="$((window_size / 1000))k"
    else
      window_display="${window_size}"
    fi

    # Color based on usage level
    if [ "$pct" -ge 80 ]; then
      ctx_color="$RED"
    elif [ "$pct" -ge 50 ]; then
      ctx_color="$YELLOW"
    else
      ctx_color="$MAGENTA"
    fi

    context_usage=" ${DIM}·${RESET} ${DIM}ctx${RESET} ${ctx_color}${tokens_display}/${window_display} (${pct}%)${RESET}"
  fi
fi

# Cache write/read info
cache_info=""
if [ "$current_usage" != "null" ]; then
  cache_write_tok=$(echo "$current_usage" | jq '.cache_creation_input_tokens // 0')
  cache_read_tok=$(echo "$current_usage" | jq '.cache_read_input_tokens // 0')

  if [ "$cache_write_tok" -gt 0 ] || [ "$cache_read_tok" -gt 0 ]; then
    if [ "$cache_write_tok" -ge 1000 ]; then
      cache_write_display="$((cache_write_tok / 1000))k"
    else
      cache_write_display="${cache_write_tok}"
    fi

    if [ "$cache_read_tok" -ge 1000 ]; then
      cache_read_display="$((cache_read_tok / 1000))k"
    else
      cache_read_display="${cache_read_tok}"
    fi

    cache_info=" ${DIM}·${RESET} ${DIM}cache${RESET} ${GREEN}w:${cache_write_display}${RESET} ${GREEN}r:${cache_read_display}${RESET}"
  fi
fi

# Session usage (Claude.ai subscription rate limits)
session_info=""
if [ "$rate_limits" != "null" ]; then
  five_hour=$(echo "$rate_limits" | jq -r '.five_hour.used_percentage // empty')
  seven_day=$(echo "$rate_limits" | jq -r '.seven_day.used_percentage // empty')

  session_parts=""
  if [ -n "$five_hour" ]; then
    five_pct=$(printf '%.0f' "$five_hour")
    if [ "$five_pct" -ge 80 ]; then
      s_color="$RED"
    elif [ "$five_pct" -ge 50 ]; then
      s_color="$YELLOW"
    else
      s_color="$GREEN"
    fi
    session_parts="${s_color}5h:${five_pct}%${RESET}"
  fi
  if [ -n "$seven_day" ]; then
    week_pct=$(printf '%.0f' "$seven_day")
    if [ "$week_pct" -ge 80 ]; then
      w_color="$RED"
    elif [ "$week_pct" -ge 50 ]; then
      w_color="$YELLOW"
    else
      w_color="$GREEN"
    fi
    [ -n "$session_parts" ] && session_parts="${session_parts} "
    session_parts="${session_parts}${w_color}7d:${week_pct}%${RESET}"
  fi

  [ -n "$session_parts" ] && session_info=" ${DIM}·${RESET} ${DIM}session${RESET} ${session_parts}"
fi

# Model + effort display
model_display="${BLUE}${model_name}${RESET}"
if [ -n "$effort_level" ]; then
  model_display="${model_display}${DIM}:${RESET}${MAGENTA}${effort_level}${RESET}"
fi

# Output the status line
echo -e "${path_display}${git_info} ${DIM}·${RESET} ${DIM}model${RESET} ${model_display}${context_usage}${cache_info}${session_info}"
