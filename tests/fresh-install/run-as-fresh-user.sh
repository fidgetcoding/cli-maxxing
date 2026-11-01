#!/usr/bin/env bash
# Runs as the test account. Installs from the checkout with a bare environment
# and the same one-liner the README gives people, then checks the result.
#
# Usage: run-as-fresh-user.sh <mac|linux> <full|no-sudo|expect-stop>
#
#   full         Admin account. Everything installs, and a second run is clean.
#   no-sudo      No admin rights. Claude Code still installs in the home folder,
#                and the output says what got skipped and why.
#   expect-stop  No admin rights and a missing prerequisite. Stops up front with
#                a clear message, having written nothing.
set -u

os="$1"
mode="$2"
here="$(cd "$(dirname "$0")" && pwd)"

# People run the one-liner from their home folder. Step 4 writes project config
# to the current directory, so the runner's checkout would not stand in for that.
cd "$HOME" || exit 2

shim_dir="$HOME/.cli-maxxing-test-shim"
mkdir -p "$shim_dir"
cp "$here/curl-shim.sh" "$shim_dir/curl"
chmod +x "$shim_dir/curl"

run_installer() {
  env -i \
    HOME="$HOME" USER="$(id -un)" LOGNAME="$(id -un)" TERM=dumb SHELL="$CM_TEST_SHELL" \
    PATH="$shim_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
    CLI_MAXXING_TEST_CHECKOUT="$CM_TEST_CHECKOUT" \
    bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/fidgetcoding/cli-maxxing/main/install.sh)'
}

rc_snapshot() { cat "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.bash_profile" "$HOME/.profile" 2>/dev/null | cksum; }

expect_in_output() {
  if grep -qF -- "$2" "$1"; then
    echo "PASS  output says: $2"
  else
    echo "FAIL  output should say: $2"
    return 1
  fi
}

case "$mode" in
  full)
    echo "===== First run ====="
    run_installer
    echo "installer exit code: $?"
    echo "===== Checks after first run ====="
    bash "$here/assert-install.sh" "$os"
    first=$?

    before="$(rc_snapshot)"

    echo "===== Second run (idempotency) ====="
    run_installer
    echo "installer exit code: $?"
    echo "===== Checks after second run ====="
    bash "$here/assert-install.sh" "$os"
    second=$?

    after="$(rc_snapshot)"
    if [ "$before" = "$after" ]; then
      echo "PASS  second run left shell startup files unchanged"
      idem=0
    else
      echo "FAIL  second run changed shell startup files"
      idem=1
    fi
    [ "$first" -eq 0 ] && [ "$second" -eq 0 ] && [ "$idem" -eq 0 ]
    ;;

  no-sudo)
    log="$(mktemp)"
    echo "===== Install without admin rights ====="
    run_installer 2>&1 | tee "$log"
    rc="${PIPESTATUS[0]}"
    echo "installer exit code: $rc"
    echo "===== Checks ====="
    status=0
    [ "$rc" -eq 0 ] || { echo "FAIL  installer should exit 0 here"; status=1; }
    expect_in_output "$log" "This account can't use sudo, so this is a partial install" || status=1
    expect_in_output "$log" "Partial install: this account can't use sudo" || status=1
    expect_in_output "$log" "Step 3 (developer tools)" || status=1
    if grep -q "a terminal is required\|a password is required\|is not in the sudoers" "$log"; then
      echo "FAIL  installer ran sudo anyway"
      status=1
    else
      echo "PASS  installer never ran sudo"
    fi
    bash "$here/assert-install.sh" "$os" partial || status=1
    exit "$status"
    ;;

  expect-stop)
    log="$(mktemp)"
    before="$(rc_snapshot)"
    echo "===== Install that must stop up front ====="
    run_installer 2>&1 | tee "$log"
    rc="${PIPESTATUS[0]}"
    echo "installer exit code: $rc"
    echo "===== Checks ====="
    status=0
    [ "$rc" -ne 0 ] || { echo "FAIL  installer should exit non-zero"; status=1; }
    expect_in_output "$log" "This install can't finish on this machine yet" || status=1
    expect_in_output "$log" "Nothing has been installed or changed." || status=1
    expect_in_output "$log" "$CM_TEST_STOP_REASON" || status=1
    for leftover in .nvm .cli-maxxing .claude .local/bin/ctg; do
      if [ -e "$HOME/$leftover" ]; then
        echo "FAIL  stopped, but left $leftover behind"
        status=1
      else
        echo "PASS  nothing written: $leftover"
      fi
    done
    if [ "$before" = "$(rc_snapshot)" ]; then
      echo "PASS  shell startup files untouched"
    else
      echo "FAIL  shell startup files changed"
      status=1
    fi
    exit "$status"
    ;;

  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
