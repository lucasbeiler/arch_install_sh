#!/bin/bash
# Arch Linux automated installation
set -e
systemctl stop sshd
pacman -Sy efitools sbsigntools patch archlinux-keyring sbctl jq

# Load config.
source config.sh

# Ensure everything is unmounted before starting.
[ "$(mount | grep '/mnt')" ] && umount -R /mnt
swapoff -a || echo "Looks like there's no swap on to swapoff!"
[[ -b /dev/mapper/${LUKS_CONTAINER_LABEL} ]] && cryptsetup close ${LUKS_CONTAINER_LABEL}

# It will automatically detect the biggest SSD available.
TARGET_DISK_BLK="/dev/$(lsblk -x SIZE -d -o name,rota,type --json | jq -r '.blockdevices[] | select(( .rota == false) and .type == "disk").name' | tac | head -n1)"
lsblk
read -p "I've detected ${TARGET_DISK_BLK}, is it right? (Y/correct blk): " -r
if [[ $REPLY =~ ^[\/] ]]; then
    TARGET_DISK_BLK=$REPLY
    until [ -b $TARGET_DISK_BLK ]; do read -p "Incorrect ${TARGET_DISK_BLK} block device. Enter blk now, exactly: " -r TARGET_DISK_BLK; done;
fi
echo "OK. I'll use $TARGET_DISK_BLK."

# Remove partition tables from the target disk.
sgdisk --clear --zap-all ${TARGET_DISK_BLK}
sgdisk -n1:0:+550M -t1:ef00 -c1:${BOOT_PART_NAME} -N2 -t2:8304 -c2:${ROOT_PART_NAME} ${TARGET_DISK_BLK}
sync && partprobe ${TARGET_DISK_BLK} && sleep 2

# Setup LUKS on the target disk.
echo "[+] Set and confirm the LUKS password (it'll be temporary as we will remove the password and use a TPM2-enrolled-key afterwards)!"
until cryptsetup ${LUKS_FORMAT_ARGS} luksFormat /dev/disk/by-partlabel/${ROOT_PART_NAME}; do echo 'Try again!'; done;
echo "[+] Enter the LUKS password below, we'll open the disk now!"
until cryptsetup open /dev/disk/by-partlabel/${ROOT_PART_NAME} ${LUKS_CONTAINER_LABEL}; do echo 'Try again!'; done

# Format the filesystems.
mkfs.fat -F32 -n ${BOOT_PART_NAME} /dev/disk/by-partlabel/${BOOT_PART_NAME}
mkfs.btrfs -f -L ${ROOT_PART_NAME} /dev/mapper/${LUKS_CONTAINER_LABEL}

# Mount BTRFS root.
mount /dev/mapper/${LUKS_CONTAINER_LABEL} /mnt

# Prepare the /efi/ dir and mount the FAT32 EFI partition into it.
mkdir /mnt/efi
mount /dev/disk/by-partlabel/${BOOT_PART_NAME} /mnt/efi

# Mount pseudo filesystems.
for key in "${!MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[@]}"; do
    mkdir -pv /mnt/${key}
    mount ${MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[$key]} /mnt/${key}
done

# Check connectivity.
until curl -L -s www.kernel.org 2>/dev/null 1>&2; do echo 'Error requesting kernel.org. Are we connected to the Internet?'; done;

# Remove non-HTTPS mirrors from the mirrorlist.
sed -i '/http:\|rsync:\/\//d' /etc/pacman.d/mirrorlist # I will not run reflector since archiso already does it.

#### SYSTEM INSTALL BELOW!!
#### SYSTEM INSTALL BELOW!!
#### SYSTEM INSTALL BELOW!!

# Install Arch Linux with all the desired packages.
pacman -Syy
pacstrap -i /mnt ${PACSTRAP_PACKAGES} $PKGS_TO_IGNORE

# Copy config files and scripts to the new rootfs.
cp -r ./files/rootfs/usr/local/bin/* /mnt/usr/local/bin/ || echo 'ERROR!'
cp -r ./files/rootfs/etc/* /mnt/etc/ || echo 'ERROR!'
arch-chroot /mnt systemctl daemon-reload
cp -r /var/lib/iwd/ /mnt/var/lib/ || echo 'Failed: There is nothing to copy.' # Copy all the PSK-based networks to the new system.

# Generate locales and set timezone.
arch-chroot /mnt locale-gen || echo 'Failed: Error generating locales!'
arch-chroot /mnt ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime || echo 'Apparently, the selected timezone is invalid!'

# Replace sudo with OpenBSD's doas (safer, smaller codebase).
[ -x "/mnt/usr/bin/doas" ] && arch-chroot /mnt ln -sf /usr/bin/doas /usr/bin/sudo

# Apply dnscrypt-proxy settings.
patch /mnt/etc/dnscrypt-proxy/dnscrypt-proxy.toml files/patch_dnscryptproxy_toml.patch
chattr +i /mnt/etc/resolv.conf

# Enable the desired services.
arch-chroot /mnt systemctl enable $SERVICES_TO_ENABLE || echo 'Error: One or more of the selected services are invalid!'

# Generate Secure Boot keys and certs.
arch-chroot /mnt sbctl create-keys

# Generate initramfs and install bootloader, everything signed for Secure Boot. 
genfstab -U -P /mnt >> /mnt/etc/fstab
arch-chroot /mnt sbctl sign -s /usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot /mnt dracut -f --uefi --regenerate-all
arch-chroot /mnt bootctl install # Remove this line and keep the line below if you prefer EFISTUB over systemd-boot. 
# efibootmgr --create --disk ${TARGET_DISK_BLK} --part 1 --label "Meu Arch Linux" --loader /EFI/Linux/$(basename /mnt/efi/EFI/Linux/*.efi)

echo "[+] Set the root password!"
until arch-chroot /mnt passwd; do echo 'Try again!'; done;

# This is my custom systemd service to set kernel.deny_new_usb=1 some time after boot.
# It disables the whole USB subsystem in runtime. From a hardening perspective, it is good.
# In the future, I'm probably going to do something in order to automatically set kernel.deny_new_usb=1 when users are logged out.
arch-chroot /mnt systemctl enable mydenyusb || echo 'Error: Maybe this service does not exist in your system.'

# Close things up.
chmod +x /mnt/usr/local/bin/firstboot
mkdir -pv /mnt/etc/arch_install_sh && cp -r ./ /mnt/etc/arch_install_sh/
echo "[+] Bye! Run firstboot as soon as you boot into the installed system for the first time."
umount -R /mnt
[[ -b /dev/mapper/${LUKS_CONTAINER_LABEL} ]] && cryptsetup close ${LUKS_CONTAINER_LABEL}
reboot
