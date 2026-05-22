#!/bin/bash
# Status Line — real state only
# 2ndBrain (Obsidian) + fidgetflo (MCP) + Swarm/Hive activity

input=$(cat)

# Parse Claude Code's JSON input
MODEL=$(echo "$input" | jq -r '.model.display_name // "Opus 4.6"' 2>/dev/null)
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
CWD=$(echo "$input" | jq -r '.workspace.current_dir // ""' 2>/dev/null)

# Format duration
if [ "$DURATION_MS" != "0" ] && [ "$DURATION_MS" != "null" ]; then
  SECS=$((${DURATION_MS%.*} / 1000))
  MINS=$((SECS / 60))
  REMAINING_SECS=$((SECS % 60))
  if [ "$MINS" -gt 0 ]; then
    TIME_FMT="${MINS}m${REMAINING_SECS}s"
  else
    TIME_FMT="${SECS}s"
  fi
else
  TIME_FMT="0s"
fi

# --- 2ndBRAIN CHECK ---
# Primary: ~/.claude/.mogging-vault marker (written by 2ndBrain-mogging's
# install.sh). Contents = absolute vault path. Light up 🧠 when $CWD
# matches exactly or sits inside ($CWD starts with path + "/").
# Fallback: legacy path regex for pre-marker installs / legacy vault names.
BRAIN=""
MOGGING_VAULT_MARKER="$HOME/.claude/.mogging-vault"
if [ -f "$MOGGING_VAULT_MARKER" ] && [ -n "$CWD" ]; then
  VAULT_PATH=$(head -n1 "$MOGGING_VAULT_MARKER" 2>/dev/null | tr -d '\n')
  if [ -n "$VAULT_PATH" ]; then
    case "$CWD" in
      "$VAULT_PATH"|"$VAULT_PATH"/*) BRAIN="🧠 Brain²" ;;
    esac
  fi
fi
if [ -z "$BRAIN" ] && [ -n "$CWD" ] && echo "$CWD" | grep -qiE "OBSIDIAN/(2ndBrain|MASTER)|/BRAIN2?(/|$)" 2>/dev/null; then
  BRAIN="🧠 Brain²"
fi

# --- fidgetflo CHECK ---
fidgetflo=""
if pgrep -f "fidgetflo.*mcp" >/dev/null 2>&1 || pgrep -f "fidgetflo/bin/cli" >/dev/null 2>&1 || pgrep -f "fidgetflo" >/dev/null 2>&1; then
  fidgetflo="⚡️ fidgetflo"
fi

# --- SWARM CHECK (only shows when actively running) ---
# Lock file is written by /fswarm skill, removed on completion.
# Agents run as Claude Code subprocesses (not CLI), so pgrep won't find them.
# Auto-clean lock files older than 30 min as stale.
SWARM=""
SWARM_LOCK="/tmp/fidgetflo-swarm-active"
if [ -f "$SWARM_LOCK" ] 2>/dev/null; then
  if [ "$(find /tmp -maxdepth 1 -name 'fidgetflo-swarm-active' -mmin +30 2>/dev/null)" ]; then
    rm -f "$SWARM_LOCK" 2>/dev/null
  else
    AGENT_COUNT=$(cat "$SWARM_LOCK" 2>/dev/null || echo "")
    # Sanitize: keep only digits to prevent injection from a malicious lock-file write
    AGENT_COUNT="${AGENT_COUNT//[^0-9]/}"
    if [ -n "$AGENT_COUNT" ]; then
      SWARM="🐝 ${AGENT_COUNT}"
    else
      SWARM="🐝"
    fi
  fi
fi

# --- HIVE CHECK (only shows when actively running) ---
# Same approach — trust lock file, auto-clean after 30 min.
HIVE=""
HIVE_LOCK="/tmp/fidgetflo-hive-active"
if [ -f "$HIVE_LOCK" ] 2>/dev/null; then
  if [ "$(find /tmp -maxdepth 1 -name 'fidgetflo-hive-active' -mmin +30 2>/dev/null)" ]; then
    rm -f "$HIVE_LOCK" 2>/dev/null
  else
    HIVE="👑 Hive"
  fi
fi

# --- MINI CHECK (only shows when actively running) ---
# Same approach — trust lock file, auto-clean after 30 min.
MINI=""
MINI_LOCK="/tmp/fidgetflo-mini-active"
if [ -f "$MINI_LOCK" ] 2>/dev/null; then
  if [ "$(find /tmp -maxdepth 1 -name 'fidgetflo-mini-active' -mmin +30 2>/dev/null)" ]; then
    rm -f "$MINI_LOCK" 2>/dev/null
  else
    MINI_AGENT_COUNT=$(cat "$MINI_LOCK" 2>/dev/null || echo "")
    # Sanitize: keep only digits to prevent injection from a malicious lock-file write
    MINI_AGENT_COUNT="${MINI_AGENT_COUNT//[^0-9]/}"
    if [ -n "$MINI_AGENT_COUNT" ]; then
      MINI="🍯 ${MINI_AGENT_COUNT}"
    else
      MINI="🍯"
    fi
  fi
fi

# --- CLAUDE SUBSCRIPTION USAGE (5h / 7d) ---
# Claude Code passes rate-limit utilization directly in the stdin JSON
# (rate_limits.*.used_percentage), so no network call is needed.
USAGE=""

# 5-cell colored bar + percent for a single utilization value.
usage_seg() {
  local label="$1" val="$2"
  [ -z "$val" ] || [ "$val" = "null" ] && return
  local p=${val%.*}; [ -z "$p" ] && p=0
  local cells=5
  local filled=$(( (p * cells + 50) / 100 ))
  [ "$filled" -gt "$cells" ] && filled=$cells
  [ "$filled" -lt 0 ] && filled=0
  local empty=$(( cells - filled )) c fill="" emp="" i=0
  if   [ "$p" -ge 90 ]; then c=$'\033[38;5;196m'   # red
  elif [ "$p" -ge 75 ]; then c=$'\033[38;5;208m'   # orange
  elif [ "$p" -ge 60 ]; then c=$'\033[38;5;226m'   # yellow
  elif [ "$p" -ge 40 ]; then c=$'\033[38;5;154m'   # lime
  else                       c=$'\033[38;5;46m'; fi # green
  local dim=$'\033[38;5;240m' reset=$'\033[0m'
  while [ $i -lt $filled ]; do fill="${fill}█"; i=$((i+1)); done
  i=0; while [ $i -lt $empty ]; do emp="${emp}█"; i=$((i+1)); done
  printf '%s %s%s%s%s%s' "$label" "$c" "$fill" "$dim" "$emp" "$reset"
}

U5=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
U7=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
seg=$(usage_seg "5h" "$U5"); [ -n "$seg" ] && USAGE="$seg"
seg=$(usage_seg "7d" "$U7"); [ -n "$seg" ] && { [ -n "$USAGE" ] && USAGE="$USAGE · "; USAGE="$USAGE$seg"; }

# --- BUILD THE LINE ---
PARTS=""
if [ -n "$BRAIN" ] && [ -n "$fidgetflo" ]; then
  PARTS="${BRAIN} + ${fidgetflo}"
elif [ -n "$BRAIN" ]; then
  PARTS="${BRAIN}"
elif [ -n "$fidgetflo" ]; then
  PARTS="${fidgetflo}"
fi

# Swarm, Hive, or Mini activity
ACTIVITY=""
if [ -n "$SWARM" ]; then
  ACTIVITY="${SWARM}"
fi
if [ -n "$HIVE" ]; then
  [ -n "$ACTIVITY" ] && ACTIVITY="${ACTIVITY} + "
  ACTIVITY="${ACTIVITY}${HIVE}"
fi
if [ -n "$MINI" ]; then
  [ -n "$ACTIVITY" ] && ACTIVITY="${ACTIVITY} + "
  ACTIVITY="${ACTIVITY}${MINI}"
fi
if [ -n "$ACTIVITY" ]; then
  if [ -n "$PARTS" ]; then
    PARTS="${PARTS} [${ACTIVITY}]"
  else
    PARTS="[${ACTIVITY}]"
  fi
fi

LINE="${MODEL} • ⏱ ${TIME_FMT} • ${CTX}% ctx"
[ -n "$PARTS" ] && LINE="${PARTS} • ${LINE}"
[ -n "$USAGE" ] && LINE="${LINE} • ${USAGE}"
echo "$LINE"
