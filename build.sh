#!/bin/bash
set -euo pipefail

# Architecture and Alpine version.
ARCH=$(uname -m)
VERSION=edge
MIRROR=https://dl-cdn.alpinelinux.org/alpine
WORKDIR=/hardenedos/rootfs
OUTPUT=/hardenedos/rootfs.squashfs
ENABLE_TESTING=true
readonly ALPINE_KEYS='
alpine-devel@lists.alpinelinux.org-4a6a0840.rsa.pub:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1yHJxQgsHQREclQu4Ohe\nqxTxd1tHcNnvnQTu/UrTky8wWvgXT+jpveroeWWnzmsYlDI93eLI2ORakxb3gA2O\nQ0Ry4ws8vhaxLQGC74uQR5+/yYrLuTKydFzuPaS1dK19qJPXB8GMdmFOijnXX4SA\njixuHLe1WW7kZVtjL7nufvpXkWBGjsfrvskdNA/5MfxAeBbqPgaq0QMEfxMAn6/R\nL5kNepi/Vr4S39Xvf2DzWkTLEK8pcnjNkt9/aafhWqFVW7m3HCAII6h/qlQNQKSo\nGuH34Q8GsFG30izUENV9avY7hSLq7nggsvknlNBZtFUcmGoQrtx3FmyYsIC8/R+B\nywIDAQAB
alpine-devel@lists.alpinelinux.org-5261cecb.rsa.pub:MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwlzMkl7b5PBdfMzGdCT0\ncGloRr5xGgVmsdq5EtJvFkFAiN8Ac9MCFy/vAFmS8/7ZaGOXoCDWbYVLTLOO2qtX\nyHRl+7fJVh2N6qrDDFPmdgCi8NaE+3rITWXGrrQ1spJ0B6HIzTDNEjRKnD4xyg4j\ng01FMcJTU6E+V2JBY45CKN9dWr1JDM/nei/Pf0byBJlMp/mSSfjodykmz4Oe13xB\nCa1WTwgFykKYthoLGYrmo+LKIGpMoeEbY1kuUe04UiDe47l6Oggwnl+8XD1MeRWY\nsWgj8sF4dTcSfCMavK4zHRFFQbGp/YFJ/Ww6U9lA3Vq0wyEI6MCMQnoSMFwrbgZw\nwwIDAQAB
alpine-devel@lists.alpinelinux.org-6165ee59.rsa.pub:MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAutQkua2CAig4VFSJ7v54\nALyu/J1WB3oni7qwCZD3veURw7HxpNAj9hR+S5N/pNeZgubQvJWyaPuQDm7PTs1+\ntFGiYNfAsiibX6Rv0wci3M+z2XEVAeR9Vzg6v4qoofDyoTbovn2LztaNEjTkB+oK\ntlvpNhg1zhou0jDVYFniEXvzjckxswHVb8cT0OMTKHALyLPrPOJzVtM9C1ew2Nnc\n3848xLiApMu3NBk0JqfcS3Bo5Y2b1FRVBvdt+2gFoKZix1MnZdAEZ8xQzL/a0YS5\nHd0wj5+EEKHfOd3A75uPa/WQmA+o0cBFfrzm69QDcSJSwGpzWrD1ScH3AK8nWvoj\nv7e9gukK/9yl1b4fQQ00vttwJPSgm9EnfPHLAtgXkRloI27H6/PuLoNvSAMQwuCD\nhQRlyGLPBETKkHeodfLoULjhDi1K2gKJTMhtbnUcAA7nEphkMhPWkBpgFdrH+5z4\nLxy+3ek0cqcI7K68EtrffU8jtUj9LFTUC8dERaIBs7NgQ/LfDbDfGh9g6qVj1hZl\nk9aaIPTm/xsi8v3u+0qaq7KzIBc9s59JOoA8TlpOaYdVgSQhHHLBaahOuAigH+VI\nisbC9vmqsThF2QdDtQt37keuqoda2E6sL7PUvIyVXDRfwX7uMDjlzTxHTymvq2Ck\nhtBqojBnThmjJQFgZXocHG8CAwEAAQ==
'

# Require root.
if [ "$EUID" -ne 0 ]; then echo "Be root!"; exit 1; fi;

# TODO: DEBUGGING. REMOVE!
pacman -Syu --noconfirm qemu-full curl squashfs-tools erofs-utils abuild alpine-keyring apk-tools 
killall qemu-system-x86_64 || :

