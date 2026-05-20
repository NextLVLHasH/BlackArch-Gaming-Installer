#!/usr/bin/env bash
#
# 30-replace-browser.sh - Remove Firefox (and the Garuda FireDragon fork) and
#                         replace it with Microsoft Edge, set as default browser.
#
# Microsoft Edge is not in the official Arch repos; it is published as a prebuilt
# binary in Chaotic-AUR (microsoft-edge-stable-bin), which 20-garuda-dr460nized.sh
# enables. This script requires that repo (or an AUR helper) to be available.
#
# Override the Edge channel with:  EDGE_PACKAGE=microsoft-edge-dev-bin (or -beta-).
# Keep FireDragon with:            REMOVE_FIREDRAGON=0
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

EDGE_PACKAGE="${EDGE_PACKAGE:-microsoft-edge-stable-bin}"
REMOVE_FIREDRAGON="${REMOVE_FIREDRAGON:-1}"

main() {
    require_arch

    if ! repo_enabled chaotic-aur && ! command -v yay >/dev/null 2>&1 \
        && ! command -v paru >/dev/null 2>&1; then
        die "Microsoft Edge ($EDGE_PACKAGE) needs Chaotic-AUR or an AUR helper.
     Run the desktop step first (./install.sh --desktop) to enable Chaotic-AUR."
    fi

    remove_firefox
    install_edge
    set_default_browser

    success "Firefox replaced with Microsoft Edge."
}

remove_firefox() {
    log "Removing Firefox family browsers..."
    pac_remove firefox firefox-esr firefox-developer-edition \
        firefox-i18n-en-us firefox-kde-opensuse
    if [[ "$REMOVE_FIREDRAGON" == "1" ]]; then
        log "Removing Garuda's FireDragon (Firefox fork)..."
        pac_remove firedragon firedragon-extension-plasma-integration
    else
        log "Keeping FireDragon (REMOVE_FIREDRAGON=0)."
    fi
}

install_edge() {
    log "Installing Microsoft Edge ($EDGE_PACKAGE)..."
    if repo_enabled chaotic-aur; then
        pac_install "$EDGE_PACKAGE"
    elif command -v yay >/dev/null 2>&1; then
        as_user yay -S --needed --noconfirm "$EDGE_PACKAGE"
    elif command -v paru >/dev/null 2>&1; then
        as_user paru -S --needed --noconfirm "$EDGE_PACKAGE"
    fi
    pacman -Qq "$EDGE_PACKAGE" >/dev/null 2>&1 \
        && success "Microsoft Edge installed." \
        || die "Microsoft Edge installation failed."
}

# Make Edge the default browser for the real desktop user (and the http/https
# + html MIME handlers), so links open in Edge instead of the removed Firefox.
set_default_browser() {
    if ! resolve_target_user; then
        warn "No real user resolved; skipping default-browser setup."
        warn "After login run:  xdg-settings set default-web-browser microsoft-edge.desktop"
        return 0
    fi
    local desktop=microsoft-edge.desktop
    log "Setting Edge as the default browser for '${TARGET_USER}'..."
    as_user xdg-settings set default-web-browser "$desktop" 2>/dev/null || true
    local m
    for m in x-scheme-handler/http x-scheme-handler/https text/html \
             application/xhtml+xml; do
        as_user xdg-mime default "$desktop" "$m" 2>/dev/null || true
    done
    as_user xdg-settings set default-web-browser "$desktop" >/dev/null 2>&1 \
        && success "Default browser set to Microsoft Edge." \
        || warn "Could not confirm default-browser setting (no session?); set it after login."
}

main "$@"
