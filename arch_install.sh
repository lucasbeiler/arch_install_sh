#!/bin/bash
# Arch Linux automated installation, featuring FDE with LUKS + Detached Header + Partitionless setup + general system hardening.
# As of now, IT IS INTENDED FOR UEFI + WIFI + INTEL CPU + NVIDIA GPU + NO-MULTILIB PLATFORMS.

# Below, before the script itself, you can see a list of values that you SHOULD set accordingly, based on your device and preferences.

# Miscellaneous
HOSTNAME="computador"
USERNAME="lucas"
MEUSHELL="/bin/bash"
LANGUAGE="pt_BR.UTF-8"
LOCALES=("pt_BR.UTF-8 UTF-8" "pt_BR ISO-8859-1")
TIMEZONE="America/Sao_Paulo"
LUKS_HEADER_FILENAME="header.img"
MKINITCPIO_FILES="/boot/${LUKS_HEADER_FILENAME}"
MKINITCPIO_MODULES="ext4"
MKINITCPIO_HOOKS="base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt sd-lvm2 filesystems fsck"
HTTPS_NEARBY_MIRRORLIST="https://archlinux.org/mirrorlist/?country=BR&country=CL&protocol=https"
XORG_NEEDS_ROOT_RIGHTS="no"
CPU_VENDOR="intel" # Change it accordingly
GPU_PACKAGES="nvidia-dkms"  # GPU driver - Change it accordingly
CPU_PACKAGES="${CPU_VENDOR}-ucode" # Microcode - Change it accordingly
TBB_DEPENDS="mozilla-common libxt startup-notification mime-types dbus-glib alsa-lib desktop-file-utils hicolor-icon-theme libvpx icu libevent nss hunspell sqlite"
KERNEL="linux-hardened"
PACSTRAP_PACKAGES="base base-devel vim ${KERNEL} ${KERNEL}-headers linux-firmware lvm2 ${CPU_PACKAGES} ${GPU_PACKAGES} iwd zip openssh docker-compose xorg-server xorg-xinit xorg-xrandr xorg-xsetroot feh picom apparmor neofetch git man unzip code flameshot unrar ttf-opensans terminus-font ttf-font-awesome gptfdisk dmenu pipewire-pulse pavucontrol alsa-utils telegram-desktop bubblewrap-suid weechat tor virtualbox openbsd-netcat ttf-liberation sqlmap nano chromium firefox ${TBB_DEPENDS}"
ADDITIONAL_INITRD="initrd /${CPU_VENDOR}-ucode.img"
DISK_BY_ID="$(ls /dev/disk/by-id/nvme-Force_MP510*)" # I should maybe improve this line. # Change it accordingly.
LVM_VG_LABEL="vg0"
LUKS_CONTAINER_LABEL="tudo"
BASE_KERNEL_BOOT_PARAMS="options cryptdevice=${DISK_BY_ID}:${LVM_VG_LABEL} root=/dev/mapper/${LVM_VG_LABEL}-root"
KERNEL_BOOT_PARAMS="${BASE_KERNEL_BOOT_PARAMS} rw apparmor=1 security=apparmor lsm=lockdown,yama,apparmor slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 slub_debug=F mce=0 oops=panic iommu=force ${CPU_VENDOR}_iommu=on pti=on spectre_v2=on mds=full,nosmt efi=disable_early_pci_dma spec_store_bypass_disable=on tsx=off tsx_async_abort=full,nosmt l1tf=full,force nosmt=force kvm.nx_huge_pages=force extra_latent_entropy"
KERNEL_SYSCTL_PARAMS=('kernel.yama.ptrace_scope = 3' 'dev.tty.ldisc_autoload = 0' 'fs.protected_fifos = 2' 'fs.protected_regular = 2' 'kernel.sysrq = 0' 'net.ipv4.tcp_sack = 0' 'net.ipv4.tcp_dsack=0' 'net.ipv4.tcp_fack=0' 'ipv6.disable=1' 'fs.suid_dumpable=0' 'net.ipv4.tcp_rfc1337=1')
MODPROBE_BLACKLIST=('bluetooth' 'btusb' 'uvcvideo' 'dccp' 'sctp' 'rds' 'tipc' 'n-hdlc' 'ax25' 'netrom' 'x25' 'rose' 'decnet' 'econet' 'af_802154' 'ipx' 'appletalk' 'psnap' 'p8023' 'p8022' 'can' 'atm' 'cramfs' 'freevxfs' 'jffs2' 'hfs' 'hfsplus' 'squashfs' 'udf' 'cifs' 'nfs' 'nfsv3' 'nfsv4' 'gfs2' 'vivid')
DNSSERVERS=('1.1.1.1' '1.0.0.1') # Primary and secondary. TODO: Use dnscrypt-proxy instead, since I do it manually in post-installation.

