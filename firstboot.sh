#!/bin/bash
USERNAMES=('noone' 'lucas')
unset LD_PRELOAD

set -e
reboot () { echo 'Reboot now? (y/N)' && read x && [[ "$x" == "y" ]] && /sbin/reboot; }
reboot_firm () { echo 'Reboot now? (y/N)' && read x && [[ "$x" == "y" ]] && /usr/bin/systemctl reboot --firmware-setup; }
ask_usbguard_gen () { echo 'Generate usbguard policy now (Y/n)' && read x && [[ "$x" != "n" ]] && $PRIVESC_PREFIX usbguard generate-policy | $PRIVESC_PREFIX tee /etc/usbguard/rules.conf; } 
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
        until $PRIVESC_PREFIX homectl create $USERNAME --storage luks --fs-type btrfs --member-of=wheel,libvirt,docker,video,audio,users --nosuid=true --nodev=true --noexec=true --luks-discard=true; do echo -en '\nTente novamente!\n'; done;
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
# Do you want to run things as root? Use sudo/doas.
if ! $PRIVESC_PREFIX cat /etc/shadow | grep -iq 'root:!'; then
    echo -e "Locking the root user...\n"
    $PRIVESC_PREFIX passwd -l root
fi

# Enroll TPM2 keys.
echo "Verifying TPM2 and Secure Boot enrollment statuses..."
if [ $(sbctl status | grep "^Setup Mode" | awk 'NF>1{print $NF}' | sed -e 's/^[[:space:]]*//') = "Disabled" ] && [ $(sbctl status | grep "^Secure Boot" | awk 'NF>1{print $NF}' | sed -e 's/^[[:space:]]*//') = "Enabled" ]; then
    if ! $PRIVESC_PREFIX systemd-cryptenroll /dev/gpt-auto-root-luks | grep -qi tpm2; then
	    # $PRIVESC_PREFIX systemd-cryptenroll /dev/gpt-auto-root-luks --recovery-key
        $PRIVESC_PREFIX systemd-cryptenroll /dev/gpt-auto-root-luks --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=0+1+2+3+5+7  # Always run when the system suffer changes on the hardware, UEFI firmware, partition tables or Secure Boot keys. TODO: Consider PCR 14.
        $PRIVESC_PREFIX systemd-cryptenroll /dev/gpt-auto-root-luks --wipe-slot=password
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
pkgs="hardened-malloc-git wayfire wf-shell dracut-hook-uefi"
mkdir -pv ~/yay_dir_with_exec
if ! pacman -Qi $pkgs >/dev/null 2>&1; then
    if findmnt -T ~/yay_dir_with_exec/ | grep -qi noexec; then
        # Temporary workaround for 'hardened /home' since I have user's home mounted with noexec.
        sudo mount --bind $HOME/yay_dir_with_exec $HOME/yay_dir_with_exec
        sudo mount $HOME/yay_dir_with_exec -oremount,exec
        yay --builddir $HOME/yay_dir_with_exec --save
    fi
    
    for pkg in $pkgs; do
        if ! pacman -Qi $pkg >/dev/null 2>&1; then
            yay -Sy $pkg
        fi
    done
else
    echo -e "We already have all those packages installed.\n"
fi

# Run this as the user that you want to apply the dotfiles.
if [ ! -d "$HOME/dotfiles" ]; then
    git clone https://github.com/lucassbeiler/dotfiles ~/dotfiles
    cp -r ~/dotfiles/.{config,*rc} ~/
    sudo cp -r ~/dotfiles/usr/local/bin/* /usr/local/bin/
    sudo cp -r ~/dotfiles/etc/* /etc/
fi

$PRIVESC_PREFIX systemctl daemon-reload
$PRIVESC_PREFIX systemctl enable mydenyusb
$PRIVESC_PREFIX timedatectl set-ntp true
ask_usbguard_gen
