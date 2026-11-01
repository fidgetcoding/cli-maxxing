#!/usr/bin/env bash
# Checks a finished install from the outside, the way a new terminal window sees
# it. install.sh keeps going past a soft failure and its own self-test runs with
# a PATH it bootstrapped itself, so neither one counts as proof here. Every check
# below starts a clean login shell, or reads the files the install left behind.
#
# Usage: assert-install.sh <mac|linux> [partial]
#   partial  No-admin install: only what fits in the home folder is expected.
set -u

os="${1:?usage: assert-install.sh <mac|linux> [partial]}"
scope="${2:-all}"
user_shell="$(if [ "$os" = mac ]; then dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}'; else getent passwd "$(id -un)" | cut -d: -f7; fi)"
fails=0

ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }

# What a new terminal window runs: the account's own shell, interactive + login,
# with nothing inherited but HOME, USER and TERM.
in_new_terminal() {
  env -i HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" TERM=dumb "$user_shell" -ilc "$1" 2>/dev/null </dev/null
}

resolves() {
  if in_new_terminal "command -v $1" | tail -1 | grep -q .; then
    ok "$1 resolves in a new terminal"
  else
    bad "$1 does not resolve in a new terminal"
  fi
}

echo "== Checking as $(id -un), login shell $user_shell, scope $scope"

for tool in claude node npm git; do
  resolves "$tool"
done

version="$(in_new_terminal 'claude --version' | tail -1)"
case "$version" in
  [0-9]*) ok "claude --version runs in a new terminal ($version)" ;;
  *)      bad "claude --version failed in a new terminal (got: '$version')" ;;
esac

# A non-login interactive shell is what GNOME Terminal opens on Linux.
if [ "$os" = linux ]; then
  if env -i HOME="$HOME" USER="$(id -un)" TERM=dumb "$user_shell" -ic 'command -v claude' 2>/dev/null </dev/null | tail -1 | grep -q .; then
    ok "claude resolves in a non-login interactive shell"
  else
    bad "claude does not resolve in a non-login interactive shell"
  fi
fi

for name in cc ccr ccc cskip; do
  if in_new_terminal "alias $name" | grep -q "$name="; then
    ok "alias $name loads in a new terminal"
  else
    bad "alias $name does not load in a new terminal"
  fi
done

crumbs="step-1 step-8 step-final"
skills="safetycheck"

if [ "$scope" = partial ]; then
  # Step 4 runs without sudo only where jq already exists. macOS 15 ships it.
  if in_new_terminal 'command -v jq' | tail -1 | grep -q .; then
    crumbs="$crumbs step-4"
    skills="$skills concise fswarm"
    resolves fidgetflo
  fi
  for crumb in step-3 ghostty arc; do
    if [ -f "$HOME/.cli-maxxing/$crumb.done" ]; then
      bad "breadcrumb $crumb.done should not exist on a partial install"
    else
      ok "$crumb correctly skipped"
    fi
  done
  if [ "$os" = mac ] && in_new_terminal 'command -v brew' | tail -1 | grep -q .; then
    bad "brew should not be installed by a standard account"
  fi
else
  crumbs="$crumbs step-3 step-4"
  skills="$skills concise fswarm"
  [ "$os" = mac ] && crumbs="$crumbs ghostty arc"

  for tool in jq rg pandoc tree fzf wget fidgetflo; do
    resolves "$tool"
  done

  # hyperresearch needs Python 3.11-3.13. The installer gets that itself on macOS
  # and on Linux skips with a message when the distro's Python is older.
  if [ "$os" = linux ] && ! in_new_terminal 'command -v python3.11 || command -v python3.12 || command -v python3.13' | tail -1 | grep -q .; then
    echo "SKIP  hyperresearch (this distro has no Python 3.11-3.13)"
  else
    resolves hyperresearch
  fi

  if [ -f "$HOME/.claude/settings.json" ] && in_new_terminal "jq -e . '$HOME/.claude/settings.json'" >/dev/null; then
    ok "settings.json is valid JSON"
  else
    bad "settings.json missing or invalid"
  fi
fi

for crumb in $crumbs; do
  if [ -f "$HOME/.cli-maxxing/$crumb.done" ]; then
    ok "breadcrumb $crumb.done"
  else
    bad "breadcrumb $crumb.done missing"
  fi
done

for skill in $skills; do
  if [ -s "$HOME/.claude/skills/$skill/SKILL.md" ]; then
    ok "skill $skill installed"
  else
    bad "skill $skill missing"
  fi
done

echo ""
if [ "$fails" -eq 0 ]; then
  echo "All install checks passed."
else
  echo "$fails install check(s) failed."
fi
exit "$fails"
