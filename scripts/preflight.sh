#!/usr/bin/env bash
# =============================================================================
# CLI Maxxing: Preflight
# Sourced by install.sh and by the steps that need system packages. Works out,
# before anything is downloaded or written, whether this account and this machine
# can finish the install, so nobody hits the wall 15 minutes in.
#
#   cm_preflight        Prints what it found. Returns 0 to go ahead, 1 to stop.
#
# Sets and exports:
#   CLI_MAXXING_NO_SUDO=1        This account can't use sudo. Install only what
#                                fits in the home folder.
#   CLI_MAXXING_PREFLIGHT_DONE=1 Later steps don't need to run this again.
#
# Set CLI_MAXXING_IGNORE_POLICY=1 to go ahead past a security-policy stop.
# =============================================================================

CM_BLOCKERS=()
CM_WARNINGS=()

_cm_red='\033[0;31m'
_cm_yellow='\033[1;33m'
_cm_green='\033[0;32m'
_cm_nc='\033[0m'

# -----------------------------------------------------------------------------
# Can this account use sudo?
# `sudo -n` alone can't answer: on most systems it says "a password is required"
# whether or not the account is allowed in. So: a working sudo -n is a yes, the
# admin groups are a yes, and anyone else only gets asked when there's a terminal
# to ask on, because a custom sudoers entry is the one case left.
# -----------------------------------------------------------------------------
cm_has_sudo() {
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n true >/dev/null 2>&1 && return 0
    case " $(id -Gn 2>/dev/null) " in
        *" admin "*|*" sudo "*|*" wheel "*) return 0 ;;
    esac
    if [ -t 0 ]; then
        echo "  Checking whether this account can use sudo. Enter your password if asked."
        sudo -v 2>/dev/null && return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Are the hosts the install depends on reachable? A corporate proxy or firewall
# usually shows up here, and TLS interception has its own curl exit code.
# -----------------------------------------------------------------------------
cm_check_network() {
    local hosts=(raw.githubusercontent.com github.com registry.npmjs.org nodejs.org)
    [ "$(uname -s)" = "Darwin" ] && hosts+=(formulae.brew.sh ghcr.io)

    local host rc blocked="" intercepted=""
    for host in "${hosts[@]}"; do
        curl -sS -o /dev/null --connect-timeout 8 --max-time 20 "https://$host/" >/dev/null 2>&1
        rc=$?
        case "$rc" in
            0) ;;
            60|35|77) intercepted="$intercepted $host" ;;
            *) blocked="$blocked $host" ;;
        esac
    done

    if [ -n "$intercepted" ]; then
        CM_BLOCKERS+=("Something on this network is intercepting secure connections to:$intercepted. That's usually a corporate proxy. Downloads will fail until IT allows these hosts or you switch networks.")
    fi
    if [ -n "$blocked" ]; then
        CM_BLOCKERS+=("Can't reach:$blocked. Check your internet connection. On a work network, ask IT to allow these hosts.")
    fi
}

# -----------------------------------------------------------------------------
# Things that make a Mac refuse the install partway through.
# -----------------------------------------------------------------------------
cm_check_mac() {
    local major
    major="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
    if [ -n "$major" ] && [ "$major" -lt 13 ] 2>/dev/null; then
        CM_BLOCKERS+=("This Mac is on macOS $(sw_vers -productVersion). Claude Code needs macOS 13 or newer, so update macOS first.")
    fi

    # An allowlisting tool in lockdown mode kills anything it hasn't approved,
    # and Node, Claude Code and every Homebrew tool are all unapproved here.
    if command -v santactl >/dev/null 2>&1 && santactl status 2>/dev/null | grep -Eiq 'mode[^a-z]*lockdown'; then
        if [ "${CLI_MAXXING_IGNORE_POLICY:-0}" = "1" ]; then
            CM_WARNINGS+=("Santa is in Lockdown mode. Going ahead because CLI_MAXXING_IGNORE_POLICY=1 is set.")
        else
            CM_BLOCKERS+=("This Mac runs Santa in Lockdown mode, which blocks programs your company hasn't approved. Node.js and Claude Code would be killed when they start. Ask IT to allow them. If you know they're already allowed, re-run with CLI_MAXXING_IGNORE_POLICY=1.")
        fi
    fi

    # Enrollment alone doesn't block anything, plenty of managed Macs are fine,
    # so this only tells people where to look if a later step gets refused.
    if command -v profiles >/dev/null 2>&1 && profiles status -type enrollment 2>/dev/null | grep -Eiq 'MDM enrollment:[[:space:]]*Yes'; then
        CM_WARNINGS+=("Your organization manages this Mac (MDM). The install usually still works. If a step gets refused, that policy is the likely reason, and IT can allow it.")
    fi

    # brew owned by another account on a shared Mac: every brew install fails.
    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$brew_bin" ]; then
            if [ ! -w "$("$brew_bin" --prefix 2>/dev/null)/bin" ]; then
                CM_WARNINGS+=("Homebrew here belongs to another account, so this account can't install with it. Tools that need Homebrew will be skipped or fail.")
            fi
            break
        fi
    done
}