# Download the official static build of apk. (TODO: Reproducible Builds!)
if ! command -v apk >/dev/null 2>&1; then
  curl -sSL -o "/usr/local/bin/apk" "https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v2.14.10/x86_64/apk.static"
  chmod +x /usr/local/bin/apk
fi

# Clean up previous work
umount ${WORKDIR}/dev ${WORKDIR}/proc ${WORKDIR}/sys 2>/dev/null || :
rm -rf $WORKDIR && mkdir -p $WORKDIR

# Prepare chroot with pseudofilesystems.
mkdir -p ${WORKDIR}/proc ${WORKDIR}/dev ${WORKDIR}/sys
for pseudofs in proc sys dev; do mount -o bind /${pseudofs} ${WORKDIR}/${pseudofs}; done

# Prepare basic DNS connectivity inside the chroot.
mkdir -p ${WORKDIR}/etc/
echo "9.9.9.9" > ${WORKDIR}/etc/resolv.conf

mkdir -p ${WORKDIR}/etc/mkinitfs
echo 'features="ata base ide scsi usb virtio ext4 nvme squashfs"' >> ${WORKDIR}/etc/mkinitfs/mkinitfs.conf

# Set up the official package repositories. 
# In the future, I'll have my own repositories for some specific packages (hardened builds of Chromium, iwd, and other security-critical software). 
# And, also, I'll continuously test for Reproducible Builds for the packages that I use from the Alpine repositories.
mkdir -p ${WORKDIR}/etc/apk/keys
echo "$MIRROR/$VERSION/main" >> $WORKDIR/etc/apk/repositories
echo "$MIRROR/$VERSION/community" >> $WORKDIR/etc/apk/repositories
if [[ $VERSION == "edge" || $ENABLE_TESTING == true ]]; then
  echo "$MIRROR/edge/testing" >> $WORKDIR/etc/apk/repositories
fi

