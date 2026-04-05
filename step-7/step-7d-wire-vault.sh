#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Step 7d — Wire up your vault
# Processes inbox, creates wikilinks, builds MOCs, validates everything
# Run inside a cskip session
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

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Step 7d — Wire Up Your Vault${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Find vault
VAULT_PATH="${VAULT_PATH:-}"
if [ -z "$VAULT_PATH" ]; then
    for candidate in \
        "$HOME/Desktop/2ndBrain" \
        "$HOME/Desktop/Second-Brain" \
        "$HOME/Desktop/Vault" \
        "$HOME/Documents/2ndBrain" \
        "$HOME/Documents/Second-Brain"; do
        if [ -d "$candidate/00-Inbox" ]; then
            VAULT_PATH="$candidate"
            break
        fi
    done
    if [ -z "$VAULT_PATH" ]; then
        FOUND=$(find "$HOME/Desktop" "$HOME/Documents" -maxdepth 3 -name "00-Inbox" -type d 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then
            VAULT_PATH="$(dirname "$FOUND")"
        fi
    fi
fi

if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH/00-Inbox" ]; then
    fail "Could not find your vault. Run Step 7a first, or set VAULT_PATH manually."
fi

success "Vault found at: $VAULT_PATH"

# -----------------------------------------------------------------------------
# Install Obsidian MCP (connects Claude to the vault)
# -----------------------------------------------------------------------------
if claude mcp list 2>/dev/null | grep -q "obsidian"; then
    success "Obsidian MCP already installed"
else
    info "Installing Obsidian MCP server..."
    claude mcp add --scope user obsidian -- npx -y obsidian-mcp "$VAULT_PATH" 2>/dev/null

    if claude mcp list 2>/dev/null | grep -q "obsidian"; then
        success "Obsidian MCP installed (connected to $VAULT_PATH)"
    else
        warn "Obsidian MCP installation could not be verified. You can add it manually:"
        echo "    claude mcp add --scope user obsidian -- npx -y obsidian-mcp \"$VAULT_PATH\""
    fi
fi

# -----------------------------------------------------------------------------
# Post-install MCP verification — check configured paths actually exist
# -----------------------------------------------------------------------------
info "Verifying MCP configurations..."

# Check Obsidian vault path in MCP config
OBSIDIAN_MCP_LINE=$(claude mcp list 2>/dev/null | grep -i "obsidian" || true)
if [ -n "$OBSIDIAN_MCP_LINE" ]; then
    # The vault path was passed as an argument to obsidian-mcp during registration.
    # Verify the vault path we just configured actually exists on disk.
    if [ -d "$VAULT_PATH" ]; then
        success "Obsidian MCP vault path verified: $VAULT_PATH exists"
    else
        warn "Obsidian MCP is configured but the vault path does not exist on disk: $VAULT_PATH"
        echo ""
        echo -e "    ${YELLOW}To fix this, remove and re-add the MCP with the correct path:${NC}"
        echo "    claude mcp remove obsidian"
        echo "    claude mcp add --scope user obsidian -- npx -y obsidian-mcp /path/to/your/vault"
        echo ""
    fi

    # Verify the vault has the expected Zettelkasten structure
    if [ -d "$VAULT_PATH/00-Inbox" ] && [ -d "$VAULT_PATH/03-Permanent" ]; then
        success "Obsidian vault structure verified (00-Inbox, 03-Permanent exist)"
    else
        warn "Obsidian vault exists but may not have the expected folder structure."
        echo "    Run Step 7a to create the Zettelkasten folders."
    fi
fi

# Check for any other MCP servers that may have stale paths
# (Motion Calendar uses .env, not a path arg, so check that separately)
if claude mcp list 2>/dev/null | grep -q "motion-calendar"; then
    if [ -f "$HOME/.motion-calendar-mcp/.env" ]; then
        # Check if any required keys are empty
        MOTION_EMPTY_KEYS=0
        for key in MOTION_API_KEY FIREBASE_API_KEY FIREBASE_REFRESH_TOKEN MOTION_USER_ID; do
            VAL=$(grep "^${key}=" "$HOME/.motion-calendar-mcp/.env" 2>/dev/null | cut -d= -f2)
            if [ -z "$VAL" ]; then
                MOTION_EMPTY_KEYS=$((MOTION_EMPTY_KEYS + 1))
            fi
        done
        if [ "$MOTION_EMPTY_KEYS" -gt 0 ]; then
            warn "Motion Calendar MCP has $MOTION_EMPTY_KEYS empty credential(s) in ~/.motion-calendar-mcp/.env"
            echo "    Edit ~/.motion-calendar-mcp/.env and fill in the missing values."
        else
            success "Motion Calendar MCP credentials present"
        fi
    fi
fi

# Check Notion MCP token
if claude mcp list 2>/dev/null | grep -q "notion"; then
    # Notion token is passed as env var during mcp add — if the MCP is registered, the token was provided
    success "Notion MCP registered"
fi

# Count current state
INBOX_COUNT=$(find "$VAULT_PATH/00-Inbox" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
FLEETING_COUNT=$(find "$VAULT_PATH/01-Fleeting" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
LIT_COUNT=$(find "$VAULT_PATH/02-Literature" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
PERM_COUNT=$(find "$VAULT_PATH/03-Permanent" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
MOC_COUNT=$(find "$VAULT_PATH/04-MOC" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
PROJECT_COUNT=$(find "$VAULT_PATH/07-Projects" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
PROJECT_COUNT=$((PROJECT_COUNT - 1)) # subtract the dir itself
TOTAL_NOTES=$(find "$VAULT_PATH" -name "*.md" -not -path "*/05-Templates/*" -not -name "CLAUDE.md" 2>/dev/null | wc -l | tr -d ' ')

echo ""
info "Current vault status:"
echo "    Inbox:      $INBOX_COUNT notes waiting to be processed"
echo "    Fleeting:   $FLEETING_COUNT notes"
echo "    Literature: $LIT_COUNT notes"
echo "    Permanent:  $PERM_COUNT notes"
echo "    MOCs:       $MOC_COUNT maps of content"
echo "    Projects:   $PROJECT_COUNT project folders"
echo "    Total:      $TOTAL_NOTES notes"
echo ""

# Auto-link orphan files to their parent project (idempotent — skips if link already present)
info "Linking orphan files to parent projects..."
LINK_COUNT=0
while IFS= read -r f; do
    project=$(echo "$f" | sed "s|$VAULT_PATH/07-Projects/||" | cut -d'/' -f1)
    if [ -n "$project" ] && ! grep -qF "[[${project}]]" "$f" 2>/dev/null; then
        printf "\n\n---\n[[%s]]\n" "$project" >> "$f"
        LINK_COUNT=$((LINK_COUNT + 1))
    fi
done < <(find "$VAULT_PATH/07-Projects" -name '*.md')
success "Linked orphan files to parent projects"

# Embed unlinked media files in project index notes
info "Embedding unlinked media files..."
while IFS= read -r f; do
    name=$(basename "$f")
    # Check if already embedded anywhere
    if ! grep -rq --include='*.md' "!\\[\\[${name}\\]\\]" "$VAULT_PATH" 2>/dev/null; then
        project=$(echo "$f" | sed "s|$VAULT_PATH/07-Projects/||" | cut -d'/' -f1)
        index="$VAULT_PATH/07-Projects/${project}/${project}.md"
        if [ -f "$index" ]; then
            printf "\n![[%s]]\n" "$name" >> "$index"
        fi
    fi
done < <(find "$VAULT_PATH/07-Projects" -type f -not -name '*.md')
success "Media files embedded"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Step 7d — Ready for Claude to Wire Everything Up${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  This is where Claude connects everything together."
echo "  Tell Claude:"
echo ""
echo "  'Wire up my vault at $VAULT_PATH. Here's what I need:"
echo ""
echo "   1. Process everything in 00-Inbox — sort each note into"
echo "      01-Fleeting, 02-Literature, or 03-Permanent based on"
echo "      what it is."
echo ""
echo "   2. Create [[wikilinks]] between related notes across"
echo "      all folders."
echo ""
echo "   3. Make sure all links are bidirectional — if Note A"
echo "      links to Note B, Note B should link back to Note A."
echo ""
echo "   4. Build Maps of Content in 04-MOC for any topic clusters"
echo "      you find."
echo ""
echo "   5. Create project index notes in 07-Projects for any"
echo "      project that doesn't have one yet."
echo ""
echo "   6. Convert any wikilinks inside markdown tables to"
echo "      bullet lists (Obsidian graph can't see links in tables)."
echo ""
echo "   7. Add proper YAML frontmatter to any notes missing it."
echo ""
echo "   8. Validate all files — flag anything corrupt or empty.'"
echo ""
echo "  This is the big one. Let Claude work through it."
echo "  It might take a while depending on how many notes you have."
echo ""
echo "  When Claude is done, open Obsidian and click the graph view"
echo "  icon in the left sidebar (looks like connected dots)."
echo "  That's your knowledge base, visualized."
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
