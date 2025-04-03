**Note:** This tool must be used with the linux-hardened patchset, which exposes the kernel.deny_new_usb sysctl flag.

### Build
`make clean && make` will compile the binary.
Then, you should copy the binary to `/usr/local/bin/allow_new_usb_tmp` and then turn it into a SUID binary with `chmod +s /usr/local/bin/allow_new_usb_tmp`.

### Security considerations
- SUID binaries are often a security concern. This binary is quite safe because it takes no user input, all it does is strictly set the kernel.deny_new_usb flag to 0 for 30 seconds and then set it back to 1. Doing so, you can create a keyboard shortcut to call this binary in order to allow USB for 30 seconds when you want to, without requiring root privileges to toggle the flag. Also, this binary is compiled with most security mitigations enabled, including SSP, canaries, PIE, NX, Full RELRO, FORTIFY, clang CFI, Intel IBT, and Intel Shadow Stack;
- SUID binaries are used in this case because I want to be able to toggle this specific flag without needing to change into my privileged user, as I typically use a unprivileged user which isn't even part of the wheel group. 

`kernel.deny_new_usb` serves to protect against attackers with physical access who do not have access to the shell. If someone has access to your shell, this person being able to toggle that flag via this SUID binary is the least of your concerns.
