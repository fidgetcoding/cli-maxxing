#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# CLI Maxxing — Update
# Re-runs all steps, skips anything already installed, picks up anything new.
# Each step-N-install.sh is idempotent and handles its own shell integrations
# (writing to both zsh + bash configs on macOS via SHELL_RCS / SHELL_PROFILES).
# Usage: curl -fsSL <hosted-url>/update.sh | bash
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_URL="https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main"

# Download a complete, syntax-checked script before executing any of it.
# Embedded in each entry point because the public one-liners run standalone.
DOWNLOAD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cli-maxxing-download.XXXXXX") || exit 1
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
FAILED_STEPS=()
run_step() {
    local path="$1" crumb script rc=0
    shift
    script="$DOWNLOAD_DIR/step.sh"
    for crumb in "$@"; do
        rm -f "$HOME/.cli-maxxing/$crumb.done" || { FAILED_STEPS+=("$path"); return 1; }
    done
    if curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 \
        "$BASE_URL/$path" -o "$script" && [ -s "$script" ] && bash -n "$script"; then
        # Steps 5–7 remain non-interactive in a batch; credentials are entered
        # only when the user explicitly runs those steps in their terminal.
        bash "$script" </dev/null || rc=$?
    else
        rc=1
    fi
    if [ "$rc" -ne 0 ]; then
        for crumb in "$@"; do rm -f "$HOME/.cli-maxxing/$crumb.done"; done
        FAILED_STEPS+=("$path")
        printf '[FAIL] %s did not complete (exit %s). Re-run this step after fixing the error.\n' "$path" "$rc" >&2
    fi
    return "$rc"
}


# -----------------------------------------------------------------------------
# source_runtime_path — defense-in-depth PATH hydration before re-running every
# step. Step 1 installs brew/nvm on a fresh machine; on update runs those tools
# are usually already on disk but not yet sourced into this non-interactive
# shell. Idempotent — safe to call multiple times.
# -----------------------------------------------------------------------------
source_runtime_path() {
    # 1. Homebrew shellenv (Apple Silicon + Intel macOS + Linuxbrew)
    if command -v brew &>/dev/null; then
        eval "$(brew shellenv)" 2>/dev/null || true
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
    elif [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
    fi

    # 2. nvm — source so node/npm/claude installed under a node version resolve
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1091
        set +u # nvm reads unset internal variables during auto-use
        \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
        set -u
    fi

    # 3. Prepend ~/.local/bin to PATH idempotently (ctg and friends live here)
    if [ -d "$HOME/.local/bin" ]; then
        case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *) export PATH="$HOME/.local/bin:$PATH" ;;
        esac
    fi
}

