# BlackArch Gaming Installer

Automated setup scripts for **BlackArch / Arch Linux** that:

1. Install the **latest NVIDIA drivers** tuned for an **RTX 3060** (Ampere), with
   32-bit (multilib) support for Steam / Proton / Wine.
2. Replace the desktop UX with **Garuda Linux "Dr460nized"** KDE Plasma — including
   the **BeautyLine icons** and the floating **Dr460nized taskbar**.
3. Replace **Firefox** with **Microsoft Edge** (set as the default browser).
4. Install developer / creator apps: **VS Code, Node.js, Discord, OBS Studio**, and
   **LM Studio** with all the runtime libraries it needs.

> **Heads-up:** this layers Garuda's third-party desktop and binary repository
> (Chaotic-AUR) on top of BlackArch. Review the scripts and keep a recovery path
> (a TTY or live USB) handy before running.

## Usage

```bash
git clone <this-repo>
cd BlackArch-Gaming-Installer
chmod +x install.sh scripts/*.sh

./install.sh --all          # everything (drivers + desktop + Edge + apps)
./install.sh --nvidia       # drivers only
./install.sh --desktop      # desktop only
./install.sh --browser      # replace Firefox with Edge only
./install.sh --apps         # VS Code / Node.js / Discord / OBS / LM Studio only
./install.sh --all --yes    # unattended (assume "yes")
./install.sh --nvidia --open  # use NVIDIA open kernel modules (nvidia-open-dkms)
```

Run as your normal user; the scripts call `sudo` where root is needed. Running the
whole thing through `sudo` also works — set `TARGET_USER=<name>` so the desktop
theming lands on the right account.

Reboot when finished.

## What each script does

| Script | Purpose |
| --- | --- |
| `install.sh` | Orchestrator + CLI flags. |
| `scripts/00-common.sh` | Shared helpers (logging, root, pacman wrappers). |
| `scripts/10-nvidia.sh` | Enables `[multilib]`, installs `nvidia-dkms` (or `nvidia-open-dkms`) + `nvidia-utils` + `lib32-nvidia-utils` + Vulkan/VA-API bits, enables DRM modeset, sets up early module loading and an initramfs pacman hook. |
| `scripts/20-garuda-dr460nized.sh` | Enables Chaotic-AUR, installs the Garuda Dr460nized desktop package set, enables SDDM, then **applies the BeautyLine icon theme and the Dr460nized panel/taskbar** for your user. |
| `scripts/30-replace-browser.sh` | Removes Firefox (and the FireDragon fork), installs `microsoft-edge-stable-bin`, and sets Edge as the default browser. |
| `scripts/40-dev-apps.sh` | Installs `visual-studio-code-bin`, `nodejs`+`npm`, `discord`, `obs-studio`, and `lmstudio-bin` plus LM Studio's runtime libraries (`fuse2`, `gtk3`, `nss`, …). |

### Browser / apps notes

- **Edge**, **VS Code (Microsoft build)** and **LM Studio** are not in the official
  Arch repos — they come from Chaotic-AUR (enabled by the desktop step) or an AUR
  helper. Run `--desktop` before `--browser`/`--apps`, or have `yay`/`paru` installed.
- Keep FireDragon with `REMOVE_FIREDRAGON=0`; use the open-source VS Code build
  with `VSCODE_PACKAGE=code`; pull the full CUDA toolkit with `INSTALL_CUDA_TOOLKIT=1`.
- LM Studio uses the NVIDIA driver's CUDA library for GPU offload automatically.

### NVIDIA notes

- DKMS variants are used so modules rebuild against **any** installed kernel
  (BlackArch often runs more than the stock `linux` kernel).
- DRM mode setting (`nvidia_drm modeset=1 fbdev=1`) is enabled via
  `/etc/modprobe.d/nvidia.conf` — bootloader-agnostic, no GRUB edits required.
- Verify after reboot with `nvidia-smi`.

### Garuda Dr460nized notes

- Packages come from the Garuda-maintained Chaotic-AUR repo (the official ISO
  profile package list is used).
- Icons = **BeautyLine**; the taskbar/panel layout is taken from Garuda's
  `/etc/skel` config. Existing Plasma config is backed up before being replaced.
- Pick **Plasma** at the SDDM login screen after rebooting.
