#!/usr/bin/env bash
# Runs as root inside a stock distro image. Adds only what the README's one-liner
# assumes, creates a normal user, and hands over to run-as-fresh-user.sh.
#
# Usage: linux-container.sh <full|no-sudo|no-sudo-no-git>
#
#   full            New user with sudo, on a machine with curl and sudo added.
#   no-sudo         New user with no sudo rights, on a machine that already has
#                   curl, git and libatomic, as a real desktop would.
#   no-sudo-no-git  Same, with no git, so the installer has to stop up front.
set -eu

scenario="${1:-full}"
checkout="/repo"
user="maxtest"

if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates sudo procps >/dev/null
  [ "$scenario" = no-sudo ] && apt-get install -y -qq git libatomic1 >/dev/null
elif command -v dnf >/dev/null; then
  dnf install -y -q curl ca-certificates sudo procps-ng findutils util-linux >/dev/null
  [ "$scenario" = no-sudo ] && dnf install -y -q git libatomic >/dev/null
else
  echo "no supported package manager in this image" >&2
  exit 2
fi

useradd -m -s /bin/bash "$user"

case "$scenario" in
  full)
    echo "$user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$user"
    chmod 440 "/etc/sudoers.d/$user"
    mode=full
    ;;
  no-sudo)
    mode=no-sudo
    ;;
  no-sudo-no-git)
    mode=expect-stop
    ;;
  *)
    echo "unknown scenario: $scenario" >&2
    exit 2
    ;;
esac

su - "$user" -c "CM_TEST_SHELL=/bin/bash CM_TEST_CHECKOUT=$checkout CM_TEST_STOP_REASON='git isn'\''t installed' bash $checkout/tests/fresh-install/run-as-fresh-user.sh linux $mode"
