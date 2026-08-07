#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Step 7 — GitHub CLI + MCP + /gitfix + /recon + /osmani-build
# Installs the `gh` CLI (terminal binary), the GitHub MCP server, and the
# /gitfix + /recon + /osmani-build skills. `gh` installs unconditionally (no
# credentials needed) and is what /recon uses to sweep GitHub for prior art;
# the MCP install is gated on a Personal Access Token. /osmani-build also
# pulls in the addyosmani/agent-skills plugin (best-effort).
# Run after completing Steps 1-6. Run this in your terminal.
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
soft_fail() { echo -e "${RED}[FAIL]${NC} $1 (non-critical, continuing...)"; ERRORS=$((ERRORS + 1)); }

# Track what was installed this run
INSTALLED_GH=false
INSTALLED_GITHUB=false
INSTALLED_GITFIX=false
INSTALLED_RECON=false
INSTALLED_VBC=false

# -----------------------------------------------------------------------------
# Ensure runtime PATH (brew, nvm, ~/.local/bin) is visible.
# Defense-in-depth: users typically run this step in a fresh terminal after
# Steps 1-6 completed, but installers/nvm don't always source their shell
# rc files in non-login shells. This makes `node`, `npm`, and `claude`
# resolvable regardless of how the user invoked the script.
# -----------------------------------------------------------------------------
source_runtime_path() {
    # Homebrew shellenv — try the first brew binary we find.
    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
        if [ -x "$brew_bin" ]; then
            eval "$("$brew_bin" shellenv)" 2>/dev/null || true
            break
        fi
    done

    # nvm — source it if installed so `node`/`npm` resolve.
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh" 2>/dev/null || true
    fi

    # ~/.local/bin — prepend if not already on PATH.
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
}

# -----------------------------------------------------------------------------
# Detect OS
# -----------------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Darwin)       OS="mac" ;;
        Linux)        OS="linux" ;;
        MINGW*|MSYS*|CYGWIN*) fail "Windows is not supported. This script is for macOS and Linux only." ;;
        *)            fail "Unsupported OS: $(uname -s). This script supports macOS and Linux only." ;;
    esac
    info "Detected OS: $OS"
}

# -----------------------------------------------------------------------------
# Verify prerequisites
# -----------------------------------------------------------------------------
verify_prerequisites() {
    if ! command -v node &>/dev/null; then
        fail "Node.js not found. Run Step 1 first."
    fi
    if ! command -v claude &>/dev/null; then
        fail "Claude Code not found. Run Step 1 first."
    fi
    success "Prerequisites verified"
}

# -----------------------------------------------------------------------------
# GitHub CLI (`gh`) — terminal binary. Installs unconditionally: no credentials
# required, used by Claude via Bash (`gh pr create`, etc.) and by /gitfix for
# branch / diff inspection. Idempotent — skips when already present.
# -----------------------------------------------------------------------------
install_gh() {
    if command -v gh &>/dev/null; then
        success "GitHub CLI already installed ($(gh --version | head -1))"
        INSTALLED_GH=true
        return
    fi

    info "Installing GitHub CLI..."
    if [ "$OS" = "mac" ]; then
        brew install gh || { soft_fail "GitHub CLI installation failed"; return; }
    else
        if command -v apt-get &>/dev/null; then
            # Download keyring to a temp file first so a curl failure can't
            # poison /usr/share/keyrings with an empty/truncated file.
            local keyring_tmp
            keyring_tmp="$(mktemp)" || { soft_fail "Could not create temp file"; return; }
            if ! curl -fsSL --proto '=https' --proto-redir '=https' https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$keyring_tmp"; then
                rm -f "$keyring_tmp"
                soft_fail "Failed to download GitHub CLI keyring"
                return
            fi
            if ! [ -s "$keyring_tmp" ]; then
                rm -f "$keyring_tmp"
                soft_fail "Downloaded GitHub CLI keyring is empty"
                return
            fi
            sudo install -m 0644 "$keyring_tmp" /usr/share/keyrings/githubcli-archive-keyring.gpg
            rm -f "$keyring_tmp"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            if sudo apt-get update -qq && sudo apt-get install -y -qq gh; then
                :
            else
                soft_fail "GitHub CLI installation failed"
                return
            fi
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y gh || { soft_fail "GitHub CLI installation failed"; return; }
        else
            soft_fail "Could not install GitHub CLI — install manually: https://cli.github.com"
            return
        fi
    fi

    if command -v gh &>/dev/null; then
        success "GitHub CLI installed ($(gh --version | head -1))"
        INSTALLED_GH=true
    fi
}

