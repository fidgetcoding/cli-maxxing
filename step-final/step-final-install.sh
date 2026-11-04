#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Final Step — Status Line
# Installs the custom status line that shows what's active at a glance
# Run after completing Steps 1-8
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Serialize this installer's settings merges and atomically replace valid JSON.
# Existing custom status lines belong to the user; a null entry is unconfigured.
configure_statusline() (
    local settings="$HOME/.claude/settings.json" tmp="" lock
    lock="$settings.cli-maxxing-lock"
    mkdir "$lock" 2>/dev/null || { warn "Settings are being updated by another installer: $lock"; return 1; }
    trap '[ -z "$tmp" ] || rm -f "$tmp"; rmdir "$lock"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    tmp=$(mktemp "$HOME/.claude/.settings.XXXXXX") || return 1
    if [ -f "$settings" ]; then
        if ! command -v jq >/dev/null 2>&1; then
            warn "jq unavailable; existing settings preserved. Run Step 3 and Final again to configure the status line."
            return 0
        fi
        jq -es '
          if length == 1 and (.[0] | type) == "object" then .[0]
          else error("settings must be one JSON object") end |
          if .statusLine == null then
            .statusLine = {"type":"command", "command":"~/.claude/statusline.sh"}
          elif (.statusLine | type) == "object" and .statusLine.type == "command"
               and (.statusLine.command | type) == "string" and (.statusLine.command | length) > 0 then .
          else error("invalid statusLine configuration") end
        ' "$settings" > "$tmp" || return 1
    else
        printf '%s\n' '{"statusLine":{"type":"command","command":"~/.claude/statusline.sh"}}' > "$tmp" || return 1
    fi
    chmod 600 "$tmp" && mv "$tmp" "$settings" || return 1
)

# -----------------------------------------------------------------------------
# source_runtime_path — load brew/nvm/~/.local/bin into current PATH so that
# health checks (node, claude, jq, etc.) see what's actually installed on disk
# even if the parent shell never sourced its rc files. Idempotent.
# -----------------------------------------------------------------------------
source_runtime_path() {
    # 1. Homebrew shellenv (macOS + Linuxbrew) — adds brew-managed bins to PATH
    if command -v brew &>/dev/null; then
        eval "$(brew shellenv)" 2>/dev/null || true
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
    elif [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
    fi

    # 2. nvm — source the script so `node` / `claude` (if installed via npm -g
    # under a node version) become visible in this shell
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1091
        set +u # nvm reads unset internal variables during auto-use
        \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
        set -u
    fi

    # 3. Prepend ~/.local/bin to PATH (idempotent — skip if already present)
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
}

# Refresh PATH before any health check so we see commands that were installed
# in earlier steps but haven't been picked up by this shell yet.
source_runtime_path
rm -f "$HOME/.cli-maxxing/step-final.done" || fail "Could not clear previous completion marker"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Final Step — Status Line${NC}"
echo -e "${BLUE}  Final config — status indicators + system health check${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check jq is available (needed for status line)
if ! command -v jq &>/dev/null; then
    warn "jq not found — install it with: brew install jq (or run Step 3)"
fi

# Create .claude directory if it doesn't exist
mkdir -p "$HOME/.claude" || fail "Could not create ~/.claude"

# Install statusline.sh
info "Installing status line script..."
STATUSLINE_TMP=$(mktemp "$HOME/.claude/.statusline.XXXXXX") || fail "Could not create statusline temporary file"
trap 'rm -f "$STATUSLINE_TMP"' EXIT
cat > "$STATUSLINE_TMP" << 'STATUSLINE_EOF'
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
STATUSLINE_EOF

if [ "$?" -ne 0 ] || ! chmod 755 "$STATUSLINE_TMP" || ! mv "$STATUSLINE_TMP" "$HOME/.claude/statusline.sh"; then
    fail "Could not install statusline script"
fi
success "Status line script installed at ~/.claude/statusline.sh"

# Configure only global settings; project overrides are intentional user choices.
info "Configuring Claude Code settings..."
SETTINGS_FILE="$HOME/.claude/settings.json"
configure_statusline || fail "Could not configure status line; existing settings preserved."

# =============================================================================
# Health Check — verify all commands from previous steps
# =============================================================================
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Running Health Check${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Detect shell RC
case "${SHELL:-/bin/bash}" in
    */zsh)  SHELL_RC="$HOME/.zshrc" ;;
    */bash) SHELL_RC="$HOME/.bashrc" ;;
    *)      SHELL_RC="$HOME/.bashrc" ;;
