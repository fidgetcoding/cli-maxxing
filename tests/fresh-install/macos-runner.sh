#!/usr/bin/env bash
# Runs as the GitHub runner user on a throwaway macOS VM. A hosted runner comes
# loaded with tools, so this strips the ones the installer is meant to provide,
# creates a brand new account, and hands over to run-as-fresh-user.sh.
#
# Xcode Command Line Tools stay: installing them needs a click in a GUI dialog,
# which is the one part of a fresh Mac that cannot run on a headless VM.
#
# Usage: macos-runner.sh <shell path> <full|no-sudo>
#
#   full     New admin account.
#   no-sudo  New standard account: not an admin, nothing in sudoers.
set -eu

login_shell="${1:?usage: macos-runner.sh <shell path> <scenario>}"
scenario="${2:-full}"
checkout="$(cd "$(dirname "$0")/../.." && pwd)"
user="maxtest"

echo "== Removing runner-provided tools"
if [ -d /opt/homebrew ]; then sudo rm -rf /opt/homebrew; fi
for t in brew node npm npx claude jq rg pandoc tree fzf wget gh pipx; do
  sudo rm -f "/usr/local/bin/$t"
done
sudo rm -rf /usr/local/Homebrew /usr/local/Cellar /usr/local/Caskroom /usr/local/lib/node_modules

password="$(openssl rand -hex 16)"
case "$scenario" in
  full)
    echo "== Creating a new admin account"
    sudo sysadminctl -addUser "$user" -password "$password" -admin -shell "$login_shell" -home "/Users/$user" >/dev/null 2>&1
    echo "$user ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/$user" >/dev/null
    sudo chmod 440 "/etc/sudoers.d/$user"
    ;;
  no-sudo)
    echo "== Creating a new standard account"
    sudo sysadminctl -addUser "$user" -password "$password" -shell "$login_shell" -home "/Users/$user" >/dev/null 2>&1
    if id -Gn "$user" | tr ' ' '\n' | grep -qx admin; then
      echo "the test account came out as an admin, so this wouldn't test anything" >&2
      exit 2
    fi
    ;;
  *)
    echo "unknown scenario: $scenario" >&2
    exit 2
    ;;
esac
sudo createhomedir -c -u "$user" >/dev/null 2>&1 || true

# The checkout lives under the runner's home, which a new account cannot read.
copy="$(mktemp -d /tmp/cm-checkout.XXXXXX)"
cp -R "$checkout/." "$copy/"
sudo chown -R "$user" "$copy"

echo "== Confirming the tools are gone from a clean environment"
for t in brew node npm claude; do
  if sudo -u "$user" -H env -i HOME="/Users/$user" PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin bash -c "command -v $t" >/dev/null; then
    echo "$t is still on the runner, so this would not be a fresh install" >&2
    exit 2
  fi
done

sudo -u "$user" -H env -i HOME="/Users/$user" USER="$user" LOGNAME="$user" TERM=dumb PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  CM_TEST_SHELL="$login_shell" CM_TEST_CHECKOUT="$copy" \
  bash "$copy/tests/fresh-install/run-as-fresh-user.sh" mac "$scenario"
