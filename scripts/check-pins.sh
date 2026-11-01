#!/usr/bin/env bash
# Checks that everything the installer pins or depends on still resolves, so a
# vendor deleting a release, moving a tag or changing a file gets caught by a
# scheduled job here and not by someone's install. Pins are read out of the step
# scripts each run, so there's no second list to keep in sync.
#
# Usage: scripts/check-pins.sh [root]    root defaults to this repo
# Needs: bash, curl, jq, git. Exit 0 if every pin resolves, 1 if not.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${1:-$here/..}" && pwd)"
cd "$root" || exit 2

fails=0
warns=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; echo "::error::$1"; fails=$((fails + 1)); }
warn() { echo "WARN  $1"; echo "::warning::$1"; warns=$((warns + 1)); }

steps=()
while IFS= read -r f; do steps+=("$f"); done < <(find . -path ./terminal-academy -prune -o -type f -name '*.sh' \( -path './step-*' -o -name install.sh -o -name update.sh \) -print | sort)

# Comments and README-style echo lines may quote URLs that nothing downloads.
active_lines() { grep -hv '^[[:space:]]*#' "${steps[@]}" | grep -Ev '^[[:space:]]*(echo|warn|info|success|fail|soft_fail)\b'; }

# Status of a real download, following redirects, without fetching the whole file.
http_status() {
  curl -sS -o /dev/null -L --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 15 --max-time 60 \
    -r 0-0 -w '%{http_code}' "$1" 2>/dev/null
}
check_url() {
  local status
  status="$(http_status "$1")"
  case "$status" in
    200|206) pass "$2 ($1)" ;;
    *)       fail "$2 returned HTTP ${status:-no response}: $1" ;;
  esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

echo "== Pinned commit and SHA-256 downloads"
pin_files=()
while IFS= read -r f; do pin_files+=("$f"); done < <(grep -l '_SHA256="' "${steps[@]}" || true)
sha_pins=0
for file in "${pin_files[@]+"${pin_files[@]}"}"; do
  while IFS= read -r name; do
    sha_pins=$((sha_pins + 1))
    prefix="${name%_SHA256}"
    want="$(grep -E "^[[:space:]]*${name}=\"" "$file" | head -1 | cut -d'"' -f2)"
    commit="$(grep -E "^[[:space:]]*${prefix}_COMMIT=\"" "$file" | head -1 | cut -d'"' -f2)"
    url="$(grep -E "^[[:space:]]*${prefix}_URL=\"" "$file" | head -1 | cut -d'"' -f2)"
    url="${url//\$\{${prefix}_COMMIT\}/$commit}"
    if [ -z "$want" ] || [ -z "$url" ]; then
      fail "$file: $name has no matching ${prefix}_URL, so this script can't check it"
      continue
    fi
    tmp="$(mktemp)"
    if curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 --max-time 60 "$url" -o "$tmp" 2>/dev/null; then
      got="$(sha256_of "$tmp")"
      if [ "$got" = "$want" ]; then
        pass "$file: $name matches ($url)"
      else
        fail "$file: $name mismatch. Pinned $want, the URL now serves $got: $url"
      fi
    else
      fail "$file: $name can't be downloaded: $url"
    fi
    rm -f "$tmp"
    # raw.githubusercontent keeps serving commits a history rewrite orphaned, so
    # HTTP 200 doesn't show the pin is still part of this repo's history.
    if [ -n "$commit" ] && git -C "$here/.." rev-parse --git-dir >/dev/null 2>&1; then
      if git -C "$here/.." merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
        pass "$file: ${prefix}_COMMIT is on this repo's history"
      else
        fail "$file: ${prefix}_COMMIT $commit is not on this repo's history (orphaned, or a shallow clone)"
      fi
    fi
  done < <(grep -Eo '^[[:space:]]*[A-Z0-9_]+_SHA256="' "$file" | tr -d ' ="')
done
if [ "$sha_pins" -eq 0 ]; then
  fail "found no *_SHA256 pins at all, so this script's pattern no longer matches the step scripts"
fi

echo "== Version-pinned release URLs"
versioned=0
while IFS= read -r url; do
  versioned=$((versioned + 1))
  check_url "$url" "pinned release"
done < <(active_lines | grep -Eo "https://[^\"' )]+" | grep -E '/v[0-9]+\.[0-9]+(\.[0-9]+)?/' | sort -u)
if [ "$versioned" -eq 0 ]; then
  fail "found no version-pinned URLs at all, so this script's pattern no longer matches the step scripts"
fi

echo "== Bootstrap scripts and keys fetched from vendors"
while IFS= read -r url; do
  check_url "$url" "vendor download"
