#!/bin/bash
set -euo pipefail

########################################
# CONFIG
########################################

DISK=disk.img
DISK_SIZE=4G

ESP_SIZE_MIB=100
ROOT_SIZE_MIB=800
HASH_SIZE_MIB=200
DATA_SIZE_MIB=1024

ROOT_A=rootfs.squashfs
VERITY_A=rootfs.squashfs.verity
HASH_A=$(cat rootfs.squashfs.verityhash)

ROOT_B=rootfs.squashfs
VERITY_B=rootfs.squashfs.verity
HASH_B=$(cat rootfs.squashfs.verityhash)

KERNEL=rootfs/boot/vmlinuz-stable
INITRD=rootfs/boot/initramfs-stable
BOOT_EFI=/usr/lib/systemd/boot/efi/systemd-bootx64.efi

########################################
# CREATE DISK + GPT
########################################

echo "[+] Creating the disk..."
rm -f "$DISK"
qemu-img create -f raw "$DISK" "$DISK_SIZE"

echo "[+] Creating GPT partition table..."
parted -s "$DISK" mklabel gpt

CUR=1
ESP_END=$((CUR + ESP_SIZE_MIB))
parted -s "$DISK" mkpart ESP fat32 ${CUR}MiB ${ESP_END}MiB
parted -s "$DISK" set 1 esp on
CUR=$ESP_END

ROOT_A_END=$((CUR + ROOT_SIZE_MIB))
parted -s "$DISK" mkpart primary ${CUR}MiB ${ROOT_A_END}MiB
CUR=$ROOT_A_END

HASH_A_END=$((CUR + HASH_SIZE_MIB))
parted -s "$DISK" mkpart primary ${CUR}MiB ${HASH_A_END}MiB
CUR=$HASH_A_END

ROOT_B_END=$((CUR + ROOT_SIZE_MIB))
parted -s "$DISK" mkpart primary ${CUR}MiB ${ROOT_B_END}MiB
CUR=$ROOT_B_END

HASH_B_END=$((CUR + HASH_SIZE_MIB))
parted -s "$DISK" mkpart primary ${CUR}MiB ${HASH_B_END}MiB
CUR=$HASH_B_END

DATA_END=$((CUR + DATA_SIZE_MIB))
parted -s "$DISK" mkpart primary ${CUR}MiB ${DATA_END}MiB

########################################
# READ OFFSETS (bytes)
########################################

echo "[+] Reading partition offsets..."
mapfile -t OFFSETS < <(parted -s "$DISK" unit B print | awk '/^[ 0-9]/ {gsub("B","",$2); print $2}')

ESP_OFFSET=${OFFSETS[0]}
ROOT_A_OFFSET=${OFFSETS[1]}
HASH_A_OFFSET=${OFFSETS[2]}
ROOT_B_OFFSET=${OFFSETS[3]}
HASH_B_OFFSET=${OFFSETS[4]}
DATA_OFFSET=${OFFSETS[5]}

########################################
# CREATE ESP
########################################

echo "[+] Creating EFI (ESP) partition..."
truncate -s ${ESP_SIZE_MIB}MiB esp.img
mkfs.vfat esp.img

mmd -i esp.img ::/EFI
mmd -i esp.img ::/EFI/BOOT
mmd -i esp.img ::/loader
mmd -i esp.img ::/loader/entries

mcopy -i esp.img "$BOOT_EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i esp.img "$KERNEL" ::/vmlinuz
mcopy -i esp.img "$INITRD" ::/initramfs.img

cat > loader.conf <<EOF
default linux-a
timeout 3
editor no
EOF

cat > linux-a.conf <<EOF
title   Linux A
linux   /vmlinuz
initrd  /initramfs.img
options root=/dev/mapper/root
EOF

cat > linux-b.conf <<EOF
title   Linux B
linux   /vmlinuz
initrd  /initramfs.img
options root=/dev/mapper/root
EOF

mcopy -i esp.img loader.conf ::/loader/loader.conf
mcopy -i esp.img linux-a.conf ::/loader/entries/linux-a.conf
mcopy -i esp.img linux-b.conf ::/loader/entries/linux-b.conf

########################################
# WRITE PARTITIONS (fast dd)
########################################

echo "[+] Burning ESP to the disk..."
dd if=esp.img of="$DISK" bs=512 seek=$((ESP_OFFSET/512)) conv=notrunc status=progress

echo "[+] Burning root A to the disk..."
dd if="$ROOT_A" of="$DISK" bs=512 seek=$((ROOT_A_OFFSET/512)) conv=notrunc status=progress

echo "[+] Burning verity A to the disk..."
dd if="$VERITY_A" of="$DISK" bs=512 seek=$((HASH_A_OFFSET/512)) conv=notrunc status=progress

echo "[+] Burning root B to the disk..."
dd if="$ROOT_B" of="$DISK" bs=512 seek=$((ROOT_B_OFFSET/512)) conv=notrunc status=progress

echo "[+] Burning verity B to the disk..."
dd if="$VERITY_B" of="$DISK" bs=512 seek=$((HASH_B_OFFSET/512)) conv=notrunc status=progress

########################################
# FORMAT DATA PARTITION (LUKS2)
########################################

echo "[+] Setting up LUKS2 on data partition..."
sudo bash -c '
  set -euo pipefail

  mkdir -p /mnt/data /mnt/rootfs
  LOOPDEV=$(losetup --show -fP disk.img)
  DATA_PART="${LOOPDEV}p6"
  DEFAULT_LUKS_PASSWORD="temporary"

  echo -n "$DEFAULT_LUKS_PASSWORD" | cryptsetup luksFormat \
      --type luks2 \
      --cipher aes-xts-plain64 \
      --key-size 512 \
      --hash sha256 \
      "$DATA_PART" -
  echo -n "$DEFAULT_LUKS_PASSWORD" | cryptsetup open "$DATA_PART" data_crypt -

  mkfs.ext4 -L data /dev/mapper/data_crypt
  mount /dev/mapper/data_crypt /mnt/data
  mount -t squashfs -o loop rootfs.squashfs /mnt/rootfs

  mkdir -p /mnt/data/etc
  for f in /mnt/rootfs/etc/*.bkp; do
    [ -e "$f" ] || continue
    cp "$f" "/mnt/data/etc/$(basename "${f%.bkp}")"
  done

  useradd -P /mnt/data -m -s /bin/sh username
  passwd -P /mnt/data username
  mkdir -p /mnt/data/home/username

  umount /mnt/rootfs
  umount /mnt/data
  cryptsetup close data_crypt
  losetup -d "$LOOPDEV"
  rm -rf /mnt/rootfs /mnt/data
'

########################################
# CLEANUP
########################################

rm -f esp.img loader.conf linux-a.conf linux-b.conf

echo "ALL GOOD!"