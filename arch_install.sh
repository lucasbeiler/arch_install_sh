#!/bin/bash
# Arch Linux automated installation
# As of now, IT IS INTENDED FOR UEFI + WIFI + INTEL CPU + NVIDIA GPU + NO-MULTILIB PLATFORMS.

# Below, before the script itself, you can see a list of values that you SHOULD set accordingly, based on your device and preferences.

# Miscellaneous
HOSTNAME="computer"
USERNAMES=('noone' 'lucas')
MEUSHELL="/bin/bash"
LANGUAGE="pt_BR.UTF-8"
LOCALES=("pt_BR.UTF-8 UTF-8" "pt_BR ISO-8859-1")
TIMEZONE="America/Sao_Paulo"
CPU_VENDOR="intel" # Change it accordingly
GPU_PACKAGES="nvidia-dkms"  # GPU driver - Change it accordingly
CPU_PACKAGES="${CPU_VENDOR}-ucode" # Microcode - Change it accordingly
KERNEL="linux-hardened"
# TODO: Remove some useless packages below.
PACSTRAP_PACKAGES="base base-devel neovim ${KERNEL} ${KERNEL}-headers man-db btrfs-progs dracut binutils elfutils tpm2-tools sbctl linux-firmware ${CPU_PACKAGES} ${GPU_PACKAGES} wireguard-tools iwd zip dnscrypt-proxy openssh alacritty uutils-coreutils exa apparmor neofetch git unzip unrar ttf-opensans terminus-font ttf-font-awesome gptfdisk pipewire-pulse pavucontrol alsa-utils bubblewrap-suid irssi arti openbsd-netcat ttf-liberation sqlmap nmap code chromium ttf-fantasque-sans-mono net-tools ttf-hack pamixer patchutils nodejs npm nano opendoas ttf-ubuntu-font-family capitaine-cursors sbsigntools efitools ansible vagrant docker docker-compose terraform minikube zathura kanshi vulkan-headers vulkan-tools vulkan-validation-layers seatd go kubectl pipewire-jack wireplumber checksec grim slurp wl-clipboard telegram-desktop qemu-base dnsmasq libvirt bridge-utils brightnessctl usbctl gxmessage torbrowser-launcher"
IGNORED_PKGS="sudo" # Sudo is ignored since I use doas, which is safer and smaller.
VENDOR_SPECIFIC_BOOT_PARAMS="nvidia-drm.modeset=1"
KERNEL_BOOT_PARAMS="${BASE_KERNEL_BOOT_PARAMS} apparmor=1 quiet security=apparmor lsm=lockdown,yama,apparmor slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 mce=0 oops=panic iommu=force iommu.strict=1 iommu.passthrough=0 vsyscall=none ${CPU_VENDOR}_iommu=on ${VENDOR_SPECIFIC_BOOT_PARAMS} pti=on spectre_v2=on mds=full,nosmt efi=disable_early_pci_dma spec_store_bypass_disable=on tsx=off tsx_async_abort=full,nosmt l1tf=full,force nosmt=force kvm.nx_huge_pages=force randomize_kstack_offset=on debugfs=off ipv6.disable=1 libata.force=3.00:disable,3.00:norst extra_latent_entropy"
KERNEL_SYSCTL_PARAMS=('kernel.yama.ptrace_scope = 3' 'dev.tty.ldisc_autoload = 0' 'fs.protected_fifos = 2' 'fs.protected_regular = 2' 'kernel.sysrq = 0' 'net.ipv4.tcp_sack = 0' 'net.ipv4.tcp_dsack=0' 'net.ipv4.tcp_fack=0' 'fs.suid_dumpable=0' 'net.ipv4.tcp_rfc1337=1' 'kernel.kexec_load_disabled=1' 'user.max_user_namespaces=0' 'kernel.deny_new_usb=1' 'vm.unprivileged_userfaultfd=0' 'net.ipv4.conf.all.rp_filter=1' 'net.ipv4.conf.default.rp_filter=1' 'net.ipv4.conf.all.accept_redirects=0' 'net.ipv4.conf.default.accept_redirects=0' 'net.ipv4.conf.all.secure_redirects=0' 'net.ipv4.conf.default.secure_redirects=0' 'net.ipv6.conf.all.accept_redirects=0' 'net.ipv6.conf.default.accept_redirects=0' 'net.ipv4.conf.all.send_redirects=0' 'net.ipv4.conf.default.send_redirects=0' 'net.ipv4.icmp_echo_ignore_all=1' 'net.ipv4.conf.all.accept_source_route=0' 'net.ipv4.conf.default.accept_source_route=0' 'net.ipv6.conf.all.accept_source_route=0' 'net.ipv6.conf.default.accept_source_route=0' 'net.ipv6.conf.all.accept_ra=0' 'net.ipv6.conf.default.accept_ra=0')
# TODO: Disable more 'DMA-capable' modules.
MODPROBE_BLACKLIST=('bluetooth' 'btusb' 'dccp' 'sctp' 'rds' 'tipc' 'n-hdlc' 'ax25' 'netrom' 'x25' 'rose' 'decnet' 'econet' 'af_802154' 'ipx' 'appletalk' 'psnap' 'p8023' 'p8022' 'can' 'atm' 'cramfs' 'freevxfs' 'jffs2' 'hfs' 'hfsplus' 'squashfs' 'udf' 'cifs' 'nfs' 'nfsv3' 'nfsv4' 'gfs2' 'vivid')

