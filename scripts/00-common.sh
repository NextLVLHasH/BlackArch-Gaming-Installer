#!/usr/bin/env bash
# Shared helpers for the BlackArch Gaming Installer.
# Source this file from the other scripts: `source "$(dirname "$0")/00-common.sh"`

# Colors (disabled when not writing to a terminal)
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'; C_BLUE=$'\033[1;34m'; C_BOLD=$'\033[1m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

log()     { printf '%s[*]%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
success() { printf '%s[+]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn()    { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()     { printf '%s[x]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
die()     { err "$*"; exit 1; }

# Run a command as root, using sudo when not already root.
as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        die "This step needs root privileges and 'sudo' was not found. Re-run as root."
    fi
}

# Ask a yes/no question. Honours ASSUME_YES=1 for unattended runs.
confirm() {
    local prompt="${1:-Continue?}"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        log "$prompt -> auto-yes (ASSUME_YES=1)"
        return 0
    fi
    local reply
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

require_arch() {
    command -v pacman >/dev/null 2>&1 \
        || die "pacman not found. This installer targets Arch / BlackArch Linux only."
}

# Refresh databases + full system upgrade.
pac_sync() {
    log "Synchronising package databases and upgrading the system..."
    as_root pacman -Syu --noconfirm
}

# Install packages. Skips ones already installed (--needed). Non-fatal per-package:
# packages that fail to be found are collected and reported, the rest still install.
pac_install() {
    [[ $# -gt 0 ]] || return 0
    log "Installing: $*"
    if as_root pacman -S --needed --noconfirm "$@"; then
        return 0
    fi
    warn "Batch install reported errors; retrying packages individually to skip unavailable ones."
    local pkg failed=()
    for pkg in "$@"; do
        as_root pacman -S --needed --noconfirm "$pkg" || failed+=("$pkg")
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        warn "These packages could not be installed: ${failed[*]}"
        return 1
    fi
}

# True if a pacman repo section is enabled in /etc/pacman.conf.
repo_enabled() {
    grep -q "^\[$1\]" /etc/pacman.conf
}

# Remove packages if installed. Non-fatal; reports what was actually removed.
pac_remove() {
    local pkg present=()
    for pkg in "$@"; do
        pacman -Qq "$pkg" >/dev/null 2>&1 && present+=("$pkg")
    done
    if [[ ${#present[@]} -eq 0 ]]; then
        log "None of the requested packages are installed: $*"
        return 0
    fi
    log "Removing: ${present[*]}"
    as_root pacman -Rns --noconfirm "${present[@]}"
}

# Resolve the real (non-root) user whose desktop should be configured.
# Sets TARGET_USER and TARGET_HOME. Honours TARGET_USER, then $SUDO_USER,
# then the current user. Returns non-zero if only root is available.
resolve_target_user() {
    TARGET_USER="${TARGET_USER:-${SUDO_USER:-}}"
    if [[ -z "$TARGET_USER" && $EUID -ne 0 ]]; then
        TARGET_USER="$USER"
    fi
    if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
        TARGET_HOME=""
        return 1
    fi
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]]
}

# Run a command as the resolved target desktop user.
as_user() {
    if [[ "${TARGET_USER:-}" == "$USER" ]]; then
        "$@"
    else
        as_root runuser -u "$TARGET_USER" -- "$@"
    fi
}
