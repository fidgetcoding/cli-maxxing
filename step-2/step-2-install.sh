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

BASE_URL="https://raw.githubusercontent.com/lorecraft-io/cli-maxxing/main/step-2"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Step 2 — Bonus Software${NC}"
echo -e "${BLUE}  Installing Ghostty Terminal and Arc Browser${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}>>> Ghostty Terminal${NC}"
echo ""
curl -fsSL "$BASE_URL/ghostty-install.sh" | bash
echo ""

echo -e "${YELLOW}>>> Arc Browser${NC}"
echo ""
curl -fsSL "$BASE_URL/arc-install.sh" | bash
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Step 2 Complete — Ghostty and Arc are ready.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  NEXT: Continue to Step 3${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Run Step 3 to install developer tools (Python, jq, ripgrep, gh, etc.):"
echo ""
echo -e "     ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/lorecraft-io/cli-maxxing/main/step-3/step-3-install.sh)${NC}"
echo ""