esac

HC_PASS=0
HC_FAIL=0
# Optional add-ons (e.g., 2ndBrain-mogging) are tracked separately so we don't
# tell the user to "re-run a step" when nothing is actually broken.
OPTIONAL_FAIL=0
OPTIONAL_MSGS=()

# --- Shell aliases ---
for alias_check in \
    "cskip:claude --dangerously-skip-permissions" \
    "cc:claude" \
    "ccr:claude --resume" \
    "ccc:claude --continue"; do
    ALIAS_NAME="${alias_check%%:*}"
    ALIAS_CMD="${alias_check#*:}"
    if grep -q "alias ${ALIAS_NAME}=" "$SHELL_RC" 2>/dev/null; then
        success "HEALTH: $ALIAS_NAME alias — configured"
        HC_PASS=$((HC_PASS + 1))
    else
        warn "HEALTH: $ALIAS_NAME alias — missing, adding now..."
        echo "alias ${ALIAS_NAME}='${ALIAS_CMD}'" >> "$SHELL_RC"
        success "HEALTH: $ALIAS_NAME alias — fixed"
        HC_PASS=$((HC_PASS + 1))
    fi
done

# --- ~/.local/bin on PATH ---
if grep -q '\.local/bin' "$SHELL_RC" 2>/dev/null; then
    success "HEALTH: ~/.local/bin on PATH"
    HC_PASS=$((HC_PASS + 1))
else
    warn "HEALTH: ~/.local/bin not on PATH, adding now..."
    # SC2016: $HOME inside single quotes is intentional — written to shell rc
    # where it must expand at login time, not at install time.
    # shellcheck disable=SC2016
    { echo ""; echo '# Local bin (cbrain, cbraintg, ctg)'; echo 'export PATH="$HOME/.local/bin:$PATH"'; } >> "$SHELL_RC"
    success "HEALTH: ~/.local/bin PATH — fixed"
    HC_PASS=$((HC_PASS + 1))
fi

# --- cbrain script (optional — installed by 2ndBrain-mogging) ---
if [ -x "$HOME/.local/bin/cbrain" ]; then
    success "HEALTH: cbrain command — installed"
    HC_PASS=$((HC_PASS + 1))
else
    info "HEALTH: cbrain not installed — optional add-on (install 2ndBrain-mogging for vault-aware Claude aliases: https://github.com/fidgetcoding/2ndBrain-mogging)"
    OPTIONAL_FAIL=$((OPTIONAL_FAIL + 1))
    OPTIONAL_MSGS+=("cbrain — install 2ndBrain-mogging (https://github.com/fidgetcoding/2ndBrain-mogging) for vault-aware Claude aliases")
fi

# --- cbraintg script (optional — installed by 2ndBrain-mogging) ---
if [ -x "$HOME/.local/bin/cbraintg" ]; then
    success "HEALTH: cbraintg command — installed"
    HC_PASS=$((HC_PASS + 1))
else
    info "HEALTH: cbraintg not installed — optional add-on (install 2ndBrain-mogging for vault-aware Claude aliases: https://github.com/fidgetcoding/2ndBrain-mogging)"
    OPTIONAL_FAIL=$((OPTIONAL_FAIL + 1))
    OPTIONAL_MSGS+=("cbraintg — install 2ndBrain-mogging (https://github.com/fidgetcoding/2ndBrain-mogging) for vault-aware Claude aliases")
fi

