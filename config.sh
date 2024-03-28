#!/bin/bash
set -e

# Miscellaneous - Modify as you wish.
HOSTNAME="computer"
MEUSHELL="/bin/bash"
TIMEZONE="America/Sao_Paulo"
CPU_VENDOR=$(cat /proc/cpuinfo | grep 'vendor' | uniq | tr '[:upper:]' '[:lower:]' | awk 'NF>1{print $NF}' | sed 's/\genuine\|authentic//g')
KERNEL="linux-hardened"
BASE_DEVEL_WITHOUT_SUDO=$(LANG=en_US pacman -Sii base-devel | grep ^Depends | cut -d ':' -f2 | sed 's/sudo//g')
SERVICES_TO_ENABLE="apparmor iptables ip6tables iwd systemd-networkd dnscrypt-proxy.socket systemd-homed libvirtd docker"
KERNEL_BOOT_PARAMS="apparmor=1 security=apparmor lsm=landlock,lockdown,yama,integrity,apparmor,bpf slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 oops=panic ${CPU_VENDOR}_iommu=on iommu=force iommu.strict=1 iommu.passthrough=0 vsyscall=none pti=on spectre_v2=on mds=full,nosmt efi=disable_early_pci_dma spec_store_bypass_disable=on tsx=off tsx_async_abort=full,nosmt l1tf=full,force nosmt=force kvm.nx_huge_pages=force randomize_kstack_offset=on debugfs=off libata.force=3.00:disable,3.00:norst extra_latent_entropy "

PKGS_TO_IGNORE="--ignore sudo" # Keep this variable empty if you have no packages to ignore.

# Core.
PACSTRAP_PACKAGES="base ${BASE_DEVEL_WITHOUT_SUDO} ${KERNEL} ${KERNEL}-headers ${CPU_VENDOR}-ucode man-db btrfs-progs dracut binutils elfutils tpm2-tools sbctl linux-firmware"

# Development tools.
PACSTRAP_PACKAGES+=" neovim jq go python-pip python-requests helix code lapce patchutils nodejs npm nano cargo"

# General system utils.
PACSTRAP_PACKAGES+=" wireguard-tools sbsigntools pacman-contrib usbctl iwd zip net-tools dnscrypt-proxy gptfdisk openssh opendoas alacritty pamixer uutils-coreutils exa apparmor neofetch git unzip unrar pipewire-jack sof-firmware wireplumber pipewire-pulse pavucontrol"

# Browsers, chat applications and fonts.
PACSTRAP_PACKAGES+=" chromium gomuks irssi ttf-ubuntu-font-family ttf-opensans ttf-fantasque-sans-mono"

# Cloud, infrastructure and virtualization.
PACSTRAP_PACKAGES+=" ansible kubectl skaffold helm kustomize docker-buildx istio vagrant qemu-base dnsmasq libvirt bridge-utils docker docker-compose terraform minikube aws-cli-v2 helm k9s "

# Multimedia and document viewers.
PACSTRAP_PACKAGES+=" zathura zathura-pdf-mupdf ncspot"

# Security tools.
PACSTRAP_PACKAGES+=" checksec bubblewrap-suid peda valgrind gef radare2 ropgadget ghidra pwndbg binwalk arti openbsd-netcat sqlmap nmap arch-repro-status tcpdump wireshark-qt"

# User interface and GUI.
PACSTRAP_PACKAGES+=" plasma-desktop flameshot grim xdg-desktop-portal xdg-desktop-portal-kde systemsettings xdg-desktop-portal-kde kpipewire plasma-pa kscreen plasma-workspace-wallpapers dolphin vulkan-validation-layers vulkan-icd-loader vulkan-headers vulkan-tools"


# Intel GPU -- Remove or adapt this block if you have NVIDIA or AMD! -- TODO: Detect automatically.
PACSTRAP_PACKAGES+=" intel-media-driver libva-intel-driver libvdpau-va-gl libva-utils vulkan-intel "
KERNEL_BOOT_PARAMS+=" lockdown=confidentiality module.sig_enforce=1 i915.modeset=1 " # As we don't need DKMS modules, we can set lockdown=confidentiality and module.sig_enforce=1, hardening the kernel further.
echo "add_drivers+=\" i915 \"" >> files/rootfs/etc/dracut.conf.d/50-host-only.conf

# TODO: Make it conditional in order to add only if the device is a Galaxy Book2 Pro with Intel Arc.
KERNEL_BOOT_PARAMS+=" i915.enable_dpcd_backlight=3 i915.force_probe=!5694 pcie_aspm.policy=powersupersave acpi.ec_no_wakeup=1 "

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
echo "kernel_cmdline=\"${KERNEL_BOOT_PARAMS}\"" >> files/rootfs/etc/dracut.conf.d/50-host-only.conf
