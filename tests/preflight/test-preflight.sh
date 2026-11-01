#!/usr/bin/env bash
# Unit tests for scripts/preflight.sh. Every outside command it calls is a stub in
# a sandbox bin directory, so this runs nothing real, asks for no password and
# touches nothing. It covers what a CI runner can't be: a Mac under MDM or Santa,
# an old macOS, a proxy that intercepts TLS, a box with no sudo binary at all.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
preflight="$here/../../scripts/preflight.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0
passes=0

# Builds a sandbox bin from KEY=VALUE settings. Tools not stubbed here don't exist,
# which is how "no sudo binary" and "no git" get simulated.
make_sandbox() {
  local bin="$work/bin"
  rm -rf "$bin"; mkdir -p "$bin"
  local t real
  for t in grep cut sed tr cat; do
    real="$(PATH=/usr/bin:/bin command -v "$t")"
    ln -s "$real" "$bin/$t"
  done

  : "${OS_NAME:=Linux}" "${UID_VALUE:=1000}" "${GROUPS_VALUE:=maxtest}"
  : "${SUDO_N_RC:=1}" "${HAVE_SUDO:=1}" "${HAVE_GIT:=1}" "${CURL_RC:=0}"
  : "${MAC_VERSION:=15.1}" "${CLT_RC:=0}" "${SANTA_MODE:=}" "${MDM:=No}"

  printf '#!/bin/bash\necho %s\n' "$OS_NAME" > "$bin/uname"
  cat > "$bin/id" <<STUB
#!/bin/bash
case "\$1" in -u) echo $UID_VALUE ;; -Gn) echo "$GROUPS_VALUE" ;; esac
STUB
  if [ "$HAVE_SUDO" = 1 ]; then
    cat > "$bin/sudo" <<STUB
#!/bin/bash
echo "\$*" >> "$work/sudo.log"
case "\$1" in -n) exit $SUDO_N_RC ;; esac
exit 1
STUB
  fi
  [ "$HAVE_GIT" = 1 ] && printf '#!/bin/bash\nexit 0\n' > "$bin/git"
  if [ "${LIBATOMIC:-}" = 1 ]; then
    printf '#!/bin/bash\necho "\tlibatomic.so.1 (libc6,x86-64) => /lib/libatomic.so.1"\n' > "$bin/ldconfig"
  elif [ "${LIBATOMIC:-}" = 0 ]; then
    printf '#!/bin/bash\necho "\tlibc.so.6 (libc6,x86-64) => /lib/libc.so.6"\n' > "$bin/ldconfig"
  fi
  cat > "$bin/curl" <<STUB