# Disk details
TARGET_DISK_BLK="/dev/nvme0n1" # Change it accordingly.
DETACHED_HEADER_AND_BOOT_BLK="/dev/sdc" # Change it accordingly.
DETACHED_HEADER_AND_BOOT_PART="${DETACHED_HEADER_AND_BOOT_BLK}1"
DETACHED_BOOT_PARTITION_SIZE="2G"
LUKS_FORMAT_ARGS="-v --hash sha512 --use-urandom --verify-passphrase --header /mnt/${LUKS_HEADER_FILENAME}"

declare -A LVM_VOLUMES
LVM_VOLUMES[root]="-L 130G"
LVM_VOLUMES[var]="-L 95G"
LVM_VOLUMES[usr]="-L 15G"
LVM_VOLUMES[opt]="-L 5G"
LVM_VOLUMES[swap]="-L 3G"
LVM_VOLUMES[home]="-L 210G"

# LVM volumes are granularly divided so that I can define appropriate specific mounting arguments for some of them, as you can see below.
declare -A MOUNT_ARGS
MOUNT_ARGS[var]="-o rw,relatime,nosuid,nodev,noexec"
MOUNT_ARGS[usr]="-o rw,relatime,nodev"
MOUNT_ARGS[opt]="-o rw,relatime,nosuid,nodev"
MOUNT_ARGS[home]="-o rw,relatime,nosuid,nodev,noexec"
MOUNT_ARGS[boot]="-o noauto"

declare -A MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS
MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[proc]="-o nosuid,nodev,noexec,hidepid=2,gid=proc -t proc proc"
MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[tmp]="-o rw,relatime,nodev,nosuid,noexec,size=4G -t tmpfs tmpfs"

# Wi-Fi
WIFI_SSID="example" # Change it accordingly.
WIFI_PASSWORD="whatever" # Change it accordingly.
SSID_HIDDEN="" # Is it? So set to "Hidden=true".

# Script starts here.
set -e # If any command fails, this directive will kill the entire script.

# Prepare the USB drive where the /boot partition and the LUKS header will be stored (outside of the primary disk, detached of it).
sgdisk --clear --zap-all ${DETACHED_HEADER_AND_BOOT_BLK} # Wipe all the partitions and the partition table itself.
sgdisk -o ${DETACHED_HEADER_AND_BOOT_BLK}                # Create a GPT partition table
sgdisk -n 1:0:+${DETACHED_BOOT_PARTITION_SIZE} ${DETACHED_HEADER_AND_BOOT_BLK}        # Create the first and only 2GB partition
sgdisk -t 1:ef00 ${DETACHED_HEADER_AND_BOOT_BLK}         # Set the EF00 type to the partition
mkfs.fat -F32 ${DETACHED_HEADER_AND_BOOT_PART}           # FAT32 format the partition
mount ${DETACHED_HEADER_AND_BOOT_PART} /mnt

# Prepare the target drive.
sgdisk --clear --zap-all ${TARGET_DISK_BLK}  # Wipe all the partitions and the partition table itself.
echo -e "\n\n[+] Set and confirm the LUKS password!"
cryptsetup ${LUKS_FORMAT_ARGS} luksFormat ${TARGET_DISK_BLK}
echo -e "\n\n[+] Enter the LUKS password below, we'll open the disk now!"
cryptsetup --header /mnt/${LUKS_HEADER_FILENAME} open ${TARGET_DISK_BLK} ${LUKS_CONTAINER_LABEL}
umount /mnt

