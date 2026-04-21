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

BASE_URL="https://raw.githubusercontent.com/lorecraft-io/cli-maxxing/main"

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
        \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
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
    curl -fsSL "$BASE_URL/step-1/step-1-install.sh" | bash
    # Re-hydrate in case step-1 just installed brew/nvm for the first time and
    # the remaining curl|bash steps need them on PATH.
    source_runtime_path
    echo ""

    # Step 2 — Bonus Software (Ghostty + Arc, idempotent)
    echo -e "${YELLOW}>>> Running Step 2 — Bonus Software${NC}"
    echo ""
    curl -fsSL "$BASE_URL/step-2/step-2-install.sh" | bash
    echo ""

    # Step 3 — Developer & Utility Tools
    echo -e "${YELLOW}>>> Running Step 3 — Developer & Utility Tools${NC}"
    echo ""
    curl -fsSL "$BASE_URL/step-3/step-3-install.sh" | bash
    echo ""

    # Step 4 — refreshes fidgetflo/agentic-flow + skill files (/w4w, /fswarm*, /fmini*, /fhive, get-api-docs)
    echo -e "${YELLOW}>>> Running Step 4 — FidgetFlo + Context Hub${NC}"
    echo ""
    curl -fsSL "$BASE_URL/step-4/step-4-install.sh" | bash
    echo ""

    # Step 5 (Productivity Tools)
    echo -e "${YELLOW}>>> Running Step 5 — Productivity Tools${NC}"
    echo ""
    curl -fsSL "$BASE_URL/step-5/step-5-install.sh" | bash
    echo ""

    # Step 6 (Telegram)
    echo -e "${YELLOW}>>> Running Step 6 — Telegram${NC}"
    echo ""
    curl -fsSL "$BASE_URL/step-6/step-6-install.sh" | bash
    echo ""

    # Step 7 (GitHub MCP + /gitfix)
    echo -e "${YELLOW}>>> Running Step 7 — GitHub${NC}"
    echo ""
    curl -fsSL "$BASE_URL/step-7/step-7-install.sh" | bash
    echo ""

    # Step 8 — refreshes /safetycheck skill
    echo -e "${YELLOW}>>> Running Step 8 — Safety Check${NC}"
    echo ""
    curl -fsSL "$BASE_URL/step-8/step-8-install.sh" | bash
    echo ""

    # Final Step (Status Line — wrap-up)
    echo -e "${YELLOW}>>> Running Final Step — Status Line${NC}"
    echo ""
    curl -fsSL "$BASE_URL/step-final/step-final-install.sh" | bash
    echo ""

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Update complete. All steps are current.${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo "  Available commands: cskip, ctg, cc, ccr, ccc"
    echo "  Available skills:   /fswarm, /fmini, /fhive, /w4w, /safetycheck, /gitfix, get-api-docs (auto-triggered)"
    echo "  Swarm tiers:        /fswarm{1,2,3,max}, /fmini{1,2,3,max} — 1=think, 2=think hard, 3=think harder, max=ultrathink"
    echo "  Design + media:     github.com/lorecraft-io/creativity-maxxing"
    echo "  Second Brain:       github.com/lorecraft-io/2ndBrain-mogging"
    echo ""
    echo "  Note: Steps 6 and 8 require interactive input (API credentials"
    echo "  and Telegram bot token). They may skip themselves if run"
    echo "  non-interactively. Run them directly in your terminal if needed:"
    echo ""
    echo "    Step 6: bash <(curl -fsSL https://raw.githubusercontent.com/lorecraft-io/cli-maxxing/main/step-6/step-6-install.sh)"
    echo "    Step 8: bash <(curl -fsSL https://raw.githubusercontent.com/lorecraft-io/cli-maxxing/main/step-8/step-8-install.sh)"
    echo ""
    echo "  Open a new terminal window for aliases to take effect."
    echo ""
    echo "  On macOS, shell integrations are written to BOTH .zshrc/.zprofile"
    echo "  AND .bashrc/.bash_profile so Terminal.app (which launches zsh even"
    echo "  when your passwd shell is bash) still picks up aliases + PATH."
    echo ""
}

main "$@"