# -----------------------------------------------------------------------------
# No sudo: is the home-folder install possible at all?
# -----------------------------------------------------------------------------
cm_check_no_sudo_path() {
    if [ "$(uname -s)" = "Darwin" ]; then
        # Without the Command Line Tools, /usr/bin/git is a stub that opens a
        # dialog, and that dialog wants an admin password.
        if ! xcode-select -p >/dev/null 2>&1; then
            CM_BLOCKERS+=("This account isn't an admin, and the Xcode Command Line Tools aren't installed. Installing them needs an admin. Ask one to run: xcode-select --install")
        fi
    else
        if ! command -v git >/dev/null 2>&1; then
            CM_BLOCKERS+=("This account can't use sudo, and git isn't installed. Ask an admin to install it, for example: sudo apt-get install -y git")
        fi
        # Node's Linux builds won't start without libatomic. A desktop usually has
        # it, a minimal server or container may not, and with sudo Step 1 adds it.
        local ldconfig_bin=""
        ldconfig_bin="$(command -v ldconfig || { [ -x /sbin/ldconfig ] && echo /sbin/ldconfig; } || true)"
        if [ -n "$ldconfig_bin" ] && ! "$ldconfig_bin" -p 2>/dev/null | grep -q 'libatomic\.so\.1'; then
            CM_BLOCKERS+=("This account can't use sudo, and Node.js needs a system library that's missing. Ask an admin to install it, for example: sudo apt-get install -y libatomic1 (on Fedora: sudo dnf install -y libatomic)")
        fi
    fi
}

cm_preflight() {
    CM_BLOCKERS=()
    CM_WARNINGS=()
    export CLI_MAXXING_PREFLIGHT_DONE=1
    export CLI_MAXXING_NO_SUDO=0

    if [ "$(id -u)" -eq 0 ]; then
        CM_BLOCKERS+=("Don't run this as root or with sudo. Run it as your normal account.")
    elif ! cm_has_sudo; then
        export CLI_MAXXING_NO_SUDO=1
        cm_check_no_sudo_path
    fi

    [ "$(uname -s)" = "Darwin" ] && cm_check_mac
    cm_check_network

    local item
    if [ "${#CM_BLOCKERS[@]}" -gt 0 ]; then
        echo ""
        echo -e "${_cm_red}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_cm_nc}"
        echo -e "${_cm_red}  This install can't finish on this machine yet${_cm_nc}"
        echo -e "${_cm_red}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_cm_nc}"
        echo ""
        echo "  Nothing has been installed or changed."
        echo ""
        for item in "${CM_BLOCKERS[@]}"; do
            echo "  - $item"
            echo ""
        done
        echo "  Fix that, then run the installer again."
        echo ""
        return 1
    fi

    if [ "${#CM_WARNINGS[@]}" -gt 0 ]; then
        echo ""
        for item in "${CM_WARNINGS[@]}"; do
            echo -e "${_cm_yellow}[WARN]${_cm_nc} $item"
        done
    fi

    if [ "$CLI_MAXXING_NO_SUDO" = "1" ]; then
        echo ""
        echo -e "${_cm_yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_cm_nc}"
        echo -e "${_cm_yellow}  This account can't use sudo, so this is a partial install${_cm_nc}"
        echo -e "${_cm_yellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_cm_nc}"
        echo ""
        echo -e "  ${_cm_green}Will install, in your home folder:${_cm_nc} Node.js, Claude Code, your"
        echo "  shortcuts, the safety check skill and the status line."
        echo ""
        echo "  Will skip, because they need an admin: Homebrew, Ghostty, Arc and"
        echo "  the Step 3 system tools. FidgetFlo also needs jq from Step 3."
        echo ""
        echo "  Once an admin has made this account one, or installed those tools,"
        echo "  run the installer again and it picks up the rest."
        echo ""
    fi

    return 0
}
