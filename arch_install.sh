#!/bin/bash
set -euo pipefail

# Prepare some things and disable things I don't need.
tpm2_clear
rfkill block bluetooth
systemctl stop sshd
rm -f /etc/resolv.conf && echo 'nameserver 9.9.9.9' > /etc/resolv.conf # Temporarily set Quad9 as the DNS provider during install. Secure DNS will be set up later on.

# Check connectivity.
curl -sL -m5 www.kernel.org >/dev/null 2>&1 || { echo 'Error requesting kernel.org. Fix your Internet connection and try again!'; exit 1; }

# Wait for reflector to finish generating the mirrorlist and then make sure there is no non-HTTPS mirrors as part of the mirrorlist.
pgrep reflector && echo "[!] Waiting for reflector to finish modifying the mirrorlist..."
until ! pgrep reflector >/dev/null 2>&1; do sleep 1; done
sed -i '/http:\|rsync:\/\//d' /etc/pacman.d/mirrorlist

# Install the packages that this installation script depends on.
pacman -Sy efitools sbsigntools patch archlinux-keyring sbctl jq

# Load config.
source config.sh

# Ensure everything is unmounted before starting.
[ "$(mount | grep '/mnt')" ] && umount -R /mnt
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

# Mount the root filesystem.
mount /dev/mapper/${LUKS_CONTAINER_LABEL} /mnt

# Create the /efi/ directory and mount the FAT32 EFI partition.
mkdir /mnt/efi
mount /dev/disk/by-partlabel/${BOOT_PART_NAME} /mnt/efi

# Mount pseudo filesystems.
for key in "${!MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[@]}"; do
    mkdir -pv /mnt/${key}
    mount ${MOUNT_ARGS_FOR_PSEUDOFILESYSTEMS[$key]} /mnt/${key}
done

#### SYSTEM INSTALL BELOW!!

# Install Arch Linux with all the desired packages.
pacman -Syy
pacstrap -i /mnt ${PACSTRAP_PACKAGES} $PKGS_TO_IGNORE

# Copy config files and scripts to the new rootfs.
cp -r ./files/rootfs/usr/local/bin/* /mnt/usr/local/bin/ || echo 'ERROR!'
cp -r ./files/rootfs/etc/* /mnt/etc/ || echo 'ERROR!'
arch-chroot /mnt systemctl daemon-reload
arch-chroot /mnt chmod +s /usr/local/bin/allow_new_usb_tmp # This binary needs the SUID bit. It is not a security concern because it is a very simple binary and reads no input.
cp -r /var/lib/iwd/ /mnt/var/lib/ || echo 'Failed: There is nothing to copy.' # Copy all the Wi-Fi networks to the new system.

# Generate locales and set timezone.
arch-chroot /mnt locale-gen || echo 'Failed: Error generating locales!'
arch-chroot /mnt ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime || echo 'Apparently, the selected timezone is invalid!'

# Replace sudo with a symlink to OpenBSD's doas (safer, smaller codebase).
[ -x "/mnt/usr/bin/doas" ] && arch-chroot /mnt ln -sf /usr/bin/doas /usr/bin/sudo

# Enable the desired services.
arch-chroot /mnt systemctl enable $SERVICES_TO_ENABLE || echo 'Error: One or more of the selected services are invalid!'
arch-chroot /mnt systemctl disable systemd-timesyncd.service || echo 'Error: One or more of the selected services are invalid!'

# Generate Secure Boot keys and certs. They will be used to sign future boot chain images when installing updates.
arch-chroot /mnt sbctl create-keys

# Generate fstab, initramfs and install bootloader, everything signed for Secure Boot. 
genfstab -U -P /mnt >> /mnt/etc/fstab
arch-chroot /mnt sbctl sign -s /usr/lib/systemd/boot/efi/systemd-bootx64.efi # Sign systemd-boot and make sbctl remember this.
arch-chroot /mnt dracut -f --uefi --regenerate-all
arch-chroot /mnt bootctl install # Remove this line and keep the line below if you prefer EFISTUB over systemd-boot. 
# efibootmgr --create --disk ${TARGET_DISK_BLK} --part 1 --label "My Arch Linux" --loader /EFI/Linux/$(basename /mnt/efi/EFI/Linux/*.efi)

echo "[+] Set the root password!"
until arch-chroot /mnt passwd; do echo 'Try again!'; done;

# Setup systemd-resolved.
ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

# Close things up.
chmod +x /mnt/usr/local/bin/firstboot
mkdir -pv /mnt/etc/arch_install_sh && cp -r ./ /mnt/etc/arch_install_sh/
echo "[+] Bye! Run firstboot as soon as you boot into the installed system for the first time."
umount -R /mnt
[[ -b /dev/mapper/${LUKS_CONTAINER_LABEL} ]] && cryptsetup close ${LUKS_CONTAINER_LABEL}
reboot
