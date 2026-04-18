#!/bin/bash
# Status Line — real state only
# 2ndBrain (Obsidian) + fidgetflo (MCP) + UIPro + Swarm/Hive activity

input=$(cat)

# Parse Claude Code's JSON input
MODEL=$(echo "$input" | jq -r '.model.display_name // "Opus 4.6"' 2>/dev/null)
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)

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

# --- fidgetflo CHECK ---
fidgetflo=""
if pgrep -f "fidgetflo.*mcp" >/dev/null 2>&1 || pgrep -f "fidgetflo/bin/cli" >/dev/null 2>&1 || pgrep -f "fidgetflo" >/dev/null 2>&1; then
  fidgetflo="⚡️ fidgetflo"
fi

# --- UIPRO CHECK (always on — global skill) ---
UIPRO="🎨 UIPro"

# --- SWARM CHECK (only shows when actively running) ---
# Lock file alone isn't enough — validate swarm processes are alive.
# If lock file exists but nothing's running, clean it up (stale session).
SWARM=""
SWARM_LOCK="/tmp/fidgetflo-swarm-active"
if [ -f "$SWARM_LOCK" ] 2>/dev/null; then
  if pgrep -f "swarm.*init|fidgetflo.*swarm" >/dev/null 2>&1; then
    AGENT_COUNT=$(cat "$SWARM_LOCK" 2>/dev/null || echo "")
    if [ -n "$AGENT_COUNT" ]; then
      SWARM="🐝 ${AGENT_COUNT}"
    else
      SWARM="🐝"
    fi
  else
    # Stale lock file — no swarm processes running, clean up
    rm -f "$SWARM_LOCK" 2>/dev/null
  fi
fi

# --- MINI CHECK (only shows when actively running) ---
# 5-agent compact swarm (/fmini*). Lock file holds agent count.
MINI=""
MINI_LOCK="/tmp/fidgetflo-mini-active"
if [ -f "$MINI_LOCK" ] 2>/dev/null; then
  if pgrep -f "swarm.*init|fidgetflo.*swarm|fidgetflo.*mini" >/dev/null 2>&1; then
    AGENT_COUNT=$(cat "$MINI_LOCK" 2>/dev/null || echo "")
    if [ -n "$AGENT_COUNT" ]; then
      MINI="🍯 ${AGENT_COUNT}"
    else
      MINI="🍯"
    fi
  else
    # Stale lock file — no mini-swarm processes running, clean up
    rm -f "$MINI_LOCK" 2>/dev/null
  fi
fi

# --- HIVE CHECK (only shows when actively running) ---
# Same validation — lock file + live process required.
HIVE=""
HIVE_LOCK="/tmp/fidgetflo-hive-active"
if [ -f "$HIVE_LOCK" ] 2>/dev/null; then
  if pgrep -f "hive-mind|fidgetflo.*hive" >/dev/null 2>&1; then
    HIVE="👑 Hive"
  else
    # Stale lock file — no hive processes running, clean up
    rm -f "$HIVE_LOCK" 2>/dev/null
  fi
fi

# --- BUILD THE LINE ---
PARTS=""

# fidgetflo
if [ -n "$fidgetflo" ]; then
  PARTS="${fidgetflo}"
fi

# UIPro (always on)
if [ -n "$PARTS" ]; then
  PARTS="${PARTS} + ${UIPRO}"
else
  PARTS="${UIPRO}"
fi

# Swarm / Mini / Hive activity (any combination can be active)
ACTIVITY=""
[ -n "$SWARM" ] && ACTIVITY="${ACTIVITY:+${ACTIVITY} + }${SWARM}"
[ -n "$MINI" ]  && ACTIVITY="${ACTIVITY:+${ACTIVITY} + }${MINI}"
[ -n "$HIVE" ]  && ACTIVITY="${ACTIVITY:+${ACTIVITY} + }${HIVE}"
if [ -n "$ACTIVITY" ]; then
  PARTS="${PARTS} [${ACTIVITY}]"
fi

echo "${PARTS} • ${MODEL} • ⏱ ${TIME_FMT} • ${CTX}% ctx"
