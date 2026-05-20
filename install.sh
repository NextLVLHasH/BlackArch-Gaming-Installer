#!/usr/bin/env bash
#
# BlackArch Gaming Installer
# --------------------------
# Installs the latest NVIDIA drivers tuned for an RTX 3060 and replaces the
# desktop UX with Garuda Linux's "Dr460nized" KDE Plasma experience.
#
# Target: Arch / BlackArch Linux (pacman based).
#
# Usage:
#   ./install.sh [--nvidia] [--desktop] [--all] [--yes] [--open]
#
#   --nvidia    Install NVIDIA RTX 3060 drivers only.
#   --desktop   Install the Garuda Dr460nized desktop only.
#   --all       Do both (default if no step flag is given).
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nvidia)  DO_NVIDIA=1 ;;
        --desktop) DO_DESKTOP=1 ;;
        --all)     DO_NVIDIA=1; DO_DESKTOP=1 ;;
        --yes|-y)  export ASSUME_YES=1 ;;
        --open)    export NVIDIA_VARIANT=open ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# Default to running everything when no step was selected.
if [[ $DO_NVIDIA -eq 0 && $DO_DESKTOP -eq 0 ]]; then
    DO_NVIDIA=1; DO_DESKTOP=1
fi

require_arch

printf '%s\n' "${C_BOLD}=== BlackArch Gaming Installer ===${C_RESET}"
log "NVIDIA driver step:  $([[ $DO_NVIDIA  -eq 1 ]] && echo enabled || echo skipped)"
log "Garuda desktop step: $([[ $DO_DESKTOP -eq 1 ]] && echo enabled || echo skipped)"

if [[ $DO_NVIDIA -eq 1 ]]; then
    printf '\n%s\n' "${C_BOLD}--- Step 1/2: NVIDIA RTX 3060 drivers ---${C_RESET}"
    bash "${SCRIPT_DIR}/scripts/10-nvidia.sh"
fi

if [[ $DO_DESKTOP -eq 1 ]]; then
    printf '\n%s\n' "${C_BOLD}--- Step 2/2: Garuda Dr460nized desktop ---${C_RESET}"
    bash "${SCRIPT_DIR}/scripts/20-garuda-dr460nized.sh"
fi

printf '\n'
success "All selected steps finished. Reboot to apply the drivers and new desktop."