# -----------------------------------------------------------------------------
# Interactive menu — let the user pick which tools to install
# -----------------------------------------------------------------------------
choose_tools() {
    # Detect non-interactive mode (stdin is a pipe, not a terminal)
    if [ ! -t 0 ]; then
        info "Non-interactive mode detected (running via curl pipe)"
        CHOICES=""

        # Auto-detect already-installed tools.
        # Anchor to start-of-line + literal name + ":" so we don't match
        # user-defined MCP servers like "my-github-fork" or "github-mirror".
        if claude mcp list 2>/dev/null | grep -qE '^github:' 2>/dev/null; then
            CHOICES="$CHOICES 1"
            INSTALLED_GITHUB=true
        fi

        if [ -n "$CHOICES" ]; then
            info "Found already-installed tools — verifying configuration"
            return
        else
            # No GitHub MCP yet and we can't prompt — still install /gitfix (no creds needed).
            echo ""
            echo -e "${YELLOW}  Step 7 requires interactive input to set up the GitHub MCP.${NC}"
            echo -e "${YELLOW}  Run it directly in your terminal to finish:${NC}"
            echo ""
            echo "    bash <(curl -fsSL https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/step-7/step-7-install.sh)"
            echo ""
            info "Continuing with non-interactive /gitfix + /recon + /osmani-build + /verify-before-claim install..."
            install_gitfix
            install_recon
            install_osmani_build
            install_verify_before_claim
            run_self_test
            print_summary
            exit 0
        fi
    fi

    echo ""
    echo -e "${BLUE}  Which developer tools do you use?${NC}"
    echo -e "${BLUE}  (enter numbers separated by spaces)${NC}"
    echo ""
    echo "    1) GitHub  — repos, issues, PRs, code search (requires Personal Access Token)"
    echo ""
    echo -e "${YELLOW}  This step is for developers. If you don't use GitHub with Claude,${NC}"
    echo -e "${YELLOW}  you can skip it — all earlier steps work without it.${NC}"
    echo ""
    read -rp "  Enter your choices (e.g. \"1\"): " CHOICES
    echo ""

    if [ -z "$CHOICES" ]; then
        # GitHub MCP is optional, but /gitfix is always installed in Step 7.
        # Return instead of exiting so main() can still install /gitfix.
        warn "No GitHub MCP selected — continuing to install /gitfix."
        return
    fi
}