for line in $ALPINE_KEYS; do
  file=${line%%:*}
  content=${line#*:}
  printf -- "-----BEGIN PUBLIC KEY-----\n$content\n-----END PUBLIC KEY-----\n" > "$WORKDIR/etc/apk/keys/$file"
done

# Install the base packages
apk -p $WORKDIR --arch $ARCH --initdb --no-cache add alpine-base alpine-baselayout busybox busybox-suid musl-utils fortify-headers iwd e2fsprogs util-linux
apk -p $WORKDIR --arch $ARCH --no-cache add sway hyprland river mako grim fastfetch slurp flameshot swaybg swaylock swayidle kanshi fuzzel yazi waybar alacritty font-dejavu libinput
apk -p $WORKDIR --arch $ARCH --no-cache add iptables pipewire-pulse pipewire wireplumber pavucontrol apparmor apparmor-profiles apparmor-utils hardened-malloc checksec-rs ntpd-rs dnscrypt-proxy curl 
apk -p $WORKDIR --arch $ARCH --no-cache add cryptsetup dbus font-terminus qemu-img cloud-hypervisor xf86-input-libinput xf86-input-evdev mesa linux-firmware-none linux-stable linux-stable-dev linux-headers wayvnc mesa-dri-gallium mesa-va-gallium pciutils xf86-video-modesetting chromium bash eudev udev-init-scripts

echo "/usr/lib/libhardened_malloc.so" > ${WORKDIR}/etc/ld.so.preload
echo -en "auto lo\niface lo inet loopback" > ${WORKDIR}/etc/network/interfaces

# chroot $WORKDIR rc-update add apparmor boot # TODO: Needs a patched kernel to work.
chroot $WORKDIR rc-update add networking boot
chroot $WORKDIR rc-update add devfs sysinit
chroot $WORKDIR rc-update add hwclock boot
chroot $WORKDIR rc-update add hwdrivers sysinit
chroot $WORKDIR rc-update add modules boot
chroot $WORKDIR rc-update add sysctl boot
chroot $WORKDIR rc-update add hostname boot
chroot $WORKDIR rc-update add mount-ro shutdown
chroot $WORKDIR rc-update add killprocs shutdown

chroot $WORKDIR rc-update add udev sysinit
chroot $WORKDIR rc-update add udev-trigger sysinit
chroot $WORKDIR rc-update add udev-settle sysinit
chroot $WORKDIR rc-update add udev-postmount default

chroot $WORKDIR rc-update add iptables 
# chroot $WORKDIR rc-update add dnscrypt-proxy # TODO: Patch its configuration to my liking.
chroot $WORKDIR rc-update add ntpd-rs
# chroot $WORKDIR rc-update add iwd boot
# chroot $WORKDIR rc-update del networking boot

chroot $WORKDIR setup-desktop sway

echo "tmpfs /var/tmp tmpfs rw,nosuid,nodev,noexec 0 0" >> ${WORKDIR}/etc/fstab
echo "tmpfs /tmp tmpfs rw,nosuid,nodev,noexec 0 0" >> ${WORKDIR}/etc/fstab
echo "proc /proc proc rw,nosuid,nodev,noexec,gid=26,hidepid=invisible 0 0" >> ${WORKDIR}/etc/fstab
echo "tmpfs /root tmpfs rw,nosuid,nodev,noexec 0 0" >> ${WORKDIR}/etc/fstab
echo "tmpfs /root tmpfs rw,nosuid,nodev,noexec 0 0" >> ${WORKDIR}/etc/fstab
echo "LABEL=data /data ext4 defaults,nosuid,nodev,noexec 0 2" >> ${WORKDIR}/etc/fstab

# Lock root user forever. # TODO: Keep uncommented.
# chroot $WORKDIR passwd -l root 

# Copy some stuff.
cp -r root_files/* ${WORKDIR}/

cp -r ${WORKDIR}/etc/shadow ${WORKDIR}/etc/shadow.bkp
cp -r ${WORKDIR}/etc/passwd ${WORKDIR}/etc/passwd.bkp
cp -r ${WORKDIR}/etc/group  ${WORKDIR}/etc/group.bkp

chroot ${WORKDIR} ln -sf /data/etc/shadow /etc/shadow
chroot ${WORKDIR} ln -sf /data/etc/passwd /etc/passwd
chroot ${WORKDIR} ln -sf /data/etc/group /etc/group

rm -rf ${WORKDIR}/home/
chroot ${WORKDIR} ln -sf /data/home /home

mkdir ${WORKDIR}/data

# Enable my services.
# chroot $WORKDIR rc-update add populate-var-etc sysinit

# Prepare mkinitfs.
mkdir -p ${WORKDIR}/etc/mkinitfs/features.d
echo 'features="ata base ide scsi usb virtio ext4 squashfs erofs nvme veritysetup verityhash my-custom-script"' > ${WORKDIR}/etc/mkinitfs/mkinitfs.conf
echo "/verityhash" >> ${WORKDIR}/etc/mkinitfs/features.d/verityhash.files
echo "/sbin/veritysetup" >> ${WORKDIR}/etc/mkinitfs/features.d/veritysetup.files
echo "kernel/drivers/md/dm-verity.ko*" >> ${WORKDIR}/etc/mkinitfs/features.d/veritysetup.modules
# echo "kernel/fs/erofs" >> ${WORKDIR}/etc/mkinitfs/features.d/erofs.modules

# Umount things.
umount ${WORKDIR}/dev ${WORKDIR}/proc ${WORKDIR}/sys 2>/dev/null

# Create an EROFS image with LZ4 compression
rm -f $OUTPUT
# mkfs.erofs $OUTPUT $WORKDIR
mksquashfs $WORKDIR $OUTPUT
chmod 777 $OUTPUT

VERITY_INFO=$(veritysetup format "$OUTPUT" "${OUTPUT}.verity")
echo "Done: $OUTPUT"

# The rootfs image is already done and verity'ed, so let's (re)create the initramfs now...
echo "$VERITY_INFO" | awk '/Root hash:/ {print $3}' | tee ${WORKDIR}/verityhash
chroot ${WORKDIR} mkinitfs 6.18.13-0-stable

# TODO: Remove. This is just for debugging.
rm -rf rootfs*
cp -r /hardenedos/rootfs* .
chown -R work:users rootfs rootfs.squashfs rootfs.squashfs.verity rootfs.squashfs.verityhash
echo "ALL GOOD!"
exit 0

qemu-system-x86_64 \
    -drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/x64/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=OVMF_VARS.4m.fd \
    -vga virtio \
    -display gtk,gl=on \
    -audio driver=pa,model=virtio,server=/run/user/60416/pulse/native \
    -usb -device usb-tablet -device usb-mouse -device usb-kbd \
    -hda disk.img \
    -m 2G \
    -enable-kvm \
    -boot order=c \
    -net nic -net user