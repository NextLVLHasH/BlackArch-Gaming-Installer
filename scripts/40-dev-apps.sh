#!/usr/bin/env bash
#
# 40-dev-apps.sh - Install developer / creator apps:
#   * Visual Studio Code (Microsoft build)
#   * Node.js + npm
#   * Discord
#   * OBS Studio
#   * LM Studio + all runtime libraries it needs
#
# VS Code (Microsoft build) and LM Studio are not in the official Arch repos;
# they come from Chaotic-AUR (enabled by 20-garuda-dr460nized.sh) or an AUR
# helper (yay/paru). The rest are in the official repos.
#
# Overrides:
#   VSCODE_PACKAGE=code          # use the open-source Code-OSS build instead
#   INSTALL_CUDA_TOOLKIT=1       # also install the full CUDA toolkit for LM Studio
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

VSCODE_PACKAGE="${VSCODE_PACKAGE:-visual-studio-code-bin}"
LMSTUDIO_PACKAGE="${LMSTUDIO_PACKAGE:-lmstudio-bin}"
INSTALL_CUDA_TOOLKIT="${INSTALL_CUDA_TOOLKIT:-0}"

# Runtime libraries LM Studio (an AppImage/Electron app) needs.
# fuse2 is required to mount the AppImage; the rest are its shared-lib deps.
# GPU offload uses libcuda from the NVIDIA driver (installed by 10-nvidia.sh).
LMSTUDIO_LIBS=(
    fuse2 gtk3 nss zlib libxcrypt-compat hicolor-icon-theme
    alsa-lib libnotify at-spi2-core libxss
)

main() {
    require_arch
    pac_sync

    install_official_apps
    install_nodejs
    install_vscode
    install_lmstudio

    success "Developer / creator apps installed."
    cat <<'EOF'

  Installed: VS Code, Node.js + npm, Discord, OBS Studio, LM Studio.
  LM Studio GPU offload uses your NVIDIA driver automatically; pick a CUDA
  runtime inside LM Studio (Settings -> Runtime) on first launch.

EOF
}

# Discord + OBS live in the official repos.
install_official_apps() {
    log "Installing Discord and OBS Studio (official repos)..."
    pac_install discord obs-studio
}

install_nodejs() {
    log "Installing Node.js and npm (official repos)..."
    pac_install nodejs npm
    command -v node >/dev/null 2>&1 && success "Node.js $(node --version) installed."
}

# Install a package preferring Chaotic-AUR via pacman, then an AUR helper.
install_aur_pkg() {
    local pkg="$1"
    if repo_enabled chaotic-aur && pacman -Ssq "^${pkg}$" >/dev/null 2>&1; then
        pac_install "$pkg" && return 0
    fi
    if command -v yay >/dev/null 2>&1; then
        as_user yay -S --needed --noconfirm "$pkg" && return 0
    elif command -v paru >/dev/null 2>&1; then
        as_user paru -S --needed --noconfirm "$pkg" && return 0
    fi
    # Last attempt: maybe it is in a configured repo even without chaotic.
    pac_install "$pkg"
}

install_vscode() {
    log "Installing Visual Studio Code ($VSCODE_PACKAGE)..."
    if [[ "$VSCODE_PACKAGE" == "code" ]]; then
        pac_install code   # open-source Code-OSS, official repo
    elif ! install_aur_pkg "$VSCODE_PACKAGE"; then
        warn "Could not install $VSCODE_PACKAGE; falling back to open-source 'code'."
        pac_install code
    fi
}

install_lmstudio() {
    log "Installing LM Studio runtime libraries..."
    pac_install "${LMSTUDIO_LIBS[@]}"

    if [[ "$INSTALL_CUDA_TOOLKIT" == "1" ]]; then
        log "Installing the full CUDA toolkit (INSTALL_CUDA_TOOLKIT=1)..."
        pac_install cuda cudnn || warn "CUDA toolkit install reported errors."
    fi

    log "Installing LM Studio ($LMSTUDIO_PACKAGE)..."
    if install_aur_pkg "$LMSTUDIO_PACKAGE"; then
        success "LM Studio installed."
    else
        warn "LM Studio ($LMSTUDIO_PACKAGE) could not be installed automatically."
        warn "It needs Chaotic-AUR or an AUR helper (yay/paru). Install one, then:"
        warn "    yay -S $LMSTUDIO_PACKAGE"
        warn "The required libraries above are already installed."
    fi
}

main "$@"
