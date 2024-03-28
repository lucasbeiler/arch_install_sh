## Summary and main features of this script
This script facilitates the installation of a security-focused Arch Linux environment. Arch Linux is a good distribution, with a high amount of packages passing build reproducibility tests, providing transparency in trusting that the distributed binaries match the software source code. Also, maintainers keep good security practices and compile their packages with proper mitigations enforced by compiler flags, they also do a pretty good job at keeping packages closer to upstream software.

* **Secure Boot:**
  - Bootloader, kernel, microcode and initrd are bundled into the Unified Kernel Image. Then, this image is authenticated by Secure Boot, at every boot, ensuring the authenticity and integrity of the whole boot chain.

* **Full Disk Encryption with LUKS:**
  - Keys are securely stored in the TPM 2.0 chip, granting access only under strict authenticity conditions. This setup ensures decryption of the disk only when hardware, firmware, and Secure Boot configuration are intact and in a known-good state;
  - Secure Boot + LUKS + TPM 2.0 are useful to enhance the boot process, making it more secure and tamper-evident. A tampered firmware and/or boot chain won't successfully boot the OS;
  - Additionally, each user has a home directory encrypted with LUKS via systemd-homed, this time with a password.

* **Kernel:**
  - The linux-hardened kernel, which features security-focused patches and safer default configurations;
  - The script further secures the kernel by blacklisting old and unused modules, and by applying additional secure configurations via sysctl and boot parameters.

* **Filesystem:**
  - Employs BTRFS as the root filesystem for its Copy-on-Write (CoW) properties and integrity guarantees against benign file corruption (e.g., power loss);
  - Note: Subvolumes or other BTRFS features are intentionally omitted as I do not need them.

* **Stateful Firewall:**
  - iptables rules are used in order to implement a stateful firewall, allowing only outgoing connections and dropping packets from incoming connections initiated by the other end.

* **Secure DNS:**
  - Configures secure DNS using dnscrypt-proxy, operating over the DoH (DNS over HTTPS) protocol, with privacy-respecting providers set up.

* **Package Alternatives:**
  - Replaces the commonly used sudo binary with OpenBSD's doas for a smaller, safer codebase;
  - Replaces GNU Coreutils with uutils-coreutils, a memory safe alternative;
  - Installs a security-oriented malloc implementation loaded via LD_PRELOAD. This implementation is used by every binary respecting LD_PRELOAD.

### Note
* This script is tailored to my personal needs and threat model. Exercise caution and adapt it to your preferences and threat model.
  * Consider adjustments such as a more fine-grained disk partition layout with security-related filesystem flags (e.g., noexec, nosuid) for each mount point according to your preferences.
