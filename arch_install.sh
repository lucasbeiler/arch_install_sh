#!/bin/bash
# Arch Linux automated installation
# As of now, IT IS INTENDED FOR UEFI + WIFI + INTEL CPU + NVIDIA GPU + NO-MULTILIB PLATFORMS.
set -e
# Below, before the script itself, you can see a list of values that you SHOULD set accordingly, based on your device and preferences.
pacman -Sy efitools sbsigntools patch archlinux-keyring sbctl jq

# Miscellaneous - Modify as you wish.
HOSTNAME="computer"
USERNAMES=('noone' 'lucas')
MEUSHELL="/bin/bash"
LANGUAGE="pt_BR.UTF-8"
LOCALES=("pt_BR.UTF-8 UTF-8" "pt_BR ISO-8859-1")
TIMEZONE="America/Sao_Paulo"
CPU_VENDOR=$(cat /proc/cpuinfo | grep 'vendor' | uniq | tr '[:upper:]' '[:lower:]' | awk 'NF>1{print $NF}' | sed 's/\genuine\|authentic//g')
KERNEL="linux-hardened"
PACSTRAP_PACKAGES="base base-devel neovim ${KERNEL} ${KERNEL}-headers ${CPU_VENDOR}-ucode jq man-db btrfs-progs dracut binutils elfutils tpm2-tools sbctl linux-firmware wireguard-tools iwd zip dnscrypt-proxy openssh alacritty uutils-coreutils exa apparmor neofetch git unzip unrar ttf-opensans gptfdisk pipewire-pulse pavucontrol alsa-utils bubblewrap-suid irssi arti openbsd-netcat sqlmap nmap code chromium ttf-fantasque-sans-mono net-tools pamixer patchutils nodejs npm nano opendoas ttf-ubuntu-font-family capitaine-cursors sbsigntools efitools ansible vagrant docker docker-compose terraform minikube zathura kanshi vulkan-headers vulkan-tools vulkan-validation-layers seatd go kubectl pipewire-jack wireplumber checksec grim slurp wl-clipboard telegram-desktop qemu-base dnsmasq libvirt bridge-utils brightnessctl usbctl usbguard gxmessage torbrowser-launcher"
IGNORED_PKGS="sudo" # Sudo is ignored since I use doas, which is safer and smaller.
KERNEL_BOOT_PARAMS="apparmor=1 security=apparmor lsm=lockdown,yama,apparmor slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 mce=0 oops=panic ${CPU_VENDOR}_iommu=on iommu=force iommu.strict=1 iommu.passthrough=0 vsyscall=none pti=on spectre_v2=on mds=full,nosmt efi=disable_early_pci_dma spec_store_bypass_disable=on tsx=off tsx_async_abort=full,nosmt l1tf=full,force nosmt=force kvm.nx_huge_pages=force randomize_kstack_offset=on debugfs=off ipv6.disable=1 libata.force=3.00:disable,3.00:norst extra_latent_entropy"
KERNEL_SYSCTL_PARAMS=('kernel.yama.ptrace_scope = 3' 'dev.tty.ldisc_autoload = 0' 'fs.protected_fifos = 2' 'fs.protected_regular = 2' 'kernel.sysrq = 0' 'net.ipv4.tcp_sack = 0' 'net.ipv4.tcp_dsack=0' 'net.ipv4.tcp_fack=0' 'fs.suid_dumpable=0' 'net.ipv4.tcp_rfc1337=1' 'kernel.kexec_load_disabled=1' 'user.max_user_namespaces=0' 'vm.unprivileged_userfaultfd=0' 'net.ipv4.conf.all.rp_filter=1' 'net.ipv4.conf.default.rp_filter=1' 'net.ipv4.conf.all.accept_redirects=0' 'net.ipv4.conf.default.accept_redirects=0' 'net.ipv4.conf.all.secure_redirects=0' 'net.ipv4.conf.default.secure_redirects=0' 'net.ipv6.conf.all.accept_redirects=0' 'net.ipv6.conf.default.accept_redirects=0' 'net.ipv4.conf.all.send_redirects=0' 'net.ipv4.conf.default.send_redirects=0' 'net.ipv4.icmp_echo_ignore_all=1' 'net.ipv4.conf.all.accept_source_route=0' 'net.ipv4.conf.default.accept_source_route=0' 'net.ipv6.conf.all.accept_source_route=0' 'net.ipv6.conf.default.accept_source_route=0' 'net.ipv6.conf.all.accept_ra=0' 'net.ipv6.conf.default.accept_ra=0')
MODPROBE_BLACKLIST=('bluetooth' 'btusb' 'dccp' 'sctp' 'rds' 'tipc' 'n-hdlc' 'ax25' 'netrom' 'x25' 'rose' 'decnet' 'econet' 'af_802154' 'ipx' 'appletalk' 'psnap' 'p8023' 'p8022' 'can' 'atm' 'cramfs' 'freevxfs' 'jffs2' 'hfs' 'hfsplus' 'squashfs' 'udf' 'cifs' 'nfs' 'nfsv3' 'nfsv4' 'gfs2' 'vivid' 'mei' 'mei-me' 'mei_me' 'mei_hdcp' 'mei_pxp'  'ath_pci' 'thunderbolt' 'firewire-core' 'firewire_core' 'firewire-ohci' 'firewire_ohci' 'firewire_sbp2' 'firewire-sbp2' 'ohci1394' 'sbp2' 'dv1394' 'raw1394' 'video1394' 'msr' 'evbug' 'eepro100' 'cdrom' 'sr_mod')

