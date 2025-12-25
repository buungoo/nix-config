SOPS_FILE := "../nix-secrets/.sops.yaml"

# Define path to helpers
export HELPERS_PATH := justfile_directory() + "/nixos-installer/scripts/helpers.sh"

# default recipe to display help information
default:
  @just --list

# Run a flake check on the config
check ARGS="":
	NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure --keep-going --show-trace {{ARGS}}

# Rebuild the system
rebuild HOST="nas0":
  sudo nixos-rebuild switch --flake .#{{HOST}}

# Update the flake
update:
  nix flake update

# Update and then rebuild
rebuild-update HOST="nas0": update
  just rebuild {{HOST}}

# Git diff the entire repo except for flake.lock
diff:
  git diff ':!flake.lock'

# Generate a new age key
age-key:
  nix-shell -p age --run "age-keygen"

# Build a custom ISO image for installing new systems
iso:
  rm -rf result
  nix build --impure .#nixosConfigurations.iso.config.system.build.isoImage && ln -sf result/iso/*.iso latest.iso
  @echo "ISO built successfully! Available at: latest.iso"

# Install the latest ISO to a flash drive
flash-iso DRIVE: iso
  @echo "WARNING: This will erase all data on {{DRIVE}}"
  @echo "Press Ctrl+C to cancel, or Enter to continue..."
  @read
  sudo dd if=latest.iso of={{DRIVE}} bs=4M status=progress oflag=sync
  sync
  @echo "ISO written to {{DRIVE}} successfully!"

# Format nix files
fmt:
  nix fmt

# Rekey all secrets in nix-secrets
rekey:
  #!/usr/bin/env bash
  cd ../nix-secrets
  find sops -type f -name "*.yaml" -exec sops updatekeys {} \;
  echo "All secrets rekeyed successfully"

# Check if SOPS secrets are working
check-sops:
  @systemctl --quiet is-active sops-nix && echo "✓ SOPS is running" || echo "✗ SOPS is not running"