# Create the volume group.
pvcreate -q /dev/mapper/${LUKS_CONTAINER_LABEL}
vgcreate -q ${LVM_VG_LABEL} /dev/mapper/${LUKS_CONTAINER_LABEL}

# Create the volumes.
for key in "${!LVM_VOLUMES[@]}"; do
    lvcreate -q ${LVM_VOLUMES[$key]} ${LVM_VG_LABEL} -n $key
done

# Format all the ext4 volumes; Create and enable SWAP; Mount root volume;
for key in "${!LVM_VOLUMES[@]}"; do
    if [ "$key" = "swap" ]; then
        mkswap /dev/mapper/${LVM_VG_LABEL}-${key}
        swapon /dev/mapper/${LVM_VG_LABEL}-${key}
    else
        mkfs.ext4 -q /dev/mapper/${LVM_VG_LABEL}-${key}
        if [ "$key" = "root" ]; then
            mount /dev/mapper/${LVM_VG_LABEL}-${key} /mnt
        fi
    fi
done

# Mount ordinary volumes.
for key in "${!MOUNT_ARGS[@]}"; do
    mkdir /mnt/${key}
    if [ "$key" = "boot" ]; then
        mount ${MOUNT_ARGS[$key]} ${DETACHED_HEADER_AND_BOOT_PART} /mnt/${key}
    else
        mount ${MOUNT_ARGS[$key]} /dev/mapper/${LVM_VG_LABEL}-${key} /mnt/${key}
    fi
done

# Mount pseudo filesystems.
for key in "${!MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[@]}"; do
    mkdir /mnt/${key}
    mount ${MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[$key]} /mnt/${key}
done

# Stateful Firewall.
# It will DROP every INPUT packet, except the ones belonging to already established connections, then it will DROP and REJECT other packets using other criterias/states.
# Only OUTPUT can be used to establish new connections.
# Loopback connections are allowed.
systemctl start iptables

for chain in INPUT FORWARD OUTPUT; do
    iptables -P ${chain} DROP
done

iptables -A INPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED,NEW -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A INPUT -j REJECT --reject-with icmp-proto-unreachable

# Mirrorlist
curl -s --retry 4 "${HTTPS_NEARBY_MIRRORLIST}" > /etc/pacman.d/mirrorlist
sed -i 's/#Server/Server/' /etc/pacman.d/mirrorlist
sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional TrustedOnly/' /etc/pacman.conf
sed -i 's/^LocalFileSigLevel.*/LocalFileSigLevel = Required DatabaseOptional TrustedOnly/' /etc/pacman.conf # Personally, I block unsigned local packages by default, like this, then I undo this temporally when I need to install something trustworthy from AUR.

# Install the base system.
pacman -Syy
pacstrap -i /mnt ${PACSTRAP_PACKAGES} --ignore sudo

# Set computer's hostname
echo ${HOSTNAME} > /mnt/etc/hostname

# Set the root password
echo -e "\n\n[+] Set the root password!"
arch-chroot /mnt passwd

# pacman's aesthetics and signature levels
sed -i 's/#Color/Color/' /mnt/etc/pacman.conf
sed -i 's/#TotalDownload/TotalDownload/' /mnt/etc/pacman.conf
sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional TrustedOnly/' /mnt/etc/pacman.conf
# Below, personally, I block unsigned local packages by default.
# Then I undo this temporally when I need to install something unsigned, but trustworthy, from AUR.
sed -i 's/^LocalFileSigLevel.*/LocalFileSigLevel = Required DatabaseOptional TrustedOnly/' /mnt/etc/pacman.conf 

