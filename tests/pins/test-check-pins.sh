#!/usr/bin/env bash
# Proves scripts/check-pins.sh catches a vendor change, not just that it passes
# today. Each case copies the step scripts, breaks one pin the way a vendor would,
# and expects the check to fail and name it. Uses the real network.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0

expect_caught() {
  local name="$1" file="$2" from="$3" to="$4" want="$5"
  local tree="$work/tree" out rc
  rm -rf "$tree"
  mkdir -p "$tree"
  (cd "$repo" && tar cf - install.sh update.sh step-*) | (cd "$tree" && tar xf -)

  if ! grep -qF -- "$from" "$tree/$file"; then
    echo "FAIL  $name: '$from' isn't in $file any more, so this case tests nothing"
    fails=$((fails + 1))
    return
  fi
  # Literal replacement, so a pin containing regex characters can't misfire.
  FROM="$from" TO="$to" perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$tree/$file"

  out="$(bash "$repo/scripts/check-pins.sh" "$tree" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -F -- "$want" | grep -q '^FAIL'; then
    echo "PASS  $name"
  else
    echo "FAIL  $name: rc=$rc, wanted a FAIL line containing '$want'"
    printf '%s\n' "$out" | grep -E '^(FAIL|[0-9]+ failed)' | sed 's/^/        /'
    fails=$((fails + 1))
  fi
}

expect_caught "file behind a SHA-256 pin changed" step-8/step-8-install.sh \
  'SKILL_SHA256="9' 'SKILL_SHA256="0' "SKILL_SHA256 mismatch"
expect_caught "pinned commit no longer exists" step-8/step-8-install.sh \
  'SKILL_COMMIT="cfb973bbecd7e2bb54deb15027ee8b5f5deb6513"' 'SKILL_COMMIT="0000000000000000000000000000000000000000"' "can't be downloaded"
expect_caught "pinned commit orphaned by a history rewrite" step-8/step-8-install.sh \
  'SKILL_COMMIT="cfb973bbecd7e2bb54deb15027ee8b5f5deb6513"' 'SKILL_COMMIT="0000000000000000000000000000000000000000"' "not on this repo's history"
expect_caught "vendor deleted a version-pinned release" step-1/step-1-install.sh \
  'nvm-sh/nvm/v0.40.1/' 'nvm-sh/nvm/v0.0.999/' "pinned release returned HTTP"
expect_caught "vendor deleted a release asset" step-2/ghostty-install.sh \
  'JetBrainsMono/releases/download/v2.304/' 'JetBrainsMono/releases/download/v0.0.1/' "pinned release returned HTTP"
expect_caught "npm package disappeared" step-4/step-4-install.sh \
  'pin_npm fidgetflo' 'pin_npm fidgetflo-does-not-exist-xyz' "npm fidgetflo-does-not-exist-xyz does not resolve"
expect_caught "PyPI package disappeared" step-3/step-3-install.sh \
  'pipx install xlsx2csv --force' 'pipx install xlsx2csv-does-not-exist-xyz --force' "PyPI xlsx2csv-does-not-exist-xyz does not resolve"
expect_caught "vendor bootstrap script moved" step-1/step-1-install.sh \
  'raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' 'raw.githubusercontent.com/Homebrew/install/HEAD/moved.sh' "vendor download returned HTTP"

echo ""
[ "$fails" -eq 0 ] && echo "All pin-failure cases were caught." || echo "$fails case(s) were not caught."
[ "$fails" -eq 0 ]
