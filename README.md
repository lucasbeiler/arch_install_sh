## Summary and main features of this script
This script automates the installation of a security-focused Arch Linux environment.

Arch Linux is a good distribution, with a high amount of packages passing build reproducibility tests, providing transparency in trusting that the distributed binaries match the software source code. Also, maintainers keep good security practices and compile their packages with proper mitigations enforced by compiler flags, they also do a pretty good job at keeping packages closer to upstream software.

* **Secure Boot:**
  - Bootloader, kernel, microcode and initrd are combined following the Unified Kernel Image specification. This image is authenticated by Secure Boot on each boot, ensuring the authenticity and integrity of the entire initial boot chain.

* **Full Disk Encryption with LUKS:**
  - Keys are securely stored on the TPM 2.0 chip, granting access only under strict conditions of authenticity. This setup guarantees that disk decryption will only happen when hardware, firmware and Secure Boot setup are intact and in a known good state;
    - Secure Boot, LUKS and TPM 2.0 together are useful to improve the boot process, making it more secure and tamper-evident. A tampered firmware or boot chain will not boot the operating system successfully.
  - A TPM PIN is also enabled to prevent the system from booting automatically. If the correct PIN is not entered, communication with the TPM does not even begin;
    - This PIN is limited to a maximum of 4 failed attempts every 24 hours to drastically slow down dictionary attacks. This throttling turns even a short, random PIN into something difficult to crack (if we pretend that the TPM is always reliable and has no vulnerabilities, which is not always true).
  - Finally, each user has an encrypted home directory protected by the user's password. This is managed by systemd-homed (which uses LUKS for encryption);
    - If TPM vulnerabilities and their expensive exploits really scare you (or if you're a valuable enough target), use a diceware passphrase of 7 or more really random words to protect your home directories, then avoid storing sensitive data outside of home directories. 
      - Yes, typing a huge diceware passphrase at every login or screen unlock would be a pain, do it only if you really need. Alternatively, the length of this passphrase can correspond to your threat model, in order to try to combine security and convenience without relying solely on the TPM.
  - In order to close the disk to a back-at-rest state (encrypted) in case someone takes the computer while it is turned on, a custom code runs alongside KDE Plasma listening for D-Bus screen lock and unlock events. When the screen is locked (after 5 minutes of inactivity or by pressing Win+L), `shutdown -h +30` is executed to unconditionally shut down the computer within 30 minutes. If the screen is successfully unlocked, the scheduled shutdown is canceled.
    - In order to enforce this behaviour, it's a good habit to lock the screen by pressing Win+L whenever you leave the computer unattended.

* **USB hardening**
  - The USB subsystem is always disabled in the kernel. 
    - My [allow_new_usb_tmp SUID binary](https://github.com/lucasbeiler/arch_install_sh/tree/master/files/allow_new_usb_tmp) can be called to temporarily enable it (for 30 seconds) when you need to use the USB ports;
      - Even though it is a SUID binary, it is safe because it takes no user input, all it does is strictly set the `kernel.deny_new_usb` kernel flag to `0` for 30 seconds and then set it back to `1`. Doing so, you can create a keyboard shortcut to call this binary in order to allow USB for 30 seconds when you want to, without requiring root privileges to toggle the flag on and off.
    - For Thunderbolt, there is a blacklist completely disabling the thunderbolt kernel module (as a mitigation against DMA, in addition to IOMMU enforcement).

* **Modern memory corruption exploit mitigations**
  - Intel CET [Control-flow Enforcement Technology] is enabled and glibc is configured to enforce it as much as possible via the `glibc.cpu.x86_shstk=on:glibc.cpu.x86_ibt=on` tunable. Intel CET has Intel IBT providing coarse-grained forward-edge CFI protections and has Intel Shadow Stack providing backward-edge CFI protections.
    - Note that this only applies to computers with very recent Intel or AMD processors.

* **Kernel:**
  - This installation uses the linux-hardened kernel, which has security/hardening patches and safer defaults as well as safer build-time configuration and flags;
  - The script further ensures kernel security by blocking old and unused modules, and applying additional secure settings through sysctl flags and kernel boot parameters.

* **Stateful Firewall:**
  - Firewall rules are used within iptables in order to implement a stateful firewall, allowing only outgoing connections and dropping packets from incoming connections initiated by the other end. This way, only outgoing packets are able to start new connections.

* **Secure DNS:**
  - Configures system-wide secure DNS using systemd-resolved, operating over the DoT (DNS over TLS) protocol, with privacy-respecting providers configured;
  - Configures Chromium to use Secure DNS over DoH (DNS over HTTPS) by setting the DoH address of the AdGuard DNS provider, which is relatively private and also blocks known ads and malicious domains.
    - Also enables ECH/ESNI to further strengthen DoH and prevent some ways of leaking the domain names via unencrypted SNI.

* **Package Alternatives:**
  - Replaces the sudo binary with OpenBSD's doas as it has a smaller and safer codebase;
  - Installs uutils-coreutils as a Rust-written reimplementation of the GNU coreutils project;
  - Installs a [security-oriented memory allocator implementation](https://github.com/GrapheneOS/hardened_malloc) and enforces it via /etc/ld.so.preload.

* **File System:**
  - Employs BTRFS as root file system due to its Copy-on-Write (CoW) properties and integrity guarantees against non-malicious file corruption (e.g. power loss);
    - Note: Subvolumes and other BTRFS functionality are intentionally omitted as I do not need them.

### Note
* This script is tailored to my personal needs and my threat model. Exercise caution and adapt it to your preferences and threat model.
 * Consider tweaks such as a more fine-grained disk partition layout with security-related file system flags (e.g. noexec, nosuid) for each mount point according to your preferences.