# Further Wi-Fi and general network setup.
if [[ $WIFI_SSID == *['!'@#\$%^\&*()_+-';']* ]]; then
    WIFI_SSID="=$(printf "${WIFI_SSID}" | xxd -pu)"
fi
iptables-save | tee /mnt/etc/iptables/ip{tables.rules,6tables.rules}
mkdir /mnt/{etc,var/lib}/iwd
echo -en "[General]\nEnableNetworkConfiguration=true" > /mnt/etc/iwd/main.conf
echo -en "[Settings]\n${SSID_HIDDEN}\n\n[Security]\nPassphrase=${WIFI_PASSWORD}" > /mnt/var/lib/iwd/${WIFI_SSID}.psk

# Empty the resolv.conf file if our DNS Servers array has data. TODO: Use dnscrypt-proxy instead, since I do it manually in post-installation.
if [ ${#DNSSERVERS[@]} -gt 0 ]; then
    cat /dev/null > /mnt/etc/resolv.conf
fi

# Set the DNS Servers. TODO: Use dnscrypt-proxy instead, since I do it manually in post-installation.
for DNSSERVER in "${DNSSERVERS[@]}"; do
    if [ -n "$DNSSERVER" ]; then
        echo -e "nameserver ${DNSSERVER}" >> /mnt/etc/resolv.conf
    fi
done

# Set resolv.conf as read-only since we want to set it in stone. TODO: Use dnscrypt-proxy instead, since I do it manually in post-installation.
if [ ${#DNSSERVERS[@]} -gt 0 ]; then
    chattr +i /mnt/etc/resolv.conf
fi

# Rootless Xorg setup, if desired.
if [ "$XORG_NEEDS_ROOT_RIGHTS" = "no" ]; then
    echo "needs_root_rights = no" > /mnt/etc/X11/Xwrapper.config
fi

# Select the desired locales
for LCL in "${LOCALES[@]}"; do
    sed -i "s/#$LCL/$LCL/" /mnt/etc/locale.gen
done

# Set locales
arch-chroot /mnt locale-gen
echo LANG=${LANGUAGE} > /mnt/etc/locale.conf
export LANG=${LANGUAGE}

# Set timezone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
arch-chroot /mnt hwclock --systohc

# User-specific setup
arch-chroot /mnt useradd -m -g users -s $MEUSHELL $USERNAME
echo -e "\n\n[+] Set the password for ${USERNAME}!"
arch-chroot /mnt passwd $USERNAME
arch-chroot /mnt su ${USERNAME} -c "ssh-keygen -t rsa -q -f '/home/${USERNAME}/.ssh/id_rsa' -C '' -N ''"

# Initial bootloader setup
arch-chroot /mnt bootctl install
echo -en "title Arch Linux\nlinux /vmlinuz-${KERNEL}\n${ADDITIONAL_INITRD}\ninitrd /initramfs-${KERNEL}.img" > /mnt/boot/loader/entries/arch.conf
echo -en "timeout 0\ndefault arch\neditor 0" > /mnt/boot/loader/loader.conf
echo -en "\n\n${KERNEL_BOOT_PARAMS}" >> /mnt/boot/loader/entries/arch.conf

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

# Set initcpio-related things and crypttab
touch /mnt/etc/vconsole.conf
sed -i "s/^HOOKS=(.*/HOOKS=(${MKINITCPIO_HOOKS})/" /mnt/etc/mkinitcpio.conf
sed -i "s|^FILES=(.*|FILES=(${MKINITCPIO_FILES})|" /mnt/etc/mkinitcpio.conf
sed -i "s/^MODULES=(.*/MODULES=(${MKINITCPIO_MODULES})/" /mnt/etc/mkinitcpio.conf
echo -en "enc\t${DISK_BY_ID}\tnone\theader=${MKINITCPIO_FILES}" > /mnt/etc/crypttab.initramfs

# Enable apparmor, iptables and iwd services
arch-chroot /mnt systemctl enable apparmor iptables iwd

# initcpio creation
arch-chroot /mnt mkinitcpio -p ${KERNEL}

# Let's save the sha512sum of the files from /boot 
# and save/copy this installation script from here to somewhere in the installed system)
sh -c "arch-chroot /mnt find /boot -type f -exec sha512sum {} \;" > /mnt/home/hashes.txt
cp -r ~/arch_install_sh/ /mnt/home/

# Let's generate our fstab (excluding the boot partition)
umount /mnt/boot
genfstab -U -P /mnt >> /mnt/etc/fstab

# Close things up.
echo -e "\n\n[+] Bye!"
swapoff --all
umount -R /mnt
vgchange -an ${LVM_VG_LABEL}
cryptsetup close ${LUKS_CONTAINER_LABEL}
# reboot
