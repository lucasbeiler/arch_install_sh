#!/bin/bash
USERNAMES=('noone' 'lucas')
declare -A USER_GROUPS
USER_GROUPS[${USERNAMES[0]}]="wheel,libvirt,docker,video,audio,users"
USER_GROUPS[${USERNAMES[1]}]="docker,video,audio,users"

unset LD_PRELOAD

set -e
reboot () { echo 'Reboot now? (y/N)' && read x && [[ "$x" == "y" ]] && /sbin/reboot; }
reboot_firm () { echo 'Reboot now? (y/N)' && read x && [[ "$x" == "y" ]] && /usr/bin/systemctl reboot --firmware-setup; }

PRIVESC_PREFIX="/usr/bin/sudo" # In my system it is a symlink to /usr/bin/doas.
if [ "$(id -u)" -eq 0 ]; then
    unset PRIVESC_PREFIX # Unset since doas refuses to be called by the root user.
fi

$PRIVESC_PREFIX chattr +C /home/
# Create encrypted-home users.
# TODO: Move user creation to the install script (homectl cannot operate from chroot, I'll need some workaround).
echo "Creating users..."
for USERNAME in "${USERNAMES[@]}"; do
    if ! id -u $USERNAME > /dev/null 2>&1; then
        until $PRIVESC_PREFIX homectl create $USERNAME --storage luks --fs-type btrfs --member-of=${USER_GROUPS[$USERNAME]} --rate-limit-interval=5000 --rate-limit-burst=8 --nosuid=true --nodev=true --noexec=true --luks-discard=true; do echo -en '\nTente novamente!\n'; done;
    else
        echo "User ${USERNAME} already exists. Ignoring."
    fi
done
echo -e "\n"

# Enroll Secure Boot keys and reboot.
echo "Checking Secure Boot key enrollment status..."
if [ $(sbctl status | grep "^Setup Mode" | awk 'NF>1{print $NF}' | sed -e 's/^[[:space:]]*//') = "Enabled" ]; then
    $PRIVESC_PREFIX sbctl enroll-keys
    $PRIVESC_PREFIX reboot_firm
elif [ $(sbctl status | grep "^Secure Boot" | awk 'NF>1{print $NF}' | sed -e 's/^[[:space:]]*//') = "Enabled" ]; then
    echo "We are already booted with Secure Boot and Setup Mode is disabled."
    echo -e "Therefore the appropriate keys are supposed to be already enrolled. Bye.\n"
fi

# Disable direct access to the root user as we don't need it anymore.
# Do you want to run things as root? Use sudo (I recommend doas instead of sudo) with your wheel group users.
if ! $PRIVESC_PREFIX cat /etc/shadow | grep -iq 'root:!'; then
    echo -e "Locking the root user...\n"
    $PRIVESC_PREFIX passwd -l root
fi

# Enroll TPM2 keys. TODO: Verify and warn if the TPM2 chip vendor was affected by the TPMFAIL vulnerability back in 2019.
echo "Verifying TPM2 and Secure Boot enrollment statuses..."
if [ $(sbctl status | grep "^Setup Mode" | awk 'NF>1{print $NF}' | sed -e 's/^[[:space:]]*//') = "Disabled" ] && [ $(sbctl status | grep "^Secure Boot" | awk 'NF>1{print $NF}' | sed -e 's/^[[:space:]]*//') = "Enabled" ]; then
    if ! $PRIVESC_PREFIX systemd-cryptenroll /dev/gpt-auto-root-luks | grep -qi tpm2; then
	    # $PRIVESC_PREFIX systemd-cryptenroll /dev/gpt-auto-root-luks --recovery-key
        $PRIVESC_PREFIX systemd-cryptenroll /dev/gpt-auto-root-luks --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=0+1+2+3+5+7  # These hash-based PCRs will render the system unbootable if: Hardware, UEFI firmware, partition tables or Secure Boot keys are tampered. TODO: Consider PCR 14.
        $PRIVESC_PREFIX systemd-cryptenroll /dev/gpt-auto-root-luks --wipe-slot=password # Remove any LUKS password, as the only password was stored into TPM2 and protected by those PCRs.
        reboot
    else
        echo -e "LUKS TPM slot is already set up.\n"
    fi
else
    echo "ERROR: I ain't gonna seal the keys against TPM2 as Secure Boot isn't properly set up yet."
fi

# I don't like to run makepkg and yay as root.
if [ "$(id -u)" -eq 0 ]; then
    echo "Do not run this part of the script as root."
    exit 1
fi

# Install yay.
if [ ! $(command -v yay) ]; then
    rm -rf ~/yay
    git clone https://aur.archlinux.org/yay.git ~/yay
    cd ~/yay && makepkg -si
else
    echo -e "yay is already installed!\n"
fi

# Install some of the AUR packages that I need.
yay -Sy --needed hardened-malloc-git dracut-hook-uefi

# Run this as the user that you want to apply the dotfiles.
if [ ! -d "$HOME/dotfiles" ]; then
    git clone https://github.com/lucassbeiler/dotfiles ~/dotfiles
    cp -r ~/dotfiles/.homes/.{config,*rc} ~/
    #sudo cp -r ~/dotfiles/.rootfs/usr/local/bin/* /usr/local/bin/
    #sudo cp -r ~/dotfiles/.rootfs/etc/* /etc/
    $PRIVESC_PREFIX cp -r ~/dotfiles/.rootfs/* / || echo 'ERROR!'
fi

$PRIVESC_PREFIX systemctl daemon-reload
$PRIVESC_PREFIX systemctl enable mydenyusb
$PRIVESC_PREFIX timedatectl set-ntp true # TODO: Implement NTS (which is TLS-based NTP) instead of the insecure NTP for time integrity and authenticity.
