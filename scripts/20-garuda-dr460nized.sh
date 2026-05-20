#!/usr/bin/env bash
#
# 20-garuda-dr460nized.sh - Replace the desktop UX with Garuda Linux's
#                           "Dr460nized" KDE Plasma experience on BlackArch / Arch.
#
# How it works:
#   * Garuda's Dr460nized packages (garuda-dr460nized, the Sweet theme, beautyline
#     icons, firedragon, the GRUB theme, etc.) are published as prebuilt binaries
#     in the Chaotic-AUR repository. We enable Chaotic-AUR, then install the same
#     package set Garuda ships in its official dr460nized ISO profile.
#   * SDDM is enabled as the display manager and the look-and-feel defaults are
#     applied by the garuda-dr460nized-settings package.
#
# WARNING: This layers a third-party desktop on top of BlackArch. It changes your
#          login manager and default desktop session. Review before running and
#          make sure you have a way to recover (TTY / live USB).
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

# Chaotic-AUR primary signing key.
CHAOTIC_KEY="3056513887B78AEB"
CHAOTIC_KEYSERVER="keyserver.ubuntu.com"
CHAOTIC_CDN="https://cdn-mirror.chaotic.cx/chaotic-aur"

# Garuda Dr460nized desktop package set (from the official iso-profiles
# garuda/dr460nized/Packages-Desktop list). Packages missing from the active
# repos are skipped individually rather than aborting the whole install.
DESKTOP_PACKAGES=(
    # X / Wayland base
    xorg-server xorg-xwayland xorg-xhost xorg-xinit xorg-xinput autorandr
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-kde
    # Garuda theming + identity
    garuda-dr460nized garuda-fish-config beautyline grub-theme-garuda-dr460nized
    kvantum kvantum-qt5 kwin-effect-rounded-corners-git kwin-effects-better-blur-dx
    plasma-applet-window-buttons plasma6-applets-window-title
    plasma6-wallpapers-blurredwallpaper
    # Display manager
    sddm sddm-kcm
    # Plasma desktop + applets
    plasma-desktop kwin kscreen kdeplasma-addons kinfocenter
    plasma-nm plasma-pa plasma-systemmonitor plasma-firewall
    plasma-thunderbolt plasma-browser-integration
    bluedevil kde-gtk-config kwayland-integration kwallet-pam ksshaskpass
    powerdevil power-profiles-daemon
    kf6-servicemenus-rootactions
    # Core KDE apps
    ark discover dolphin dolphin-plugins kate kdeconnect konsole okular
    partitionmanager spectacle
    # Media / thumbnails / codecs
    ffmpeg ffmpegthumbs openh264 libdvdcss kdegraphics-thumbnailers
    kimageformats qt6-imageformats qt6-quick3d resvg mpv mpv-uosc
    # Browser + integrations
    firedragon firedragon-extension-plasma-integration
    appmenu-gtk-module libappindicator-gtk3 libinput-gestures-qt
    # Utilities Garuda relies on
    octopi firewalld sshfs quota-tools ugrep
)

