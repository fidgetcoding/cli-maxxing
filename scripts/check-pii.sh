#!/usr/bin/env bash
# check-pii.sh — block a maintainer's personal operating context from shipping
# in the public pack.
#
# WHY THIS EXISTS
# ---------------
# Every skill file in this repo gets written into a recipient's ~/.claude/skills/
# by the installers. Anything personal in those files becomes an instruction to
# somebody else's Claude: address the operator by the wrong name, apply the wrong
# repo conventions, and — worst case — disclose a private client roster to a
# client. That is exactly what happened on 2026-08-17: a scrub landed downstream
# on 2026-06-23, upstream never followed, and the next update overwrote it.
#
# TWO LAYERS OF PATTERNS
# ----------------------
# 1. Generic, in this file: real home directories, bare email addresses, and
#    second-person violations. No names — safe to publish.
# 2. Private, NEVER in this file: your own client/project roster and vault name.
#    Supplied at runtime so the list itself stays out of the public repo.
#      • locally  → .pii-patterns.local  (gitignored; see the .example file)
#      • in CI    → PII_EXTRA_PATTERNS repo secret
#    A public CI script that hardcoded the roster would publish the very thing
#    it is meant to protect.
#
# Usage:
#   scripts/check-pii.sh                  # scan all tracked files
#   scripts/check-pii.sh --staged         # scan staged content only (pre-commit)
#   scripts/check-pii.sh FILE [FILE...]   # scan specific files
#
# Escape hatch: put `pii-allow` in a comment on the offending line. Use it for
# genuine placeholders and attribution, never to push real client data.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- Layer 1: generic markers (publishable) ----------------------------------
# A real home directory path — /Users/<someone>/ or /home/<someone>/. Example
# paths in docs should read /abs/path/to/thing or ~/MyVault instead.
GENERIC='(/Users/|/home/)[a-z][a-z0-9._-]{2,}/'

# A bare email address. Placeholder and third-party service addresses are
# excluded below.
GENERIC="$GENERIC"'|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'

# Not a leak: placeholder domains and paths, system service accounts (Linuxbrew
# installs to a fixed /home/linuxbrew prefix), and third-party addresses that a
# rule needs verbatim to be actionable.
GENERIC_OK='example\.(com|org|net)|yourdomain|your-domain|placeholder'
GENERIC_OK="$GENERIC_OK"'|<[A-Za-z_ -]+>|/abs/path/|/path/to/|/home/user/|~/MyVault'
GENERIC_OK="$GENERIC_OK"'|/home/linuxbrew/|noreply@|user@host|git@github\.com|ruv@ruv\.net'

# --- Layer 2: private markers (supplied at runtime) --------------------------
PRIVATE=""
PRIVATE_SOURCE="none"

if [ -n "${PII_EXTRA_PATTERNS:-}" ]; then
    PRIVATE="$PII_EXTRA_PATTERNS"
    PRIVATE_SOURCE="PII_EXTRA_PATTERNS env"
elif [ -f "$REPO_ROOT/.pii-patterns.local" ]; then
    # One extended-regex per line; blank lines and # comments ignored.
    PRIVATE="$(grep -vE '^\s*(#|$)' "$REPO_ROOT/.pii-patterns.local" 2>/dev/null | paste -sd '|' -)"
    PRIVATE_SOURCE=".pii-patterns.local"
fi

