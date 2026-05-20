#!/usr/bin/env bash
#
# 10-nvidia.sh - Install the latest NVIDIA drivers tuned for an RTX 3060 (Ampere)
#                on Arch / BlackArch Linux, with 32-bit support for gaming.
#
# Driver branch selection (RTX 3060 = Ampere, supports both):
#   NVIDIA_VARIANT=proprietary  -> nvidia-dkms      (default, broadest compatibility)
#   NVIDIA_VARIANT=open         -> nvidia-open-dkms (NVIDIA's recommended modules for Turing+)
#
# DKMS variants are used so the modules rebuild against ANY installed kernel
# (BlackArch frequently ships/uses more than just the stock `linux` kernel).
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

NVIDIA_VARIANT="${NVIDIA_VARIANT:-proprietary}"

main() {
    require_arch

    log "Detecting NVIDIA hardware..."
    if command -v lspci >/dev/null 2>&1; then
        local gpu
        gpu="$(lspci -nn | grep -Ei 'vga|3d|display' | grep -i nvidia || true)"
        if [[ -n "$gpu" ]]; then
            success "Found: ${gpu}"
            grep -qi '3060' <<<"$gpu" && success "RTX 3060 detected - this script is tuned for it."
        else
            warn "No NVIDIA GPU reported by lspci. Continuing anyway (run inside a chroot?)."
        fi
    else
        warn "'lspci' not available (pciutils). Skipping hardware detection."
    fi

    enable_multilib
    pac_sync
    install_packages
    configure_modules
    install_pacman_hook
    rebuild_initramfs

    success "NVIDIA driver installation complete."
    cat <<'EOF'

  Next steps:
    * REBOOT for the kernel modules and modesetting to take effect.
    * Verify after reboot with:  nvidia-smi
    * For Steam, enable "Steam Play" for all titles (Proton) under
      Settings -> Compatibility.

EOF
}

# Enable [multilib] - required for 32-bit (lib32) libraries used by Steam,
# Wine/Proton and many native games.
enable_multilib() {
    if repo_enabled multilib; then
        success "[multilib] already enabled."
        return 0
    fi
    log "Enabling the [multilib] repository in /etc/pacman.conf..."
    # Uncomment the standard two-line commented block:
    #   #[multilib]
    #   #Include = /etc/pacman.d/mirrorlist
    as_root sed -i '/^#\[multilib\]/{N;s/^#\[multilib\]\n#Include/[multilib]\nInclude/}' /etc/pacman.conf
    repo_enabled multilib || die "Failed to enable [multilib]. Edit /etc/pacman.conf manually and retry."
    success "[multilib] enabled."
}

install_packages() {
    # Resolve a -headers package for every installed kernel so DKMS can build.
    local headers=() k
    while read -r k; do
        [[ -n "$k" ]] && headers+=("${k}-headers")
    done < <(pacman -Qq 2>/dev/null | grep -E '^linux(-lts|-zen|-hardened|-rt|-rt-lts)?$' || true)
    [[ ${#headers[@]} -eq 0 ]] && headers=(linux-headers)

    local driver
    case "$NVIDIA_VARIANT" in
        open)        driver="nvidia-open-dkms"; log "Using OPEN kernel modules (nvidia-open-dkms)." ;;
        proprietary) driver="nvidia-dkms";      log "Using PROPRIETARY kernel modules (nvidia-dkms)." ;;
        *) die "Unknown NVIDIA_VARIANT='$NVIDIA_VARIANT' (use 'proprietary' or 'open')." ;;
    esac

    # dkms pulls in the build toolchain dependency; install it explicitly too.
    pac_install dkms "${headers[@]}"

    pac_install \
        "$driver" \
        nvidia-utils \
        lib32-nvidia-utils \
        nvidia-settings \
        opencl-nvidia \
        lib32-opencl-nvidia \
        libva-nvidia-driver \
        egl-wayland \
        vulkan-icd-loader \
        lib32-vulkan-icd-loader
}

# Enable DRM kernel mode setting + early module loading. We use modprobe.d
# (bootloader-agnostic) instead of editing GRUB/systemd-boot, plus mkinitcpio
# early loading so the modules are present before the display server starts.
configure_modules() {
    log "Configuring DRM kernel mode setting (modprobe.d)..."
    as_root install -d -m 0755 /etc/modprobe.d
    as_root tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
# Managed by BlackArch-Gaming-Installer (10-nvidia.sh)
# Enable DRM kernel mode setting (required for Wayland & smooth ttys / sleep).
options nvidia_drm modeset=1 fbdev=1
EOF

    log "Adding NVIDIA modules to mkinitcpio for early loading..."
    local mkconf=/etc/mkinitcpio.conf
    if [[ -f "$mkconf" ]]; then
        as_root cp -a "$mkconf" "${mkconf}.bak.$(date +%s)"
        # Replace the first MODULES=(...) line, preserving any existing entries.
        as_root python3 - "$mkconf" <<'PY'
import re, sys
path = sys.argv[1]
need = ["nvidia", "nvidia_modeset", "nvidia_uvm", "nvidia_drm"]
with open(path) as f:
    text = f.read()
m = re.search(r'(?m)^MODULES=\((.*?)\)', text)
if m:
    mods = m.group(1).split()
    for n in need:
        if n not in mods:
            mods.append(n)
    text = text[:m.start()] + "MODULES=(%s)" % " ".join(mods) + text[m.end():]
else:
    text += "\nMODULES=(%s)\n" % " ".join(need)
with open(path, "w") as f:
    f.write(text)
PY
        success "mkinitcpio MODULES updated (backup saved)."
    else
        warn "$mkconf not found; skipping early-load configuration."
    fi
}

# Rebuild the initramfs whenever the NVIDIA package changes, so the in-initramfs
# modules never drift out of sync with the installed driver.
install_pacman_hook() {
    log "Installing pacman hook to rebuild the initramfs on NVIDIA updates..."
    as_root install -d -m 0755 /etc/pacman.d/hooks
    as_root tee /etc/pacman.d/hooks/nvidia.hook >/dev/null <<'EOF'
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia
Target=nvidia-dkms
Target=nvidia-open
Target=nvidia-open-dkms
Target=nvidia-lts
Target=linux
Target=linux-lts
Target=linux-zen
Target=linux-hardened

[Action]
Description=Updating NVIDIA module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case $trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOF
}

rebuild_initramfs() {
    log "Rebuilding the initramfs (mkinitcpio -P)..."
    as_root mkinitcpio -P
}

main "$@"
