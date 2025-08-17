#!/bin/bash
set -euo pipefail

# Miscellaneous - Modify as you wish.
HOSTNAME="computer"
TIMEZONE="America/Sao_Paulo"
CPU_VENDOR=$(cat /proc/cpuinfo | grep 'vendor' | uniq | tr '[:upper:]' '[:lower:]' | awk 'NF>1{print $NF}' | sed 's/\genuine\|authentic//g')
KERNEL="linux-hardened"
BASE_DEVEL_WITHOUT_SUDO=$(LANG=en_US pacman -Sii base-devel | grep ^Depends | cut -d ':' -f2 | sed 's/sudo//g')
SERVICES_TO_ENABLE="apparmor iptables iwd dnscrypt-proxy ntpd-rs systemd-homed mydenyusb da-lockout-clear-tpm"
KERNEL_BOOT_PARAMS="apparmor=1 security=apparmor lsm=landlock,lockdown,yama,integrity,apparmor,bpf slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 oops=panic ${CPU_VENDOR}_iommu=on iommu=force iommu.strict=1 iommu.passthrough=0 vsyscall=none pti=on spectre_v2=on mds=full,nosmt efi=disable_early_pci_dma spec_store_bypass_disable=on tsx=off tsx_async_abort=full,nosmt l1tf=full,force nosmt=force kvm.nx_huge_pages=force randomize_kstack_offset=on debugfs=off ipv6.disable=1 extra_latent_entropy modprobe.blacklist=thunderbolt "

PKGS_TO_IGNORE="--ignore sudo" # Keep this variable empty if you have no packages to ignore.

# Core.
PACSTRAP_PACKAGES="base ${BASE_DEVEL_WITHOUT_SUDO} ${KERNEL} ${KERNEL}-headers ${CPU_VENDOR}-ucode man-db iwd bcachefs-tools btrfs-progs ntpd-rs sbsigntools opendoas apparmor dracut binutils elfutils tpm2-tools sbctl linux-firmware"

if [[ ! -f "/tmp/arch_install_sh_devmode" ]]; then
  # Development tools.
  PACSTRAP_PACKAGES+=" jq yq npm clang go rust python-pip python-requests python-beautifulsoup4 python-html5lib helix code patchutils nano cargo diffoscope rclone "
  
  # General system utils.
  PACSTRAP_PACKAGES+=" wireguard-tools flatpak eza android-tools pacman-contrib zip net-tools gptfdisk openssh pamixer uutils-coreutils fastfetch git unzip unrar pipewire-jack power-profiles-daemon python-gobject sof-firmware wireplumber pipewire-pulse pavucontrol"
  
  # Browsers, multimedia applications and fonts.
  PACSTRAP_PACKAGES+=" chromium ttf-opensans ttf-fantasque-sans-mono  zathura zathura-pdf-poppler alacritty "
  
  # Cloud, infrastructure and virtualization.
  PACSTRAP_PACKAGES+=" kubectl age sops fluxcd skaffold helm kustomize docker-buildx istio docker docker-compose opentofu pulumi minikube azure-cli aws-cli helm k9s "
  
  # Security tools.
  PACSTRAP_PACKAGES+=" checksec wireshark-qt bubblewrap-suid peda valgrind gef radare2 arti openbsd-netcat sqlmap rustscan nmap arch-repro-status"
  
  # User interface and GUI.
  # PACSTRAP_PACKAGES+=" cosmic-session cosmic-files  cosmic-wallpapers vulkan-mesa-layers vulkan-validation-layers vulkan-icd-loader vulkan-headers vulkan-tools flameshot grim "
  PACSTRAP_PACKAGES+=" plasma-desktop flameshot qt6-multimedia-ffmpeg grim xdg-desktop-portal libnotify xdg-desktop-portal-kde systemsettings xdg-desktop-portal-kde kpipewire plasma-pa kscreen plasma-workspace-wallpapers dolphin vulkan-validation-layers vulkan-icd-loader vulkan-headers vulkan-tools"
  # PACSTRAP_PACKAGES+=" sway flameshot qt6-multimedia-ffmpeg grim xdg-desktop-portal xdg-desktop-portal-wlr kanshi waybar otf-font-awesome mako swayidle swaylock brightnessctl xdg-desktop-portal-wlr slurp vulkan-validation-layers vulkan-icd-loader vulkan-headers vulkan-tools"
fi

# Intel GPU -- Remove or adapt this block if you have NVIDIA or AMD! -- TODO: Detect automatically.
PACSTRAP_PACKAGES+=" intel-media-driver onevpl-intel-gpu libva-intel-driver libvdpau-va-gl libva-utils vulkan-intel "
KERNEL_BOOT_PARAMS+=" lockdown=confidentiality module.sig_enforce=1  " # As we don't need DKMS modules, we can set lockdown=confidentiality and module.sig_enforce=1, hardening the kernel further.
echo "add_drivers+=\" i915 \"" >> files/rootfs/etc/dracut.conf.d/50-cnf.conf

# TODO: Make it conditional in order to add these energy-saving and Intel GPU stuff only if the device is known to welcome these parameters.
KERNEL_BOOT_PARAMS+=" i915.modeset=1 i915.enable_dpcd_backlight=3 i915.enable_guc=3 i915.force_probe=!5694 xe.force_probe=!5694 pcie_aspm.policy=powersupersave acpi.ec_no_wakeup=1 "

# Disk details
LUKS_FORMAT_ARGS="-v --hash sha512 --use-urandom"
LUKS_CONTAINER_LABEL="tudo"
ROOT_PART_NAME="linux"
BOOT_PART_NAME="EFISYSTEM"

# Hardened mount flags for pseudofilesystems like proc and tmp.
declare -A MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS
MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[proc]="-o nosuid,nodev,noexec,hidepid=2,gid=proc -t proc proc"
MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[tmp]="-o rw,relatime,nodev,nosuid,size=4G -t tmpfs tmpfs"
MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[var/tmp]="-o rw,relatime,nodev,nosuid,noexec,size=4G -t tmpfs tmpfs"

# Apply the kernel boot params to the actual file.
echo "kernel_cmdline=\"${KERNEL_BOOT_PARAMS}\"" >> files/rootfs/etc/dracut.conf.d/50-cnf.conf
