#!/usr/bin/env bash
# cbrain installer — adds cbrain command to ~/.local/bin

install_cbrain() {
  local BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"

  cat > "$BIN_DIR/cbrain" << 'EOF'
#!/usr/bin/env bash
# cbrain — Launch Claude Code in 2ndBrain Obsidian vault with full permissions
VAULT="$HOME/Desktop/2ndBrain"
if [ ! -d "$VAULT" ]; then
  echo "Error: 2ndBrain vault not found at $VAULT"
  exit 1
fi
cd "$VAULT" && exec claude --dangerously-skip-permissions "$@"
EOF

  chmod +x "$BIN_DIR/cbrain"

  # Ensure ~/.local/bin is in PATH
  local SHELL_RC="$HOME/.zshrc"
  [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.bashrc"

  if ! grep -q '.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
  fi

  echo "[OK] cbrain installed at $BIN_DIR/cbrain"
}

install_cbrain