# --- Allowlist ---------------------------------------------------------------
# "<path>|<tier>" pairs that are intentional. Everything else is a hard fail.
is_allowed() {
    case "$1|$2" in
        # Public authorship, license, vulnerability-report contact.
        'README.md|generic')                         return 0 ;;
        'LICENSE|generic')                           return 0 ;;
        'SECURITY.md|generic')                       return 0 ;;
        'README.md|private')                         return 0 ;;
        'LICENSE|private')                           return 0 ;;
        'SECURITY.md|private')                       return 0 ;;
        # Historical record of the prior identity collapse.
        'CHANGELOG.md|generic')                      return 0 ;;
        'CHANGELOG.md|private')                      return 0 ;;
        # This file documents the pattern mechanism itself.
        'scripts/check-pii.sh|generic')              return 0 ;;
        'scripts/check-pii.sh|private')              return 0 ;;
        '.pii-patterns.local.example|generic')       return 0 ;;
        '.pii-patterns.local.example|private')       return 0 ;;
        # Vault-detection heuristics: candidate-path lists and a regex that match
        # any path ending in /BRAIN or /BRAIN2. Guesses at a directory name, not
        # a disclosure — and removing them breaks vault auto-detection.
        'step-4/step-4-install.sh|private')          return 0 ;;
        'step-final/step-final-install.sh|private')  return 0 ;;
        'templates/statusline.sh|private')           return 0 ;;
        'templates/cbrain|private')                  return 0 ;;
        'templates/cbraintg|private')                return 0 ;;
        'tests/install-flow-walkthrough.md|private') return 0 ;;
        'tests/install-flow-walkthrough.md|generic') return 0 ;;
        *) return 1 ;;
    esac
}

# --- File list ---------------------------------------------------------------
mode="tracked"
files=()
case "${1:-}" in
    --staged) mode="staged" ;;
    "")       mode="tracked" ;;
    *)        mode="explicit"; files=("$@") ;;
esac

case "$mode" in
    staged)
        while IFS= read -r f; do [ -n "$f" ] && files+=("$f")
        done < <(git diff --cached --name-only --diff-filter=ACMR)
        ;;
    tracked)
        while IFS= read -r f; do [ -n "$f" ] && files+=("$f")
        done < <(git ls-files)
        ;;
esac

if [ "${#files[@]}" -eq 0 ]; then
    echo "✅ check-pii: nothing to scan"
    exit 0
fi

if [ -z "$PRIVATE" ]; then
    echo "⚠️  check-pii: no private pattern list found — running generic checks only." >&2
    echo "   Add your client/project roster to .pii-patterns.local (see" >&2
    echo "   .pii-patterns.local.example), or set the PII_EXTRA_PATTERNS secret in CI." >&2
    echo "" >&2
fi

# --- Scan --------------------------------------------------------------------
violations=0
for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    case "$f" in
        *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.tar.gz|*.ico|*.woff*) continue ;;
        .git/*|node_modules/*) continue ;;
    esac
    grep -Iq . "$f" 2>/dev/null || continue   # skip binary

    for tier in generic private; do
        if [ "$tier" = "generic" ]; then
            pat="$GENERIC"
        else
            [ -z "$PRIVATE" ] && continue
            pat="$PRIVATE"
        fi
        is_allowed "$f" "$tier" && continue

        while IFS=: read -r lineno line; do
            [ -z "${lineno:-}" ] && continue
            case "$line" in *pii-allow*) continue ;; esac
            # Generic tier only: skip lines whose match is a known placeholder.
            if [ "$tier" = "generic" ] && printf '%s' "$line" | grep -qE "$GENERIC_OK"; then
                continue
            fi
            if [ "$violations" -eq 0 ]; then
                echo ""
                echo "🚨 Personal operating context found in shippable files:"
                echo ""
            fi
            printf '  %s:%s\n      [%s] %s\n' \
                "$f" "$lineno" "$tier" "$(printf '%s' "$line" | cut -c1-110)"
            violations=$((violations + 1))
        done < <(grep -nE "$pat" "$f" 2>/dev/null)
    done
done

if [ "$violations" -gt 0 ]; then
    cat >&2 <<'EOM'

  This pack installs into other people's ~/.claude/skills/ — personal names,
  client names, real home paths, and private vault paths must not ship.

  Fix: write skill prose in the second person ("you", "the user"), replace
  client rosters with a "list your own projects here" note, and use generic
  example paths (/abs/path/to/x, ~/MyVault).

  Genuine placeholder or attribution? Add 'pii-allow' in a comment on the line,
  or extend the allowlist in scripts/check-pii.sh.
EOM
    echo "  $violations violation(s). Private patterns from: $PRIVATE_SOURCE" >&2
    echo "" >&2
    exit 1
fi

echo "✅ check-pii: clean (${#files[@]} files scanned, private patterns: $PRIVATE_SOURCE)"