# TODO: Improve and expand GPU/CPU/disk detection and specific actions. Currently, all these detections are very basic.
if lspci | grep -i "3d\|vga" | grep -qi "nvidia\|geforce"; then
    KERNEL_BOOT_PARAMS+=" nvidia-drm.modeset=1 "
    PACSTRAP_PACKAGES+=" nvidia-dkms "
elif lspci | grep -i vga | grep -qi "HD Graphics"; then
    PACSTRAP_PACKAGES+=" intel-media-driver vulkan-intel "
    KERNEL_BOOT_PARAMS+=" lockdown=confidentiality module.sig_enforce=1 " # Since Intel cards doesn't rely on DKMS modules, we can set lockdown=confidentiality and module.sig_enforce=1.
fi

# It will automatically detect the biggest SSD avaible.
TARGET_DISK_BLK="/dev/$(lsblk -x SIZE -d -o name,rota,type --json | jq -r '.blockdevices[] | select(( .rota == false) and .type == "disk").name' | tac | head -n1)"
lsblk
read -p "I've detected ${TARGET_DISK_BLK}, is it right? (Y/correct blk): " -r
if [[ $REPLY =~ ^[\/] ]]; then
    TARGET_DISK_BLK=$REPLY
    until [ -b $TARGET_DISK_BLK ]; do read -p "Incorrect ${TARGET_DISK_BLK} block device. Enter blk now, exactly: " -r TARGET_DISK_BLK; done;
fi
echo "OK. I'll use $TARGET_DISK_BLK."

# Disk details
LUKS_FORMAT_ARGS="-v --hash sha512 --use-urandom"
LUKS_CONTAINER_LABEL="tudo"
ROOT_PART_NAME="linux"
BOOT_PART_NAME="EFISYSTEM"
SUBVOLS=('var' 'home')

declare -A MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS
MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[proc]="-o nosuid,nodev,noexec,hidepid=2,gid=proc -t proc proc"
MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[tmp]="-o rw,relatime,nodev,nosuid,noexec,size=4G -t tmpfs tmpfs"
MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[var/tmp]="-o rw,relatime,nodev,nosuid,noexec,size=4G -t tmpfs tmpfs"

# Script

# Ensure everything is umounted before starting.
umount -R /mnt/
swapoff --all
[[ -b /dev/mapper/${LUKS_CONTAINER_LABEL} ]] && cryptsetup close ${LUKS_CONTAINER_LABEL}

