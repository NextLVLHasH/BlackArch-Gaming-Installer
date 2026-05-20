#!/usr/bin/env bash
#
# BlackArch Gaming Installer
# --------------------------
# Sets up a BlackArch / Arch system end-to-end:
#   1. Latest NVIDIA drivers tuned for an RTX 3060 (+ 32-bit gaming support).
#   2. Garuda Linux "Dr460nized" KDE Plasma desktop (BeautyLine icons + taskbar).
#   3. Replace Firefox with Microsoft Edge (set as default browser).
#   4. Developer / creator apps: VS Code, Node.js, Discord, OBS, LM Studio.
#
# Target: Arch / BlackArch Linux (pacman based).
#
# Usage:
#   ./install.sh [steps...] [--yes] [--open]
#
#   --nvidia    Install NVIDIA RTX 3060 drivers.
#   --desktop   Install the Garuda Dr460nized desktop.
#   --browser   Replace Firefox with Microsoft Edge.
#   --apps      Install VS Code, Node.js, Discord, OBS, LM Studio.
#   --all       Do everything (default when no step flag is given).
#   --yes       Non-interactive: assume "yes" to prompts (ASSUME_YES=1).
#   --open      Use the NVIDIA open kernel modules (nvidia-open-dkms).
#   -h|--help   Show this help.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00-common.sh
source "${SCRIPT_DIR}/scripts/00-common.sh"

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

DO_NVIDIA=0
DO_DESKTOP=0
DO_BROWSER=0
DO_APPS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nvidia)  DO_NVIDIA=1 ;;
        --desktop) DO_DESKTOP=1 ;;
        --browser) DO_BROWSER=1 ;;
        --apps)    DO_APPS=1 ;;
        --all)     DO_NVIDIA=1; DO_DESKTOP=1; DO_BROWSER=1; DO_APPS=1 ;;
        --yes|-y)  export ASSUME_YES=1 ;;
        --open)    export NVIDIA_VARIANT=open ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# Default to running everything when no step was selected.
if [[ $DO_NVIDIA -eq 0 && $DO_DESKTOP -eq 0 && $DO_BROWSER -eq 0 && $DO_APPS -eq 0 ]]; then
    DO_NVIDIA=1; DO_DESKTOP=1; DO_BROWSER=1; DO_APPS=1
fi

require_arch

state() { [[ "$1" -eq 1 ]] && echo enabled || echo skipped; }

printf '%s\n' "${C_BOLD}=== BlackArch Gaming Installer ===${C_RESET}"
log "NVIDIA drivers:   $(state $DO_NVIDIA)"
log "Garuda desktop:   $(state $DO_DESKTOP)"
log "Edge (browser):   $(state $DO_BROWSER)"
log "Developer apps:   $(state $DO_APPS)"

# This modifies the running system IN PLACE: changing the display manager and
# default desktop, replacing the browser, and layering a third-party repo.
warn "This OVERWRITES parts of your existing BlackArch install (desktop, login"
warn "manager, default browser, repos). Make sure you can reach a TTY or live USB."
confirm "Continue overwriting this BlackArch installation?" || die "Aborted by user."

# Refresh keyrings once, up front, so every later install/repo-add succeeds.
refresh_keyrings

# Order matters: the desktop step enables Chaotic-AUR, which the browser and
# apps steps rely on for Microsoft Edge, VS Code and LM Studio.
if [[ $DO_NVIDIA -eq 1 ]]; then
    printf '\n%s\n' "${C_BOLD}--- NVIDIA RTX 3060 drivers ---${C_RESET}"
    bash "${SCRIPT_DIR}/scripts/10-nvidia.sh"
fi

if [[ $DO_DESKTOP -eq 1 ]]; then
    printf '\n%s\n' "${C_BOLD}--- Garuda Dr460nized desktop ---${C_RESET}"
    bash "${SCRIPT_DIR}/scripts/20-garuda-dr460nized.sh"
fi

if [[ $DO_BROWSER -eq 1 ]]; then
    printf '\n%s\n' "${C_BOLD}--- Replace Firefox with Microsoft Edge ---${C_RESET}"
    bash "${SCRIPT_DIR}/scripts/30-replace-browser.sh"
fi

if [[ $DO_APPS -eq 1 ]]; then
    printf '\n%s\n' "${C_BOLD}--- Developer / creator apps ---${C_RESET}"
    bash "${SCRIPT_DIR}/scripts/40-dev-apps.sh"
fi

printf '\n'
success "All selected steps finished. Reboot to apply the drivers and new desktop."
