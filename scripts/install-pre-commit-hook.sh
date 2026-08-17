#!/usr/bin/env bash
# install-pre-commit-hook.sh — wires up the local pre-commit hook: gitleaks
# secret scanning plus the personal-context (PII) guard.
# Idempotent: safe to re-run.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/.git/hooks/pre-commit"

if ! command -v gitleaks &>/dev/null; then
  echo "⚠️  gitleaks not found on PATH — the hook will install, but secret" >&2
  echo "   scanning will be skipped until you install it:" >&2
  echo "   macOS:  brew install gitleaks" >&2
  echo "   Linux:  sudo apt install gitleaks   (Ubuntu 24.04+)" >&2
  echo "           or grab a release: https://github.com/gitleaks/gitleaks/releases" >&2
  echo "   The PII guard has no dependencies and runs regardless." >&2
  echo "" >&2
fi

mkdir -p "$REPO_ROOT/.git/hooks"
cat > "$HOOK" <<'HOOK_EOF'
#!/usr/bin/env bash
# pre-commit — two gates on staged content:
#   1. gitleaks   — hardcoded secrets
#   2. check-pii  — the maintainer's personal context / client roster
# Bypass for emergencies: git commit --no-verify
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
failed=0

# --- Gate 1: secrets --------------------------------------------------------
if command -v gitleaks &>/dev/null; then
  if ! gitleaks protect --staged --no-banner --redact -v 2>&1; then
    echo ""
    echo "🚨 SECRETS DETECTED in staged content." >&2
    echo "   Remove the secret from your changes (env vars / .env / secret manager)," >&2
    echo "   re-stage, and commit again. Output above is redacted." >&2
    failed=1
  fi
else
  echo "⚠️  gitleaks missing — skipping secret scan." >&2
fi

# --- Gate 2: personal context ----------------------------------------------
# This pack installs into other people's ~/.claude/skills/. A personal name or
# client roster in a skill file becomes an instruction to somebody else's Claude.
if [ -x "$REPO_ROOT/scripts/check-pii.sh" ]; then
  if ! "$REPO_ROOT/scripts/check-pii.sh" --staged; then
    failed=1
  fi
else
  echo "⚠️  scripts/check-pii.sh missing or not executable — skipping PII guard." >&2
fi

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "Commit BLOCKED. Emergency bypass (do NOT use for real secrets or client data):" >&2
  echo "  git commit --no-verify" >&2
  exit 1
fi
HOOK_EOF
chmod +x "$HOOK"

echo "✅ Installed pre-commit hook → $HOOK"
echo "   Gates: gitleaks (secrets) + scripts/check-pii.sh (personal context)"
echo "   Test secrets: stage a file with a fake gho_/ntn_ token, then try git commit."
echo "   Test PII:     add \"talks to <your name>\" to a skill file, then try git commit."