# Prepare the target drive
sgdisk --clear --zap-all ${TARGET_DISK_BLK}
sgdisk -n1:0:+550M -t1:ef00 -c1:${BOOT_PART_NAME} -N2 -t2:8304 -c2:${ROOT_PART_NAME} ${TARGET_DISK_BLK}
echo -e "\n\n[+] Set and confirm the LUKS password (it'll be temporary as we will remove the password and use a TPM2-enrolled-key afterwards)!"
until cryptsetup ${LUKS_FORMAT_ARGS} luksFormat /dev/disk/by-partlabel/${ROOT_PART_NAME}; do echo -en '\nTry again!\n'; done;
echo -e "\n\n[+] Enter the LUKS password below, we'll open the disk now!"
until cryptsetup open /dev/disk/by-partlabel/${ROOT_PART_NAME} ${LUKS_CONTAINER_LABEL}; do echo -en '\nTry again!\n'; done

# Format the filesystems.
mkfs.fat -F32 -n ${BOOT_PART_NAME} /dev/disk/by-partlabel/${BOOT_PART_NAME}
mkfs.btrfs -f -L ${ROOT_PART_NAME} /dev/mapper/${LUKS_CONTAINER_LABEL} 

# Mount and create BTRFS subvols
mount /dev/mapper/${LUKS_CONTAINER_LABEL} /mnt
mkdir /mnt/efi
mount /dev/disk/by-partlabel/${BOOT_PART_NAME} /mnt/efi
for subvol in "${SUBVOLS[@]}"; do 
    btrfs subvolume create "/mnt/$subvol";
done
# TODO: Further subvolume creation and mounting.

# Mount pseudo filesystems.
for key in "${!MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[@]}"; do
    mkdir -pv /mnt/${key}
    mount ${MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[$key]} /mnt/${key}
done

# Stateful Firewall
# It will DROP every INPUT packet, except the ones belonging to some already established connection.
# Only OUTPUT can be used to establish new connections.
# Loopback connections are allowed.
systemctl start iptables

for chain in INPUT FORWARD OUTPUT; do
    iptables -P ${chain} DROP
done

iptables -A INPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED,NEW -j ACCEPT

iptables -A INPUT  -i lo -s 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -o lo -d 127.0.0.1 -j ACCEPT

iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
# iptables -A INPUT -p udp -m conntrack --ctstate NEW -j UDP
# iptables -A INPUT -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j TCP
iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A INPUT -j REJECT --reject-with icmp-proto-unreachable

# Mirrorlist
until ping -c2 www.kernel.org; do echo 'Error pinging kernel.org. Are we connected to the Internet?'; done;
sed -i '/http:\|rsync:\/\//d' /etc/pacman.d/mirrorlist # Remove non-https mirrors. I will not run reflector since archiso already does it.

# System install
pacman -Syy
pacstrap -i /mnt ${PACSTRAP_PACKAGES} --ignore ${IGNORED_PKGS}

# Set computer's hostname
echo ${HOSTNAME} > /mnt/etc/hostname

# pacman's aesthetics
sed -i 's/#Color/Color/' /mnt/etc/pacman.conf
sed -i 's/#TotalDownload/TotalDownload/' /mnt/etc/pacman.conf

