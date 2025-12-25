# NixOS Installer

Lightweight flake for bootstrapping new hosts. Uses a two-phase approach:

1. **Phase 1: Minimal Install** - Basic NixOS with SSH and secrets access
2. **Phase 2: Full Config** - Deploy full configuration after boot

## Prerequisites

- Established machine with nix and flakes enabled
- Target machine booted into NixOS installer ISO (use `just iso`)
- SSH access to target machine
- nix-secrets repository configured

## Quick Start

1. **Prepare host config:**
   ```bash
   mkdir -p hosts/nixos/newhost
   # Create default.nix (see existing hosts)
   ```

   Add to `nixos-installer/flake.nix`:
   ```nix
   newhost = newConfig "newhost" "/dev/sda" 16 false;
   #                   ^name     ^disk     ^swap ^luks
   ```

2. **Boot target machine:**
   ```bash
   sudo passwd  # Set root password
   ip addr show  # Check IP
   sudo systemctl start sshd
   ```

3. **Run bootstrap:**
   ```bash
   ./scripts/bootstrap-nixos.sh \
     -n newhost \
     -d 192.168.1.100 \
     -k ~/.ssh/id_ed25519
   ```

   For multiple LUKS drives:
   ```bash
   ./scripts/bootstrap-nixos.sh \
     -n newhost \
     -d 192.168.1.100 \
     -k ~/.ssh/id_ed25519 \
     --luks-secondary-drive-labels "cryptdata1,cryptdata2"
   ```

## Disk Templates

Located in `hosts/common/disks/`:

- **btrfs-simple.nix** - Basic btrfs with subvolumes (`@root`, `@nix`, optional `@swap`)
- **btrfs-luks.nix** - LUKS encrypted btrfs with same subvolume structure

Parameters: `disk`, `withSwap`, `swapSize`

## Custom ISO

```bash
just iso  # Build
just iso-install /dev/sdX  # Write to USB
```

Includes: SSH enabled, latest kernel, neovim, git, sops/age, disk tools

## LUKS Secondary Drives

Automatically unlock secondary drives after unlocking main drive:

```bash
./scripts/bootstrap-nixos.sh \
  -n nas0 \
  -d 192.168.1.100 \
  -k ~/.ssh/key \
  --luks-secondary-drive-labels "cryptdata1,cryptdata2"
```

Change passphrase after install:
```bash
sudo cryptsetup luksChangeKey /dev/<main-partition>
sudo cryptsetup luksChangeKey /dev/<secondary-partition> /luks-secondary-unlock.key
```

## Post-Installation

```bash
ssh bungo@<target-ip>
just check-sops  # Verify secrets
df -h && lsblk   # Check disk layout
```

## Troubleshooting

**SSH issues:**
```bash
sudo systemctl status sshd
ssh root@<target-ip>
```

**SOPS issues:**
```bash
ls -la /etc/ssh/ssh_host_ed25519_key
ssh-keyscan -t ssh-ed25519 localhost 2>&1 | grep ssh-ed25519 | cut -f2- -d" " | ssh-to-age
cd ../nix-secrets && just rekey
```

**Disko issues:**
```bash
lsblk
df -h
sudo umount /mnt/*
```

## Files

- `flake.nix` - Minimal bootstrap flake
- `minimal-configuration.nix` - Lightweight NixOS config
- `../hosts/common/disks/` - Disk templates
- `../scripts/bootstrap-nixos.sh` - Automated bootstrap script