# Disk details
TARGET_DISK_BLK="/dev/nvme0n1" # Change it accordingly.
LUKS_FORMAT_ARGS="-v --hash sha512 --use-urandom" # TODO: Harden.
LUKS_CONTAINER_LABEL="tudo"
ROOT_PART_NAME="linux"
BOOT_PART_NAME="EFISYSTEM"
SUBVOLS=('var' 'var/log' 'var/cache' 'var/tmp' 'srv' 'home')

# Script
set -e

pacman -Sy efitools sbsigntools patch archlinux-keyring sbctl

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
# TODO: Further subvolume creation and mounting + fstab (remember, it requires use_fstab on dracut).


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
until ping -c2 www.kernel.org; do echo 'Verificando conexão...'; done;
# TODO: Run reflector only if mirrorlist is empty.
sed -i '/http:\/\//d' /etc/pacman.d/mirrorlist # Remove HTTP (non-https) mirrors. I will not run reflector since archiso already does it.

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

# Generate and set locales
arch-chroot /mnt locale-gen
echo LANG=${LANGUAGE} > /mnt/etc/locale.conf
export LANG=${LANGUAGE}

# Set timezone. TODO: Use sdwdate or any other thing more secure than the classic NTP (NTP isn't enabled in the system we gonna install).
arch-chroot /mnt ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
arch-chroot /mnt hwclock --systohc

# Create and set up the users.
for USERNAME in "${USERNAMES[@]}"; do
    arch-chroot /mnt useradd -m -g users -G wheel,libvirt,docker,video,audio -s $MEUSHELL $USERNAME
    echo -e "\n\n[+] Set the password for ${USERNAME}!"
    until arch-chroot /mnt passwd $USERNAME; do echo -en '\nTente novamente!\n'; done;
    arch-chroot /mnt su ${USERNAME} -c "ssh-keygen -t rsa -q -f '/home/${USERNAME}/.ssh/id_rsa' -C '' -N ''"

    # Get my dotfiles
    arch-chroot /mnt su ${USERNAME} -c "git clone https://github.com/lucassbeiler/dotfiles ~/dotfiles"
    arch-chroot /mnt su ${USERNAME} -c "cp -r ~/dotfiles/.{config,*rc} ~/"
    cp -r /mnt/home/${USERNAME}/dotfiles/usr/local/bin/* /mnt/usr/local/bin/
    cp -r /mnt/home/${USERNAME}/dotfiles/etc/* /mnt/etc/
done

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

# Apply dnscrypt-proxy settings and enable apparmor, iptables, iwd and dnscrypt-proxy.socket.
patch /mnt/etc/dnscrypt-proxy/dnscrypt-proxy.toml patch_dnscryptproxy_toml.patch
arch-chroot /mnt systemctl enable apparmor iptables iwd dnscrypt-proxy.socket
echo -en "nameserver 127.0.0.1\noptions edns0 single-request-reopen" > /mnt/etc/resolv.conf
chattr +i /mnt/etc/resolv.conf

# Generate Secure Boot keys and certs and configure dracut.
sbctl create-keys
echo -en 'uefi_secureboot_cert="/usr/share/secureboot/keys/db/db.pem"\nuefi_secureboot_key="/usr/share/secureboot/keys/db/db.key"' | tee /mnt/etc/dracut.conf.d/50-secure-boot.conf
echo -en "uefi=yes\nearly_microcode=yes\nkernel_cmdline=\"${KERNEL_BOOT_PARAMS}\"\nhostonly=\"yes\"\nhostonly_cmdline=\"no\"" | tee /mnt/etc/dracut.conf.d/50-host-only.conf
cp -r /usr/share/secureboot/ /mnt/usr/share/

# Install initramfs and bootloader and sign everything. TODO: Create pacman hooks to run the commands below when things get updated (also, maybe sbctl already set its own hooks, but dracut doesn't).
arch-chroot /mnt dracut -f --uefi --regenerate-all
arch-chroot /mnt bootctl install
arch-chroot /mnt sbctl sign -s /usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot /mnt sbctl sign -s /efi/EFI/BOOT/BOOTX64.EFI
arch-chroot /mnt sbctl sign -s /efi/EFI/systemd/systemd-bootx64.efi

# Close stuff.
cp firstboot.sh /mnt/usr/local/bin/firstboot
chmod +x /mnt/usr/local/bin/firstboot
cp -r ~/arch_install_sh*/ /mnt/etc/arch_install_sh
sbctl enroll-keys
echo -e "\n\n[+] Bye! Run firstboot as soon as you get inside the installed system."
umount -R /mnt
cryptsetup close ${LUKS_CONTAINER_LABEL}
reboot