# --- ctg script (token-guarded — not an alias) ---
# Migrate: remove stale alias if step-1 hasn't cleaned it up yet
if grep -q 'alias ctg=' "$SHELL_RC" 2>/dev/null; then
    # sed -i.bak works on both BSD (macOS) and GNU sed. The .bak file is
    # only needed as a safety net during the edit — clean it up afterward
    # so we don't leave ~/.zshrc.bak lying around.
    sed -i.bak '/alias ctg=/d' "$SHELL_RC"
    rm -f "${SHELL_RC}.bak"
    warn "HEALTH: removed stale ctg alias from $SHELL_RC — replaced by ~/.local/bin/ctg"
fi
if [ -x "$HOME/.local/bin/ctg" ]; then
    success "HEALTH: ctg command — installed"
    HC_PASS=$((HC_PASS + 1))
else
    warn "HEALTH: ctg not found — run Step 1 again to install"
    HC_FAIL=$((HC_FAIL + 1))
fi

# --- g2/g4 commands (macOS only) ---
if [ "$(uname -s)" = "Darwin" ]; then
    if grep -q 'g2()' "$SHELL_RC" 2>/dev/null; then
        success "HEALTH: g2/g4 window tiling — configured"
        HC_PASS=$((HC_PASS + 1))
    else
        warn "HEALTH: g2/g4 not found — run the Ghostty bonus step to install"
        HC_FAIL=$((HC_FAIL + 1))
    fi
fi

# --- No-flicker mode ---
if grep -q 'CLAUDE_CODE_NO_FLICKER' "$SHELL_RC" 2>/dev/null; then
    success "HEALTH: no-flicker mode — enabled"
    HC_PASS=$((HC_PASS + 1))
else
    warn "HEALTH: no-flicker mode not set — run Step 3 again to enable"
    HC_FAIL=$((HC_FAIL + 1))
fi

# --- Memory hook ---
if [ -f "$HOME/.claude/settings.json" ] && grep -q '"Stop"' "$HOME/.claude/settings.json" 2>/dev/null; then
    success "HEALTH: memory auto-save hook — configured"
    HC_PASS=$((HC_PASS + 1))
else
    warn "HEALTH: memory hook not found — run Step 3 again to configure"
    HC_FAIL=$((HC_FAIL + 1))
fi

# --- Claude Code (fallback-check nvm glob in case PATH is stale) ---
if command -v claude &>/dev/null; then
    success "HEALTH: Claude Code — installed"
    HC_PASS=$((HC_PASS + 1))
else
    NVM_CLAUDE=$(find "$HOME/.nvm/versions/node" -name "claude" -path "*/bin/claude" 2>/dev/null | head -n1)
    if [ -n "${NVM_CLAUDE:-}" ] && [ -x "$NVM_CLAUDE" ]; then
        info "HEALTH: Claude Code found at $NVM_CLAUDE (not on current shell's PATH — open a new shell or source ~/.zshrc to use it)"
        HC_PASS=$((HC_PASS + 1))
    else
        warn "HEALTH: Claude Code not found — run Step 1 first"
        HC_FAIL=$((HC_FAIL + 1))
    fi
fi

# --- jq ---
if command -v jq &>/dev/null; then
    success "HEALTH: jq — installed"
    HC_PASS=$((HC_PASS + 1))
else
    warn "HEALTH: jq not found — run Step 3 first"
    HC_FAIL=$((HC_FAIL + 1))
fi

echo ""
echo "  Health check: $HC_PASS passed, $HC_FAIL issues found."
if [ "$HC_FAIL" -gt 0 ]; then
    echo ""
    echo -e "  ${YELLOW}Some install items need attention. Scroll up to see which steps to re-run.${NC}"
    echo -e "  ${YELLOW}Or just launch cskip and ask Claude to fix them — it'll figure it out.${NC}"