main() {
    # Apply the same admin/network gate as a fresh install before updates.
    local preflight
    if ! preflight=$(curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 "$BASE_URL/scripts/preflight.sh") \
        || [ -z "$preflight" ] || ! bash -n <<< "$preflight"; then
        echo "[FAIL] Could not download preflight; update stopped." >&2
        return 1
    fi
    eval "$preflight"
    command -v cm_preflight >/dev/null 2>&1 && cm_preflight || return 1

    # Hydrate PATH at the very top so every child curl|bash step inherits a
    # usable brew/nvm/~/.local/bin environment, not just steps after step-1.
    source_runtime_path

    # Breadcrumb dir — child step scripts touch step-N.done here on success.
    mkdir -p "$HOME/.cli-maxxing"

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  CLI Maxxing — Update${NC}"
    echo -e "${BLUE}  Running all steps, skipping what's already installed${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Step 1 — CLI Tools
    echo -e "${YELLOW}>>> Running Step 1 — CLI Tools${NC}"
    echo ""
    run_step "step-1/step-1-install.sh" step-1 || exit 1
    # Re-hydrate in case step-1 just installed brew/nvm for the first time and
    # the remaining curl|bash steps need them on PATH.
    source_runtime_path
    echo ""

    # Step 2 — Bonus Software (Ghostty + Arc, idempotent)
    echo -e "${YELLOW}>>> Running Step 2 — Bonus Software${NC}"
    echo ""
    if [ "${CLI_MAXXING_NO_SUDO:-0}" != "1" ]; then
        run_step "step-2/step-2-install.sh" ghostty arc || true
    else
        echo "[SKIP] Step 2 needs admin rights."
    fi
    echo ""

    # Step 3 — Developer & Utility Tools
    echo -e "${YELLOW}>>> Running Step 3 — Developer & Utility Tools${NC}"
    echo ""
    if [ "${CLI_MAXXING_NO_SUDO:-0}" != "1" ]; then
        run_step "step-3/step-3-install.sh" step-3 || true
    else
        echo "[SKIP] Step 3 needs admin rights."
    fi
    echo ""

    # Step 4 — refreshes fidgetflo/agentic-flow + skill files (/w4w, /concise, /fswarm*, /fmini*, /fhive)
    echo -e "${YELLOW}>>> Running Step 4 — FidgetFlo${NC}"
    echo ""
    if [ "${CLI_MAXXING_NO_SUDO:-0}" != "1" ] || command -v jq >/dev/null 2>&1; then
        run_step "step-4/step-4-install.sh" step-4 || true
    else
        echo "[SKIP] Step 4 needs jq."
    fi
    echo ""

    # Step 5 (Productivity Tools)
    echo -e "${YELLOW}>>> Running Step 5 — Productivity Tools${NC}"
    echo ""
    run_step "step-5/step-5-install.sh" step-5 || true
    echo ""

    # Step 6 (Telegram)
    echo -e "${YELLOW}>>> Running Step 6 — Telegram${NC}"
    echo ""
    run_step "step-6/step-6-install.sh" step-6 || true
    echo ""

    # Step 7 (GitHub MCP + /gitfix + /recon)
    echo -e "${YELLOW}>>> Running Step 7 — GitHub${NC}"
    echo ""
    run_step "step-7/step-7-install.sh" step-7 || true
    echo ""

    # Step 8 — refreshes /safetycheck skill
    echo -e "${YELLOW}>>> Running Step 8 — Safety Check${NC}"
    echo ""
    run_step "step-8/step-8-install.sh" step-8 || true
    echo ""

    # Final Step (Status Line — wrap-up)
    echo -e "${YELLOW}>>> Running Final Step — Status Line${NC}"
    echo ""
    run_step "step-final/step-final-install.sh" step-final || true
    echo ""

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
        printf '[FAIL] Update incomplete: %s\n' "${FAILED_STEPS[*]}" >&2
        return 1
    fi
    echo -e "${GREEN}  Update complete for eligible steps. Account-dependent steps may be skipped.${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo "  Available commands: cskip, ctg, cc, ccr, ccc"
    echo "  Available skills:   /fswarm, /fmini, /fhive, /w4w, /concise, /bullets, /safetycheck, /gitfix, /recon"
    echo "  Swarm tiers:        /fswarm{1,2,3,max}, /fmini{1,2,3,max} — 1=think, 2=think hard, 3=think harder, max=ultrathink"
    echo "  Design + media:     github.com/fidgetcoding/creativity-maxxing"
    echo "  Second Brain:       github.com/fidgetcoding/2ndBrain-mogging"
    echo ""
    echo "  Note: Steps 5, 6, and 7 require interactive input (API credentials,"
    echo "  Telegram bot token, and GitHub PAT). They may skip themselves if run"
    echo "  non-interactively. Run them directly in your terminal if needed:"
    echo ""
    echo "    Step 5: bash <(curl -fsSL https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/step-5/step-5-install.sh)"
    echo "    Step 6: bash <(curl -fsSL https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/step-6/step-6-install.sh)"
    echo "    Step 7: bash <(curl -fsSL https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/step-7/step-7-install.sh)"
    echo ""
    echo "  Open a new terminal window for aliases to take effect."
    echo ""
    echo "  On macOS, shell integrations are written to BOTH .zshrc/.zprofile"
    echo "  AND .bashrc/.bash_profile so Terminal.app (which launches zsh even"
    echo "  when your passwd shell is bash) still picks up aliases + PATH."
    echo ""
}

main "$@"