#!/bin/bash
echo "\$*" >> "$work/curl.log"
exit $CURL_RC
STUB
  printf '#!/bin/bash\necho %s\n' "$MAC_VERSION" > "$bin/sw_vers"
  printf '#!/bin/bash\nexit %s\n' "$CLT_RC" > "$bin/xcode-select"
  printf '#!/bin/bash\necho "Enrolled via DEP: No"\necho "MDM enrollment: %s"\n' "$MDM" > "$bin/profiles"
  if [ -n "$SANTA_MODE" ]; then
    printf '#!/bin/bash\necho "  Mode                      | %s"\n' "$SANTA_MODE" > "$bin/santactl"
  fi
  chmod +x "$bin"/*
}

# Runs preflight in the sandbox. Sets RC, OUT and NO_SUDO_RESULT.
run_preflight() {
  : > "$work/sudo.log"; : > "$work/curl.log"
  make_sandbox
  OUT="$(env -i PATH="$work/bin" HOME="$work" CLI_MAXXING_IGNORE_POLICY="${IGNORE_POLICY:-0}" /bin/bash -c '
    . "$1"
    cm_preflight
    rc=$?
    echo "RESULT rc=$rc no_sudo=$CLI_MAXXING_NO_SUDO done=$CLI_MAXXING_PREFLIGHT_DONE"
  ' _ "$preflight" </dev/null 2>&1)"
}

check() {
  local name="$1" want="$2"
  if printf '%s' "$OUT" | /usr/bin/grep -qF -- "$want"; then
    passes=$((passes + 1))
    echo "PASS  $name"
  else
    fails=$((fails + 1))
    echo "FAIL  $name: wanted '$want' in:"
    printf '%s\n' "$OUT" | /usr/bin/sed 's/^/        /'
  fi
}

check_absent() {
  local name="$1" unwanted="$2"
  if printf '%s' "$OUT" | /usr/bin/grep -qF -- "$unwanted"; then
    fails=$((fails + 1))
    echo "FAIL  $name: did not want '$unwanted' in:"
    printf '%s\n' "$OUT" | /usr/bin/sed 's/^/        /'
  else
    passes=$((passes + 1))
    echo "PASS  $name"
  fi
}

scenario() { unset LIBATOMIC OS_NAME UID_VALUE GROUPS_VALUE SUDO_N_RC HAVE_SUDO HAVE_GIT CURL_RC MAC_VERSION CLT_RC SANTA_MODE MDM IGNORE_POLICY; }

scenario; SUDO_N_RC=0; run_preflight
check "linux, working sudo -n: goes ahead" "RESULT rc=0 no_sudo=0"
check_absent "linux, working sudo -n: no partial banner" "partial install"
check "preflight marks itself done for later steps" "done=1"

scenario; GROUPS_VALUE="maxtest sudo"; run_preflight
check "linux, sudo group with a password: goes ahead with sudo" "RESULT rc=0 no_sudo=0"

scenario; GROUPS_VALUE="maxtest wheel"; run_preflight
check "fedora, wheel group: goes ahead with sudo" "RESULT rc=0 no_sudo=0"

scenario; run_preflight
check "linux, no rights, git present: home-folder install" "RESULT rc=0 no_sudo=1"
check "linux, no rights: says it's a partial install" "partial install"
check "linux, no rights: names what gets skipped" "Homebrew, Ghostty, Arc"
if /usr/bin/grep -q -- '-v' "$work/sudo.log"; then
  fails=$((fails + 1)); echo "FAIL  no terminal: must not try a password prompt"
else
  passes=$((passes + 1)); echo "PASS  no terminal: never tries a password prompt"
fi

scenario; HAVE_SUDO=0; run_preflight
check "linux, no sudo binary at all: home-folder install" "RESULT rc=0 no_sudo=1"

scenario; HAVE_GIT=0; run_preflight
check "linux, no rights and no git: stops" "RESULT rc=1"
check "linux, no rights and no git: says what to ask for" "sudo apt-get install -y git"
check "stops are explicit that nothing changed" "Nothing has been installed or changed."

scenario; LIBATOMIC=0; run_preflight
check "linux, no rights and no libatomic: stops" "RESULT rc=1"
check "linux, no rights and no libatomic: says what to ask for" "libatomic1"

scenario; LIBATOMIC=1; run_preflight
check "linux, no rights, libatomic present: home-folder install" "RESULT rc=0 no_sudo=1"

scenario; SUDO_N_RC=0; LIBATOMIC=0; run_preflight
check "linux with sudo, no libatomic: goes ahead, Step 1 installs it" "RESULT rc=0 no_sudo=0"

scenario; UID_VALUE=0; run_preflight
check "root: stops" "RESULT rc=1"
check "root: says why" "Don't run this as root"

scenario; SUDO_N_RC=0; CURL_RC=6; run_preflight
check "network down: stops" "RESULT rc=1"
check "network down: names the hosts" "Can't reach: raw.githubusercontent.com github.com registry.npmjs.org nodejs.org"

scenario; SUDO_N_RC=0; CURL_RC=60; run_preflight
check "TLS interception: stops" "RESULT rc=1"
check "TLS interception: says it's a proxy" "intercepting secure connections"

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff admin"; run_preflight
check "mac admin: goes ahead with sudo" "RESULT rc=0 no_sudo=0"
if /usr/bin/grep -q 'formulae.brew.sh' "$work/curl.log" && /usr/bin/grep -q 'ghcr.io' "$work/curl.log"; then
  passes=$((passes + 1)); echo "PASS  mac: checks Homebrew's hosts too"
else
  fails=$((fails + 1)); echo "FAIL  mac: should check Homebrew's hosts"
fi

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff"; run_preflight
check "mac standard account with CLT: home-folder install" "RESULT rc=0 no_sudo=1"

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff"; CLT_RC=2; run_preflight
check "mac standard account, no CLT: stops" "RESULT rc=1"
check "mac standard account, no CLT: names the fix" "xcode-select --install"

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff admin"; MAC_VERSION="12.7.6"; run_preflight
check "old macOS: stops" "RESULT rc=1"
check "old macOS: says what it needs" "macOS 13 or newer"

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff admin"; SANTA_MODE=Lockdown; run_preflight
check "santa lockdown: stops" "RESULT rc=1"
check "santa lockdown: says what's blocking" "Santa in Lockdown mode"

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff admin"; SANTA_MODE=Monitor; run_preflight
check "santa monitor mode: goes ahead" "RESULT rc=0"
check_absent "santa monitor mode: not reported as lockdown" "Lockdown mode"

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff admin"; SANTA_MODE=Lockdown; IGNORE_POLICY=1; run_preflight
check "santa lockdown with the override: goes ahead" "RESULT rc=0"
check "santa lockdown with the override: still warns" "Going ahead because CLI_MAXXING_IGNORE_POLICY=1"

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff admin"; MDM=Yes; run_preflight
check "managed Mac: goes ahead" "RESULT rc=0"
check "managed Mac: warns where to look" "Your organization manages this Mac"

scenario; OS_NAME=Darwin; GROUPS_VALUE="staff admin"; MDM=No; run_preflight
check_absent "unmanaged Mac: no MDM warning" "Your organization manages this Mac"

echo ""
echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
