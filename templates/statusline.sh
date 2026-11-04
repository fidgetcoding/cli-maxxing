#!/bin/bash
# Status Line — real state only
# 2ndBrain (Obsidian) + fidgetflo (MCP) + Swarm/Hive activity

# Parse and validate stdin once. No input-derived strings reach shell arithmetic.
# Newlines/control characters are stripped from display fields before read splits
# the six records. Invalid JSON/types produce the same harmless fallback.
if ! command -v jq >/dev/null 2>&1; then
  echo "Claude (jq missing — run Step 3)"
  exit 0
fi
FIELDS=$(jq -rs '
  def text($fallback):
    if type == "string" and length > 0 then gsub("[\u0000-\u001f\u007f]"; "") else $fallback end;
  def integer($fallback; $max):
    if type == "number" and . >= 0 and . <= $max then floor else $fallback end;
  if length == 1 and (.[0] | type) == "object" then .[0] else {} end |
  (try .model.display_name catch null | text("Claude")),
  (try .context_window.used_percentage catch null | integer(0; 100)),
  (try .cost.total_duration_ms catch null | integer(0; 315360000000)),
  (try .workspace.current_dir catch null | text("")),
  (try .rate_limits.five_hour.used_percentage catch null | integer(""; 100)),
  (try .rate_limits.seven_day.used_percentage catch null | integer(""; 100))
' 2>/dev/null) || FIELDS=$'Claude\n0\n0\n\n\n'
{
  IFS= read -r MODEL
  IFS= read -r CTX
  IFS= read -r DURATION_MS
  IFS= read -r CWD
  IFS= read -r U5
  IFS= read -r U7
} <<< "$FIELDS"

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
  IFS= read -r VAULT_PATH < "$MOGGING_VAULT_MARKER" || true
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
if pgrep -f "fidgetflo" >/dev/null 2>&1; then
  fidgetflo="⚡️ fidgetflo"
fi

# --- SWARM CHECK (only shows when actively running) ---
# Lock file is written by /fswarm skill, removed on completion.
# Agents run as Claude Code subprocesses (not CLI), so pgrep won't find them.
# Ignore lock files older than 30 min as stale.
SWARM=""
SWARM_LOCK="/tmp/fidgetflo-swarm-active"
if [ -f "$SWARM_LOCK" ] 2>/dev/null; then
  if [ "$(find "$SWARM_LOCK" -prune -mmin +30 2>/dev/null)" ]; then
    : # Ignore stale markers; their owner manages cleanup.
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
# Same approach — ignore stale lock files after 30 min.
HIVE=""
HIVE_LOCK="/tmp/fidgetflo-hive-active"
if [ -f "$HIVE_LOCK" ] 2>/dev/null; then
  if [ "$(find "$HIVE_LOCK" -prune -mmin +30 2>/dev/null)" ]; then
    : # Ignore stale markers; their owner manages cleanup.
  else
    HIVE="👑 Hive"
  fi
fi

# --- MINI CHECK (only shows when actively running) ---
# Same approach — ignore stale lock files after 30 min.
MINI=""
MINI_LOCK="/tmp/fidgetflo-mini-active"
if [ -f "$MINI_LOCK" ] 2>/dev/null; then
  if [ "$(find "$MINI_LOCK" -prune -mmin +30 2>/dev/null)" ]; then
    : # Ignore stale markers; their owner manages cleanup.
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
  printf '%s %s%s%s%s%s %s%%' "$label" "$c" "$fill" "$dim" "$emp" "$reset" "$p"
}

seg=$(usage_seg "5h" "$U5"); [ -n "$seg" ] && USAGE="$seg"
seg=$(usage_seg "7d" "$U7"); [ -n "$seg" ] && { [ -n "$USAGE" ] && USAGE="$USAGE · "; USAGE="$USAGE$seg"; }

# --- BUILD THE LINE ---
PARTS=""
if [ -n "$BRAIN" ] && [ -n "$fidgetflo" ]; then
  PARTS="${BRAIN} • ${fidgetflo}"
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
printf '%s\n' "$LINE"
