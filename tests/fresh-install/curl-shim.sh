#!/usr/bin/env bash
# curl shim for the fresh-install tests.
#
# install.sh and the steps fetch each other from raw.githubusercontent.com on
# main, so without this a test would exercise whatever main already holds rather
# than the commit under test. Requests for this repo on main get served from the
# checkout named by CLI_MAXXING_TEST_CHECKOUT. Everything else, Homebrew, nvm and
# every vendor URL included, goes to the real curl over the real network.
set -u

prefix="https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/"
real_curl="/usr/bin/curl"

url="" out=""
prev=""
for arg in "$@"; do
  case "$arg" in "$prefix"*) url="$arg" ;; esac
  if [ "$prev" = "-o" ] || [ "$prev" = "--output" ]; then out="$arg"; fi
  prev="$arg"
done

if [ -z "$url" ]; then
  exec "$real_curl" "$@"
fi

file="$CLI_MAXXING_TEST_CHECKOUT/${url#"$prefix"}"
if [ ! -f "$file" ]; then
  echo "curl-shim: $url is not in the checkout" >&2
  exit 22
fi
if [ -n "$out" ]; then
  cp "$file" "$out"
else
  cat "$file"
fi