fi
if [ "$OPTIONAL_FAIL" -gt 0 ]; then
    echo ""
    echo -e "  ${BLUE}Optional add-ons (not installed — everything still works without them):${NC}"
    for msg in "${OPTIONAL_MSGS[@]}"; do
        echo -e "    ${BLUE}•${NC} $msg"
    done
fi

# =============================================================================
# Self-Test — status line specifically
# =============================================================================
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Running Status Line Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TEST_PASS=0
TEST_FAIL=0

# Test 1: statusline.sh exists and is executable
if [ -x "$HOME/.claude/statusline.sh" ]; then
    success "TEST: statusline.sh installed and executable"
    TEST_PASS=$((TEST_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} TEST: statusline.sh not found or not executable"
    TEST_FAIL=$((TEST_FAIL + 1))
fi

# Test 2: settings.json has statusLine
if grep -q '"statusLine"' "$SETTINGS_FILE" 2>/dev/null; then
    success "TEST: settings.json has statusLine config"
    TEST_PASS=$((TEST_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} TEST: settings.json missing statusLine config"
    TEST_FAIL=$((TEST_FAIL + 1))
fi

# Test 3: Status line produces output
TEST_OUTPUT=$(echo '{"model":{"display_name":"Test"},"context_window":{"used_percentage":10},"cost":{"total_duration_ms":5000},"workspace":{"current_dir":"/test"}}' | "$HOME/.claude/statusline.sh" 2>/dev/null)
if [ -n "$TEST_OUTPUT" ]; then
    success "TEST: status line produces output — $TEST_OUTPUT"
    TEST_PASS=$((TEST_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} TEST: status line produced no output"
    TEST_FAIL=$((TEST_FAIL + 1))
fi

# Test 4: /gitfix skill present (installed by Step 7)
if [ -s "$HOME/.claude/skills/gitfix/SKILL.md" ]; then
    success "TEST: /gitfix skill present (installed by Step 7)"
    TEST_PASS=$((TEST_PASS + 1))
else
    warn "TEST: /gitfix skill not found — run Step 7 to install it"
    OPTIONAL_FAIL=$((OPTIONAL_FAIL + 1))
fi

# Test 4b: /recon skill present (installed by Step 7)
if [ -s "$HOME/.claude/skills/recon/SKILL.md" ]; then
    success "TEST: /recon skill present (installed by Step 7)"
    TEST_PASS=$((TEST_PASS + 1))
else
    warn "TEST: /recon skill not found — run Step 7 to install it"
    OPTIONAL_FAIL=$((OPTIONAL_FAIL + 1))
fi

echo ""
echo "  $TEST_PASS tests passed, $TEST_FAIL failed."
[ "$TEST_FAIL" -eq 0 ] || fail "Status line verification failed; re-run Final after fixing the error."

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Final Step Complete — Status Line + Health Check${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Skills (installed by earlier steps):"
echo "    /gitfix      — full-repo consistency audit: docs, scripts, and code all in sync (Step 7)"
echo ""
echo "  Status line indicators:"
echo "    🧠 Brain²  — in Obsidian vault"
echo "    ⚡️ fidgetflo  — MCP server connected"
echo "    🐝 Swarm     — swarm active (during /fswarm)"
echo "    👑 Hive      — hive-mind active (during /fhive)"
echo "    🍯 Mini      — mini swarm active (during /fmini)"
echo ""
echo -e "  ${YELLOW}Important: Until you set up Second Brain (2ndBrain-mogging), use cskip${NC}"
echo -e "  ${YELLOW}instead of cbrain. cbrain requires an Obsidian vault to exist.${NC}"
echo ""
echo "  Next steps:"
echo "    1. Open a new terminal (or restart Claude Code) to pick up the status line."
echo "    2. See CHEATSHEET.md in this repo for every alias, slash command, and tool."
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  You're all set. CLI Maxxing is complete.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Mark step complete (best-effort — don't fail the run if mkdir/touch can't write)
mkdir -p "$HOME/.cli-maxxing" 2>/dev/null || true
touch "$HOME/.cli-maxxing/step-final.done" || fail "Could not record Final completion"
