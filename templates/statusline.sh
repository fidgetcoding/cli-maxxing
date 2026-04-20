#!/bin/bash
# Status Line — real state only
# 2ndBrain (Obsidian) + fidgetflo (MCP) + UIPro + Swarm/Hive activity

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
      "$VAULT_PATH"|"$VAULT_PATH"/*) BRAIN="🧠 2ndBrain" ;;
    esac
  fi
fi
if [ -z "$BRAIN" ] && [ -n "$CWD" ] && echo "$CWD" | grep -qiE "OBSIDIAN/(2ndBrain|MASTER)|/BRAIN2?(/|$)" 2>/dev/null; then
  BRAIN="🧠 2ndBrain"
fi

# --- fidgetflo CHECK ---
fidgetflo=""
if pgrep -f "fidgetflo.*mcp" >/dev/null 2>&1 || pgrep -f "fidgetflo/bin/cli" >/dev/null 2>&1 || pgrep -f "fidgetflo" >/dev/null 2>&1; then
  fidgetflo="⚡️ fidgetflo"
fi

# --- UIPRO CHECK (always on — global skill) ---
UIPRO="🎨 UIPro"

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
    if [ -n "$MINI_AGENT_COUNT" ]; then
      MINI="🍯 ${MINI_AGENT_COUNT}"
    else
      MINI="🍯"
    fi
  fi
fi

# --- BUILD THE LINE ---
PARTS=""
if [ -n "$BRAIN" ] && [ -n "$fidgetflo" ]; then
  PARTS="${BRAIN} + ${fidgetflo}"
elif [ -n "$BRAIN" ]; then
  PARTS="${BRAIN}"
elif [ -n "$fidgetflo" ]; then
  PARTS="${fidgetflo}"
fi

if [ -n "$PARTS" ]; then
  PARTS="${PARTS} + ${UIPRO}"
else
  PARTS="${UIPRO}"
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
  PARTS="${PARTS} [${ACTIVITY}]"
fi

echo "${PARTS} • ${MODEL} • ⏱ ${TIME_FMT} • ${CTX}% ctx"