main() {
    require_arch
    [[ $EUID -eq 0 ]] || command -v sudo >/dev/null 2>&1 \
        || die "Run as root or install sudo first."

    cat <<'EOF'

  This will:
    1. Enable the Chaotic-AUR repository (Garuda's binary package source).
    2. Install the Garuda "Dr460nized" KDE Plasma desktop and theming.
    3. Enable the SDDM login manager and set the graphical boot target.

EOF
    confirm "Proceed with installing the Garuda Dr460nized desktop?" \
        || die "Aborted by user."

    setup_chaotic_aur
    pac_sync
    install_desktop
    enable_services
    apply_dr460nized_look

    success "Garuda Dr460nized desktop installed."
    cat <<'EOF'

  Next steps:
    * REBOOT, then pick "Plasma" at the SDDM login screen.
    * The BeautyLine icons and Dr460nized taskbar are applied by the step above
      and by garuda-dr460nized-settings on first login.

EOF
}

# Resolve the real (non-root) user whose desktop should receive the look.
# Honours TARGET_USER, then $SUDO_USER, then the current user.
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

# Run a command as the target desktop user.
as_user() {
    if [[ "$TARGET_USER" == "$USER" ]]; then
        "$@"
    else
        as_root runuser -u "$TARGET_USER" -- "$@"
    fi
}

# Apply the Garuda Dr460nized ICONS (BeautyLine) and TASKBAR (Dr460nized panel
# layout) to the target user. Installing the packages only makes these available;
# this step actually activates them.
apply_dr460nized_look() {
    if ! resolve_target_user; then
        warn "Could not determine a real user to theme (running as root with no SUDO_USER)."
        warn "After first login, run this script's look step as your user, or set TARGET_USER=<name>."
        return 0
    fi
    log "Applying the Dr460nized icons + taskbar for user '${TARGET_USER}'..."

    # --- ICONS: BeautyLine ------------------------------------------------
    # Set globally and for the user. plasma-apply-icontheme needs a session, so
    # we also write kdeglobals directly to cover the next login reliably.
    local kdeglobals="${TARGET_HOME}/.config/kdeglobals"
    as_user mkdir -p "${TARGET_HOME}/.config"
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        as_user kwriteconfig6 --file "$kdeglobals" --group Icons --key Theme BeautyLine
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        as_user kwriteconfig5 --file "$kdeglobals" --group Icons --key Theme BeautyLine
    else
        warn "kwriteconfig not found; icon theme will be set by garuda settings on login."
    fi
    # If a Plasma session is live, apply immediately too.
    command -v plasma-apply-icontheme >/dev/null 2>&1 \
        && as_user plasma-apply-icontheme BeautyLine >/dev/null 2>&1 || true
    success "Icon theme set to BeautyLine."

    # --- TASKBAR: Dr460nized panel layout ---------------------------------
    # Garuda ships its panel/applet layout in /etc/skel/.config. Copy the
    # Plasma layout files into the user's config so the floating Dr460nized
    # panel (with window-title + window-buttons applets and blur) appears.
    local applied=0 f
    for f in plasma-org.kde.plasma.desktop-appletsrc plasmashellrc; do
        if [[ -f "/etc/skel/.config/$f" ]]; then
            if [[ -f "${TARGET_HOME}/.config/$f" ]]; then
                as_user cp -a "${TARGET_HOME}/.config/$f" "${TARGET_HOME}/.config/${f}.bak.$(date +%s)"
            fi
            as_root install -m 0644 -o "$TARGET_USER" -g "$TARGET_USER" \
                "/etc/skel/.config/$f" "${TARGET_HOME}/.config/$f"
            applied=1
        fi
    done
    if [[ $applied -eq 1 ]]; then
        success "Dr460nized taskbar/panel layout applied (existing config backed up)."
    else
        warn "No panel layout found in /etc/skel/.config; the Dr460nized taskbar"
        warn "will be created by garuda-dr460nized-settings on first login instead."
    fi
}

setup_chaotic_aur() {
    if repo_enabled chaotic-aur; then
        success "[chaotic-aur] already configured."
        return 0
    fi

    log "Importing the Chaotic-AUR signing key..."
    as_root pacman-key --recv-key "$CHAOTIC_KEY" --keyserver "$CHAOTIC_KEYSERVER"
    as_root pacman-key --lsign-key "$CHAOTIC_KEY"

    log "Installing chaotic-keyring and chaotic-mirrorlist..."
    as_root pacman -U --noconfirm \
        "${CHAOTIC_CDN}/chaotic-keyring.pkg.tar.zst" \
        "${CHAOTIC_CDN}/chaotic-mirrorlist.pkg.tar.zst"

    log "Adding [chaotic-aur] to /etc/pacman.conf..."
    as_root tee -a /etc/pacman.conf >/dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
    repo_enabled chaotic-aur || die "Failed to enable [chaotic-aur]."
    success "[chaotic-aur] enabled."
}

install_desktop() {
    log "Installing the Garuda Dr460nized desktop package set..."
    # Non-fatal: pac_install retries per-package and reports any that are
    # unavailable, so a single missing package never blocks the whole desktop.
    pac_install "${DESKTOP_PACKAGES[@]}" || \
        warn "Some packages were skipped (see above). The desktop should still be usable."
}

enable_services() {
    log "Enabling SDDM and the graphical boot target..."
    as_root systemctl enable sddm.service
    as_root systemctl set-default graphical.target
    # firewalld ships in the dr460nized profile and is expected to be active.
    if pacman -Qq firewalld >/dev/null 2>&1; then
        as_root systemctl enable firewalld.service || \
            warn "Could not enable firewalld.service."
    fi
    success "SDDM enabled; system will boot to the graphical login."
}

main "$@"
