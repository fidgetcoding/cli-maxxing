#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Step 2 — Bonus Software (Ghostty Terminal + Arc Browser)
# Both tools are optional but highly recommended. Ghostty gets a GPU-accelerated
# terminal with Cmd+Click links + g2/g4 tiling. Arc gets you a power-user
# browser with sidebar tabs, Spaces, split view, and built-in ad blocking.
# Both installers are idempotent — safe to re-run.
# =============================================================================

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

BASE_URL="https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/step-2"

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


echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Step 2 — Bonus Software${NC}"
echo -e "${BLUE}  Installing Ghostty Terminal and Arc Browser${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}>>> Ghostty Terminal${NC}"
echo ""
run_step "ghostty-install.sh" ghostty || true
echo ""

echo -e "${YELLOW}>>> Arc Browser${NC}"
echo ""
run_step "arc-install.sh" arc || true
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
    printf '[FAIL] Step 2 incomplete: %s\n' "${FAILED_STEPS[*]}" >&2
    exit 1
fi
echo -e "${GREEN}  Step 2 Complete — Ghostty and Arc are ready.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  NEXT: Continue to Step 3${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Run Step 3 to install developer tools (Python, jq, ripgrep, tree, fzf, etc.):"
echo ""
echo -e "     ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/step-3/step-3-install.sh)${NC}"
echo ""
