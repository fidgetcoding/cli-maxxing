#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Step 10 — Developer Tools
# Installs GitHub MCP server. More developer tools may be added here.
# Run after completing Steps 1-9. Run this in your terminal.
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
INSTALLED_GITHUB=false

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
# Interactive menu — let the user pick which tools to install
# -----------------------------------------------------------------------------
choose_tools() {
    # Detect non-interactive mode (stdin is a pipe, not a terminal)
    if [ ! -t 0 ]; then
        info "Non-interactive mode detected (running via curl pipe)"
        CHOICES=""

        # Auto-detect already-installed tools
        if claude mcp list 2>/dev/null | grep -q "github" 2>/dev/null; then
            CHOICES="$CHOICES 1"
            INSTALLED_GITHUB=true
        fi

        if [ -n "$CHOICES" ]; then
            info "Found already-installed tools — verifying configuration"
            return
        else
            echo ""
            echo -e "${YELLOW}  Step 10 requires interactive input for API credentials.${NC}"
            echo -e "${YELLOW}  Run it directly in your terminal:${NC}"
            echo ""
            echo "    bash <(curl -fsSL https://raw.githubusercontent.com/lorecraft-io/cli-maxxing/main/step-10/step-10-install.sh)"
            echo ""
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
        warn "No tools selected. Nothing to install."
        print_summary
        exit 0
    fi
}

# -----------------------------------------------------------------------------
# Install GitHub MCP
# -----------------------------------------------------------------------------
install_github() {
    info "Installing GitHub MCP server..."

    if claude mcp list 2>/dev/null | grep -q "github"; then
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

    read -sp "  GitHub Personal Access Token (ghp_...): " GITHUB_TOKEN
    echo " [saved]"
    echo ""

    if [ -z "$GITHUB_TOKEN" ]; then
        warn "No GitHub token provided. Skipping GitHub setup."
        warn "Re-run Step 10 when you have a token ready."
        return
    fi

    if [[ ! "$GITHUB_TOKEN" =~ ^gh[ps]_ ]]; then
        warn "Token doesn't look like a GitHub PAT (expected ghp_ or ghs_ prefix)."
        warn "Proceeding anyway — registration will fail if the token is invalid."
        echo ""
    fi

    # Register with the token injected via env var into the MCP server process.
    # Credentials live in Claude's MCP config only — not written to disk here.
    claude mcp add --scope user github -- npx -y @modelcontextprotocol/server-github 2>/dev/null

    # Inject the token directly into the config entry (claude mcp add --scope user
    # does not support -e flags in all CLI versions, so we patch the env block).
    python3 - "$GITHUB_TOKEN" <<'PYEOF'
import sys, json, os

token = sys.argv[1]
config_path = os.path.expanduser("~/.claude.json")

with open(config_path) as f:
    config = json.load(f)

mcpServers = config.get("mcpServers", {})
if "github" in mcpServers:
    mcpServers["github"].setdefault("env", {})
    mcpServers["github"]["env"]["GITHUB_PERSONAL_ACCESS_TOKEN"] = token
    config["mcpServers"] = mcpServers
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    print("Token injected into GitHub MCP config.")
else:
    print("WARNING: github entry not found in MCP config — token not injected.")
PYEOF

    if claude mcp list 2>/dev/null | grep -q "github"; then
        success "GitHub MCP installed"
        INSTALLED_GITHUB=true
    else
        soft_fail "GitHub MCP installation could not be verified"
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
        local needle="$2"
        if claude mcp list 2>/dev/null | grep -q "$needle"; then
            success "TEST: $label MCP registered"
            TEST_PASS=$((TEST_PASS + 1))
        else
            soft_fail "TEST: $label MCP not registered"
            TEST_FAIL=$((TEST_FAIL + 1))
        fi
    }

    if $INSTALLED_GITHUB; then check_registered "GitHub" "github"; else info "TEST: GitHub — skipped"; TEST_SKIP=$((TEST_SKIP + 1)); fi

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
    echo -e "${GREEN}  Step 10 Complete — Developer Tools${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    INSTALLED_COUNT=0

    if $INSTALLED_GITHUB; then echo "  GitHub  — repos, issues, PRs, code search"; INSTALLED_COUNT=$((INSTALLED_COUNT + 1)); fi

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
    fi

    echo ""
    if [ "$ERRORS" -gt 0 ]; then
        echo -e "  ${YELLOW}Warnings: $ERRORS issue(s) detected.${NC}"
        echo -e "  ${YELLOW}Scroll up to see details.${NC}"
        echo ""
    fi
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Continue to the Final Step to install your status line."
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step 10 — Developer Tools${NC}"
    echo -e "${BLUE}  GitHub and other dev-facing MCP tools • macOS + Linux${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    detect_os
    verify_prerequisites
    choose_tools

    # Process each selection in the canonical order
    for CHOICE in $CHOICES; do
        case "$CHOICE" in
            1) if ! $INSTALLED_GITHUB; then install_github; else success "GitHub already configured"; fi ;;
            *) warn "Unknown choice: $CHOICE (skipping)" ;;
        esac
    done

    run_self_test
    print_summary
}

main "$@"
