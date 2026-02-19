#!/bin/bash
set -euo pipefail

if ! command -v mkosi >/dev/null 2>&1; then
  echo "=== Updating current system ==="
  apt update
  apt -y upgrade
  apt -y full-upgrade
  
  echo "=== Switching APT sources to Debian testing ==="
  rm -rf /etc/apt/sources.list.d/ /etc/apt/sources.list
  echo "deb http://deb.debian.org/debian testing main contrib non-free non-free-firmware" >> /etc/apt/sources.list
  echo "deb http://deb.debian.org/debian-security testing-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list
  echo "deb http://deb.debian.org/debian testing-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list
  
  echo "=== Updating package lists ==="
  apt update
  
  echo "=== Performing full upgrade to testing ==="
  apt -y full-upgrade
  
  echo "=== Installing mkosi with recommended packages ==="
  apt -y install --install-recommends mkosi git curl
  
  echo "=== Cleaning up ==="
  apt -y autoremove
  apt clean
  update-grub
  
  reboot
  exit 0
fi

rm -rf hrdnos && git clone https://github.com/lucasbeiler/arch_install_sh -b mkosi hrdnos
cd hrdnos

mkosi genkey
mkosi -B -f