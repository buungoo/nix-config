# NixOS Installer

Self-contained NixOS installation system for established hosts. Everything you need in one directory.

## Quick Start

```bash
cd nixos-installer

# 1. Build the ISO
nix build .#iso
# ISO will be at: result/iso/*.iso

# 2. Write to USB
dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress

# 3. Generate host keys (do this BEFORE installation)
ssh-keygen -t ed25519 -f host_key -C "root@<host>" -N ""
ssh-keygen -t ed25519 -f user_host_key -C "user@<host>" -N ""

# 4. Add age keys to .sops.yaml

# 5. Rekey secrets

# 6. Boot target machine with ISO
# (Root password is "nixos")

# 7. Install
./install.sh <host> <ip> <host_key>
```