done < <(active_lines | grep -Eo "https://[^\"' )]+" \
          | grep -E '(raw\.githubusercontent\.com/Homebrew/|bootstrap\.pypa\.io/|cli\.github\.com/packages/)' | sort -u)

echo "== npm packages"
npm_pkgs="$(
  {
    active_lines | grep -Eo 'pin_npm [@a-zA-Z0-9/_.-]+' | awk '{print $2}'
    active_lines | grep -Eo 'npm install -g [@a-zA-Z0-9/_.-]+' | awk '{print $4}'
  } | grep -v '^-' | sed -E 's/(.)@[^/]*$/\1/' | grep -v '^\$' | sort -u
)"
for pkg in $npm_pkgs; do
  version="$(curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 "https://registry.npmjs.org/$pkg/latest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)"
  if [ -n "$version" ]; then
    pass "npm $pkg resolves ($version)"
  else
    fail "npm $pkg does not resolve"
  fi
done

echo "== PyPI packages"
pypi_pkgs="$(active_lines | grep 'pipx install ' | sed -E 's/.*pipx install //; s/[;>|].*//' | tr ' ' '\n' | grep -E '^[a-z0-9][a-z0-9_-]+$' | sort -u)"
for pkg in $pypi_pkgs; do
  meta="$(curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 "https://pypi.org/pypi/$pkg/json" 2>/dev/null)"
  version="$(printf '%s' "$meta" | jq -r '.info.version // empty' 2>/dev/null)"
  if [ -n "$version" ]; then
    pass "PyPI $pkg resolves ($version)"
  else
    fail "PyPI $pkg does not resolve"
  fi
  # Step 3 only looks for Python 3.11, 3.12 and 3.13 to install hyperresearch with.
  if [ "$pkg" = hyperresearch ] && [ -n "$version" ]; then
    requires="$(printf '%s' "$meta" | jq -r '.info.requires_python // empty')"
    lower="$(printf '%s' "$requires" | grep -Eo '>=[[:space:]]*3\.[0-9]+' | grep -Eo '[0-9]+$')"
    upper="$(printf '%s' "$requires" | grep -Eo '<[[:space:]]*3\.[0-9]+' | grep -Eo '[0-9]+$')"
    if { [ -n "$lower" ] && [ "$lower" -gt 13 ]; } || { [ -n "$upper" ] && [ "$upper" -le 11 ]; }; then
      fail "PyPI hyperresearch now requires Python '$requires', which step-3's 3.11-3.13 search can't satisfy"
    elif [ "$lower" != 11 ] || [ "$upper" != 14 ]; then
      warn "PyPI hyperresearch requires Python '$requires'. Step 3 pins to 3.11-3.13 because crawl4ai broke on 3.14, so check whether that pin can move"
    else
      pass "PyPI hyperresearch still fits step-3's Python range ($requires)"
    fi
  fi
done

echo "== Git repositories and the submodule pin"
while IFS= read -r url; do
  if git ls-remote --exit-code "$url" HEAD >/dev/null 2>&1; then
    pass "git repo resolves ($url)"
  else
    fail "git repo does not resolve: $url"
  fi
done < <(active_lines | grep -Eo 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git' | sort -u)

if submodule_sha="$(git -C "$here/.." ls-tree HEAD terminal-academy 2>/dev/null | awk '{print $3}')" && [ -n "$submodule_sha" ]; then
  url="https://github.com/fidgetcoding/terminal-academy/commit/$submodule_sha"
  status="$(curl -sS -o /dev/null -L --retry 3 --retry-all-errors --max-time 30 -w '%{http_code}' "$url" 2>/dev/null)"
  if [ "$status" = 200 ]; then
    pass "terminal-academy submodule commit exists ($submodule_sha)"
  else
    fail "terminal-academy submodule commit $submodule_sha returned HTTP ${status:-no response}"
  fi
fi

echo "== Hosted MCP endpoints (warnings only: they answer without auth in different ways)"
while IFS= read -r url; do
  rc=0
  status="$(curl -sS -o /dev/null --connect-timeout 10 --max-time 20 -w '%{http_code}' "$url" 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$status" ] || [ "$status" = 000 ]; then
    warn "hosted MCP endpoint didn't answer (curl exit $rc): $url"
  else
    pass "hosted MCP endpoint answers, HTTP $status ($url)"
  fi
done < <(active_lines | grep -E 'claude mcp add|^[[:space:]]*[a-z]+ https://' | grep -Eo 'https://[A-Za-z0-9./_-]+' | sort -u)

echo ""
echo "$fails failed, $warns warning(s)"
[ "$fails" -eq 0 ]
