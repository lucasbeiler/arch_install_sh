#!/bin/bash
unset LD_PRELOAD

set -e

if [ "$(id -u)" -eq 0 ]; then
    echo "Do not run this as root."
    exit 1
fi
    
if [ ! $(command -v yay) ]; then
    rm -rf ~/yay
    git clone https://aur.archlinux.org/yay.git ~/yay
    cd ~/yay && makepkg -si
fi

if [ ! -f "/usr/lib/libhardened_malloc.so" ]; then
    yay -Syyu hardened-malloc-git
fi

if [ ! $(command -v wayfire) ]; then
    # Temporary workaround for 'hardened /home' (noexec)
    mkdir ~/dmz_dir
    sudo mount --bind $HOME/dmz_dir $HOME/dmz_dir
    sudo mount $HOME/dmz_dir -oremount,exec
    yay --builddir $HOME/dmz_dir --save
  
    yay -Syyu wayfire wf-shell # TODO: Check if the wayfire pkg can be used with wf-shell-git pkg.
fi