# Apply some network setup with iwd and iptables.
iptables-save | tee /mnt/etc/iptables/ip{tables.rules,6tables.rules}
mkdir /mnt/{etc,var/lib}/iwd
echo -en "[General]\nEnableNetworkConfiguration=true" > /mnt/etc/iwd/main.conf # Use iwd's built-in DHCP client.
cp -r /var/lib/iwd/*.psk /mnt/var/lib/iwd/ # Copy all the PSK-based networks to the new system.

# Select the desired locales
for LCL in "${LOCALES[@]}"; do
    sed -i "s/#$LCL/$LCL/" /mnt/etc/locale.gen
done

# Generate and set locales.
arch-chroot /mnt locale-gen
echo LANG=${LANGUAGE} > /mnt/etc/locale.conf
export LANG=${LANGUAGE}

# Set timezone.
arch-chroot /mnt ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
#timedatectl set-ntp true
arch-chroot /mnt hwclock --systohc

# Replace sudo with OpenBSD's doas (safer, smaller).
echo 'permit persist :wheel' > /mnt/etc/doas.conf
arch-chroot /mnt ln -s /usr/bin/doas /usr/bin/sudo

# Lid settings to ignore switch (laptop will remain up and running when the lid is closed down).
echo -en "[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore" | tee /mnt/etc/systemd/logind.conf

# Forced blacklist of undesired modules.
for modulo in "${MODPROBE_BLACKLIST[@]}"
do
    echo "install ${modulo} /bin/true" >> /mnt/etc/modprobe.d/blacklist.conf
done

# Sysctl parameters for increased security
for item in "${KERNEL_SYSCTL_PARAMS[@]}"
do
    echo "$item" >> /mnt/etc/sysctl.d/params.conf
done

# Apply dnscrypt-proxy settings and enable apparmor, iptables, iwd, dnscrypt-proxy.socket, systemd-homed, usbguard and fstrim.
patch /mnt/etc/dnscrypt-proxy/dnscrypt-proxy.toml patch_dnscryptproxy_toml.patch
arch-chroot /mnt systemctl enable apparmor iptables iwd dnscrypt-proxy.socket systemd-homed usbguard fstrim
#arch-chroot /mnt timedatectl set-ntp true
echo -en "nameserver 127.0.0.1\noptions edns0 single-request-reopen" > /mnt/etc/resolv.conf
chattr +i /mnt/etc/resolv.conf

# Generate Secure Boot keys and certs and configure dracut.
arch-chroot /mnt sbctl create-keys
echo -en 'uefi_secureboot_cert="/usr/share/secureboot/keys/db/db.pem"\nuefi_secureboot_key="/usr/share/secureboot/keys/db/db.key"' | tee /mnt/etc/dracut.conf.d/50-secure-boot.conf
echo -en 'add_dracutmodules+=" tpm2-tss "' | tee /mnt/etc/dracut.conf.d/50-tpm2.conf
echo -en 'use_fstab="yes"\nadd_fstab+=" /etc/fstab "' | tee /mnt/etc/dracut.conf.d/50-fstab.conf
echo -en "reproducible=\"yes\"\nuefi=\"yes\"\nearly_microcode=\"yes\"\nkernel_cmdline=\"${KERNEL_BOOT_PARAMS}\"\nhostonly=\"yes\"\nhostonly_cmdline=\"no\"" | tee /mnt/etc/dracut.conf.d/50-host-only.conf

# Install initramfs and bootloader and sign everything. 
# TODO: Add pacman hooks to run the commands below when things get updated (also, maybe sbctl already set its own hooks, but dracut doesn't).
genfstab -U -P /mnt >> /mnt/etc/fstab
arch-chroot /mnt sbctl sign -s /usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot /mnt dracut -f --uefi --regenerate-all
arch-chroot /mnt bootctl install
# efibootmgr --create --disk ${TARGET_DISK_BLK} --part 1 --label "Meu Arch Linux" --loader /EFI/Linux/$(basename /mnt/efi/EFI/Linux/*.efi)
until arch-chroot /mnt passwd; do echo 'Try again!'; done;

# Close things up.
cp firstboot.sh /mnt/usr/local/bin/firstboot
chmod +x /mnt/usr/local/bin/firstboot
cp -r ~/arch_install_sh*/ /mnt/etc/arch_install_sh
echo -e "\n\n[+] Bye! Run firstboot as soon as you get inside the installed system."
umount -R /mnt
[[ -b /dev/mapper/${LUKS_CONTAINER_LABEL} ]] && cryptsetup close ${LUKS_CONTAINER_LABEL}
reboot