# -----------------------------------------------------------------------------
# Install GitHub MCP
# -----------------------------------------------------------------------------
install_github() {
    info "Installing GitHub MCP server..."

    if claude mcp list 2>/dev/null | grep -qE '^github:'; then
        success "GitHub MCP already installed"
        INSTALLED_GITHUB=true
        return
    fi

    echo ""
    echo -e "${BLUE}  GitHub MCP gives Claude read/write access to your repos,${NC}"
    echo -e "${BLUE}  issues, pull requests, and code search via the GitHub API.${NC}"
    echo ""
    echo -e "${BLUE}  You need a Personal Access Token (classic PAT). Create one at:${NC}"
    echo -e "${BLUE}  https://github.com/settings/tokens/new${NC}"
    echo ""
    echo "    Suggested settings:"
    echo "      - Token name: claude-github-mcp"
    echo "      - Expiration: No expiration"
    echo "      - Scopes: repo, read:org, gist"
    echo ""
    echo -e "${YELLOW}  Use a classic token (not fine-grained) for full repo access.${NC}"
    echo -e "${YELLOW}  Check only: repo (top checkbox), read:org (under admin:org), gist.${NC}"
    echo ""

    read -rsp "  GitHub Personal Access Token (ghp_...): " GITHUB_TOKEN
    echo " [captured]"
    echo ""

    if [ -z "$GITHUB_TOKEN" ]; then
        warn "No GitHub token provided. Skipping GitHub setup."
        warn "Re-run Step 7 when you have a token ready."
        return
    fi

    if [[ ! "$GITHUB_TOKEN" =~ ^gh[ps]_ ]]; then
        warn "Token doesn't look like a GitHub PAT (expected ghp_ or ghs_ prefix)."
        warn "Proceeding anyway — registration will fail if the token is invalid."
        echo ""
    fi

    # Register GitHub's official hosted MCP server (https://api.githubcopilot.com/mcp).
    # Replaces the deprecated `@modelcontextprotocol/server-github` npm package —
    # that one's been retired in favor of github/github-mcp-server, which runs
    # as a remote HTTP server behind GitHub's API domain. The PAT is passed as
    # a Bearer token via -H so it lives in Claude's MCP config, never on disk
    # in this repo. (It is briefly visible in the local process list while
    # `claude mcp add` runs — unavoidable with argv-passed headers; fine on a
    # single-user machine.)
    claude mcp add --scope user --transport http github \
        https://api.githubcopilot.com/mcp \
        -H "Authorization: Bearer $GITHUB_TOKEN" 2>/dev/null

    if claude mcp list 2>/dev/null | grep -qE '^github:'; then
        success "GitHub MCP installed"
        INSTALLED_GITHUB=true
    else
        soft_fail "GitHub MCP installation could not be verified — try manually: claude mcp add --scope user --transport http github https://api.githubcopilot.com/mcp -H \"Authorization: Bearer <your-PAT>\""
    fi
    unset GITHUB_TOKEN
}

# -----------------------------------------------------------------------------
# Install /gitfix skill
# -----------------------------------------------------------------------------
install_gitfix() {
    GITFIX_DIR="$HOME/.claude/skills/gitfix"
    GITFIX_FILE="$GITFIX_DIR/SKILL.md"
    GITFIX_URL="https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/gitfix-skill/SKILL.md"

    mkdir -p "$GITFIX_DIR"

    if [ -f "$GITFIX_FILE" ]; then
        info "Updating existing /gitfix skill..."
        INSTALLED_GITFIX=true
    else
        info "Installing /gitfix skill..."
    fi

    GITFIX_TMP="$GITFIX_FILE.tmp"
    if curl -fsSL --proto '=https' --proto-redir '=https' "$GITFIX_URL" -o "$GITFIX_TMP" 2>/dev/null && [ -s "$GITFIX_TMP" ]; then
        mv "$GITFIX_TMP" "$GITFIX_FILE"
        success "/gitfix skill installed at $GITFIX_FILE"
        INSTALLED_GITFIX=true
    else
        rm -f "$GITFIX_TMP"
        warn "Download failed — attempting local fallback..."
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
        LOCAL_GITFIX="$(dirname "$SCRIPT_DIR")/gitfix-skill/SKILL.md"
        if [ -f "$LOCAL_GITFIX" ]; then
            cp "$LOCAL_GITFIX" "$GITFIX_FILE"
            success "/gitfix skill installed from local copy"
            INSTALLED_GITFIX=true
        else
            soft_fail "Could not install /gitfix skill — download and local fallback both failed"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Install /recon skill — pre-build prior-art recon (depends on the gh CLI)
# -----------------------------------------------------------------------------
install_recon() {
    RECON_DIR="$HOME/.claude/skills/recon"
    RECON_FILE="$RECON_DIR/SKILL.md"
    RECON_URL="https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/recon-skill/SKILL.md"

    mkdir -p "$RECON_DIR"

    if [ -f "$RECON_FILE" ]; then
        info "Updating existing /recon skill..."
        INSTALLED_RECON=true
    else
        info "Installing /recon skill..."
    fi

    RECON_TMP="$RECON_FILE.tmp"
    if curl -fsSL --proto '=https' --proto-redir '=https' "$RECON_URL" -o "$RECON_TMP" 2>/dev/null && [ -s "$RECON_TMP" ]; then
        mv "$RECON_TMP" "$RECON_FILE"
        success "/recon skill installed at $RECON_FILE"
        INSTALLED_RECON=true
    else
        rm -f "$RECON_TMP"
        warn "Download failed — attempting local fallback..."
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
        LOCAL_RECON="$(dirname "$SCRIPT_DIR")/recon-skill/SKILL.md"
        if [ -f "$LOCAL_RECON" ]; then
            cp "$LOCAL_RECON" "$RECON_FILE"
            success "/recon skill installed from local copy"
            INSTALLED_RECON=true
        else
            soft_fail "Could not install /recon skill — download and local fallback both failed"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Install /verify-before-claim skill — look-don't-guess gate.
#
# Fires before answering anything about installed MCP servers, subscription
# pricing, or which AI models exist. Those three question classes are where an
# assistant is most confidently wrong: the answer is cheap to look up and
# expensive to get wrong, so it should never come from memory. Ships with a
# 5-claim adversarial test suite where a correct verdict WITHOUT a cited
# source counts as a failure.
#
# Has a references/ directory, so this one copies a tree rather than a single
# SKILL.md — hence the per-file fetch with a local directory fallback.
# -----------------------------------------------------------------------------
install_verify_before_claim() {
    VBC_DIR="$HOME/.claude/skills/verify-before-claim"
    VBC_FILE="$VBC_DIR/SKILL.md"
    VBC_REF_DIR="$VBC_DIR/references"
    VBC_BASE="https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/verify-before-claim-skill"

    mkdir -p "$VBC_REF_DIR"

    if [ -f "$VBC_FILE" ]; then
        info "Updating existing /verify-before-claim skill..."
    else
        info "Installing /verify-before-claim skill..."
    fi

    VBC_OK=false
    VBC_TMP="$VBC_FILE.tmp"
    if curl -fsSL --proto '=https' --proto-redir '=https' "$VBC_BASE/SKILL.md" -o "$VBC_TMP" 2>/dev/null && [ -s "$VBC_TMP" ]; then
        mv "$VBC_TMP" "$VBC_FILE"
        # references/test-claims.md is part of the contract — the skill tells
        # you to re-run it after any edit, so a missing file is a broken skill.
        curl -fsSL --proto '=https' --proto-redir '=https' \
            "$VBC_BASE/references/test-claims.md" -o "$VBC_REF_DIR/test-claims.md" 2>/dev/null || \
            warn "/verify-before-claim: test suite did not download (skill still works)"
        VBC_OK=true
    else
        rm -f "$VBC_TMP"
        warn "Download failed — attempting local fallback..."
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
        LOCAL_VBC="$(dirname "$SCRIPT_DIR")/verify-before-claim-skill"
        if [ -f "$LOCAL_VBC/SKILL.md" ]; then
            cp "$LOCAL_VBC/SKILL.md" "$VBC_FILE"
            [ -d "$LOCAL_VBC/references" ] && cp -R "$LOCAL_VBC/references/." "$VBC_REF_DIR/"
            VBC_OK=true
        fi
    fi

    if [ "$VBC_OK" = true ]; then
        success "/verify-before-claim skill installed at $VBC_FILE"
        INSTALLED_VBC=true
    else
        soft_fail "Could not install /verify-before-claim skill — download and local fallback both failed"
    fi
}

# -----------------------------------------------------------------------------
# Install /osmani-build skill — phase-gated product-build lifecycle.
# Orchestrates the addyosmani/agent-skills plugin (installed best-effort below).
# -----------------------------------------------------------------------------
install_osmani_build() {
    OSMANI_DIR="$HOME/.claude/skills/osmani-build"
    OSMANI_FILE="$OSMANI_DIR/SKILL.md"
    OSMANI_URL="https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/osmani-build-skill/SKILL.md"

    mkdir -p "$OSMANI_DIR"

    if [ -f "$OSMANI_FILE" ]; then
        info "Updating existing /osmani-build skill..."
    else
        info "Installing /osmani-build skill..."
    fi

    OSMANI_TMP="$OSMANI_FILE.tmp"
    if curl -fsSL --proto '=https' --proto-redir '=https' "$OSMANI_URL" -o "$OSMANI_TMP" 2>/dev/null && [ -s "$OSMANI_TMP" ]; then
        mv "$OSMANI_TMP" "$OSMANI_FILE"
        success "/osmani-build skill installed at $OSMANI_FILE"
    else
        rm -f "$OSMANI_TMP"
        warn "Download failed — attempting local fallback..."
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
        LOCAL_OSMANI="$(dirname "$SCRIPT_DIR")/osmani-build-skill/SKILL.md"
        if [ -f "$LOCAL_OSMANI" ]; then
            cp "$LOCAL_OSMANI" "$OSMANI_FILE"
            success "/osmani-build skill installed from local copy"
        else
            soft_fail "Could not install /osmani-build skill — download and local fallback both failed"
            return
        fi
    fi

    # Best-effort dependency: the addyosmani/agent-skills plugin (24 lifecycle skills).
    # HTTPS marketplace URL + per-invocation SSH→HTTPS rewrite so machines without
    # a GitHub SSH key still succeed.
    if command -v claude >/dev/null 2>&1; then
        if claude plugin list 2>/dev/null | grep -q "agent-skills@addy-agent-skills"; then
            success "addy-agent-skills plugin already installed"
        else
            info "Installing addyosmani/agent-skills plugin (dependency of /osmani-build)..."
            claude plugin marketplace add https://github.com/addyosmani/agent-skills.git >/dev/null 2>&1 || true
            if GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.https://github.com/.insteadOf" GIT_CONFIG_VALUE_0="git@github.com:" \
                claude plugin install agent-skills@addy-agent-skills >/dev/null 2>&1; then
                success "addy-agent-skills plugin installed (24 lifecycle skills)"
            else
                warn "/osmani-build installed, but the agent-skills plugin didn't — run manually:"
                warn "  claude plugin marketplace add https://github.com/addyosmani/agent-skills.git"
                warn "  claude plugin install agent-skills@addy-agent-skills"
            fi
        fi
    else
        warn "claude CLI not on PATH — install the agent-skills plugin later so /osmani-build has its 24 phase skills"
    fi
}

# -----------------------------------------------------------------------------
# Self-test — check each installed tool is registered
# -----------------------------------------------------------------------------
run_self_test() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Running Self-Test${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    TEST_PASS=0
    TEST_FAIL=0
    TEST_SKIP=0

    check_registered() {
        local label="$1"
        local name="$2"
        # Anchor to start-of-line + literal name + ":" so we don't match
        # user-defined MCP servers whose names contain the target as a substring.
        if claude mcp list 2>/dev/null | grep -qE "^${name}:"; then
            success "TEST: $label MCP registered"
            TEST_PASS=$((TEST_PASS + 1))
        else
            soft_fail "TEST: $label MCP not registered"
            TEST_FAIL=$((TEST_FAIL + 1))
        fi
    }

    # gh CLI install is unconditional in Step 7, so this test always runs.
    # A failure here means install_gh hit a soft_fail (unsupported package
    # manager, sudo denied, etc.) — scroll up for the install-time message.
    if command -v gh &>/dev/null; then
        success "TEST: gh CLI installed ($(gh --version | head -1))"
        TEST_PASS=$((TEST_PASS + 1))
    else
        soft_fail "TEST: gh CLI not found on PATH"
        TEST_FAIL=$((TEST_FAIL + 1))
    fi

    if $INSTALLED_GITHUB; then check_registered "GitHub" "github"; else info "TEST: GitHub MCP — skipped"; TEST_SKIP=$((TEST_SKIP + 1)); fi

    if $INSTALLED_GITFIX; then
        success "TEST: /gitfix skill installed"
        TEST_PASS=$((TEST_PASS + 1))
    else
        soft_fail "TEST: /gitfix skill not found"
        TEST_FAIL=$((TEST_FAIL + 1))
    fi

    if $INSTALLED_RECON; then
        success "TEST: /recon skill installed"
        TEST_PASS=$((TEST_PASS + 1))
    else
        soft_fail "TEST: /recon skill not found"
        TEST_FAIL=$((TEST_FAIL + 1))
    fi

    if $INSTALLED_VBC; then
        success "TEST: /verify-before-claim skill installed"
        TEST_PASS=$((TEST_PASS + 1))
    else
        soft_fail "TEST: /verify-before-claim skill not found"
        TEST_FAIL=$((TEST_FAIL + 1))
    fi

    echo ""
    if [ "$TEST_FAIL" -eq 0 ]; then
        echo -e "  ${GREEN}All $TEST_PASS tests passed.${NC} ($TEST_SKIP skipped)"
    else
        echo -e "  ${GREEN}$TEST_PASS passed${NC}, ${RED}$TEST_FAIL failed${NC}, $TEST_SKIP skipped."
        echo -e "  ${YELLOW}Scroll up to see what went wrong.${NC}"
    fi
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Step 7 Complete — GitHub CLI + MCP + /gitfix + /recon${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    INSTALLED_COUNT=0

    if $INSTALLED_GH; then echo "  gh CLI  — GitHub from your terminal ($(gh --version 2>/dev/null | head -1))"; INSTALLED_COUNT=$((INSTALLED_COUNT + 1)); fi
    if $INSTALLED_GITHUB; then echo "  GitHub MCP — repos, issues, PRs, code search"; INSTALLED_COUNT=$((INSTALLED_COUNT + 1)); fi
    if $INSTALLED_GITFIX; then
        echo "  /gitfix — full-repo consistency audit: docs, scripts, and README all in sync"
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    fi
    if $INSTALLED_RECON; then
        echo "  /recon — pre-build prior-art sweep: ranks competitors, finds the edge before you build"
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    fi
    if $INSTALLED_VBC; then
        echo "  /verify-before-claim — checks config and billing before answering, instead of guessing"
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    fi

    if [ "$INSTALLED_COUNT" -eq 0 ]; then
        echo "  No tools were installed."
    else
        echo ""
        echo "  $INSTALLED_COUNT tool(s) installed and ready in Claude Code."
        echo ""
        echo "  What you can do now:"

        if $INSTALLED_GITHUB; then
            echo "    - Ask Claude to list open PRs or issues on any of your repos"
            echo "    - Ask Claude to search code across your GitHub organizations"
            echo "    - Ask Claude to create issues, review diffs, or push commits"
        fi
        echo "    - Run /gitfix inside any Claude session to sync all docs with reality"
        echo "    - Run /recon <thing> before building anything to sweep what already exists"
    fi

    echo ""
    if [ "$ERRORS" -gt 0 ]; then
        echo -e "  ${YELLOW}Warnings: $ERRORS issue(s) detected.${NC}"
        echo -e "  ${YELLOW}Scroll up to see details.${NC}"
        echo ""
    fi
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Continue to Step 8 (Safety Check) or the Final Step (Status Line)."
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    source_runtime_path

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step 7 — GitHub CLI + MCP + /gitfix + /recon${NC}"
    echo -e "${BLUE}  gh CLI + GitHub MCP + /gitfix + /recon skills • macOS + Linux${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    detect_os
    verify_prerequisites
    install_gh
    choose_tools

    # Process each selection in the canonical order
    for CHOICE in $CHOICES; do
        case "$CHOICE" in
            1) if ! $INSTALLED_GITHUB; then install_github; else success "GitHub already configured"; fi ;;
            *) warn "Unknown choice: $CHOICE (skipping)" ;;
        esac
    done

    # /gitfix, /recon, and /osmani-build always install (no interactive input required)
    install_gitfix
    install_recon
    install_osmani_build
    install_verify_before_claim

    run_self_test
    print_summary

    # Breadcrumb for /doctor and re-run detection.
    mkdir -p "$HOME/.cli-maxxing" 2>/dev/null || true
    touch "$HOME/.cli-maxxing/step-7.done" 2>/dev/null || true
}

main "$@"
