#!/usr/bin/env bash
set -euo pipefail

# Remote installation script for NixOS hosts (builds on target)
# Use this when installing from a non-x86_64-linux machine (e.g., macbook)
# Assumes you've already:
# - Generated host SSH key
# - Added age key to .sops.yaml
# - Rekeyed secrets
# - Booted target machine with custom ISO

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function error() { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
function info() { echo -e "${GREEN}$*${NC}"; }
function warn() { echo -e "${YELLOW}$*${NC}"; }

# Usage
function usage() {
  cat <<EOF
Usage: $0 HOSTNAME IP HOST_SSH_KEY [SSH_PUB_KEY]

Install NixOS on a target machine using nixos-anywhere (builds on remote).

ARGUMENTS:
  HOSTNAME        Hostname of the target machine (e.g., nas1)
  IP              IP address of the target machine
  HOST_SSH_KEY    Path to the pre-generated SSH host key (private key)
  SSH_PUB_KEY     Path to your SSH public key for root access (default: ~/.ssh/id_ed25519.pub)

EXAMPLE:
  $0 nas1 192.168.x.x ../nix-secrets/keys/nas1_host_key
  $0 nas1 192.168.x.x ../nix-secrets/keys/nas1_host_key ~/.ssh/other_key.pub

PREREQUISITES:
  1. Generate host SSH key: ssh-keygen -t ed25519 -f keys/nas1_host_key -N ""
  2. Convert to age: cat keys/nas1_host_key.pub | ssh-to-age
  3. Add age key to nix-secrets/.sops.yaml
  4. Rekey secrets: cd nix-secrets && just rekey
  5. Update flake: nix flake update nix-secrets
  6. Boot target machine with ISO
EOF
  exit 1
}

# Parse arguments
if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  usage
fi

HOSTNAME=$1
TARGET_IP=$2
HOST_KEY=$3
SSH_PUB_KEY="${4:-$HOME/.ssh/id_ed25519.pub}"

# Validate arguments
[ -z "$HOSTNAME" ] && error "HOSTNAME is required"
[ -z "$TARGET_IP" ] && error "IP is required"
[ -z "$HOST_KEY" ] && error "HOST_SSH_KEY is required"
[ -f "$HOST_KEY" ] || error "Host key not found: $HOST_KEY"
[ -f "${HOST_KEY}.pub" ] || error "Host public key not found: ${HOST_KEY}.pub"
[ -f "$SSH_PUB_KEY" ] || error "SSH public key not found: $SSH_PUB_KEY"

info "Installing NixOS on $HOSTNAME at $TARGET_IP"
info "Using host SSH key: $HOST_KEY"
info "Using SSH public key: $SSH_PUB_KEY"

# Create temp directory for host key
TEMP=$(mktemp -d)
trap "rm -rf $TEMP" EXIT

# Prepare host key for nixos-anywhere
info "Preparing SSH host key..."
mkdir -p "$TEMP/etc/ssh"
cp "$HOST_KEY" "$TEMP/etc/ssh/ssh_host_ed25519_key"
cp "${HOST_KEY}.pub" "$TEMP/etc/ssh/ssh_host_ed25519_key.pub"
chmod 600 "$TEMP/etc/ssh/ssh_host_ed25519_key"

# Add SSH public key to root's authorized_keys
info "Adding SSH public key to root's authorized_keys..."
mkdir -p "$TEMP/root/.ssh"
cp "$SSH_PUB_KEY" "$TEMP/root/.ssh/authorized_keys"
chmod 700 "$TEMP/root/.ssh"
chmod 600 "$TEMP/root/.ssh/authorized_keys"

# Configure SSH to use host key for GitHub
info "Configuring SSH to use host key for GitHub authentication..."
cat > "$TEMP/root/.ssh/config" << 'EOF'
Host github.com
  IdentityFile /etc/ssh/ssh_host_ed25519_key
EOF
chmod 600 "$TEMP/root/.ssh/config"

# Clear known_hosts for this IP
info "Clearing old SSH fingerprints for $TARGET_IP..."
ssh-keygen -R "$TARGET_IP" 2>/dev/null || true

# Add target to known_hosts
info "Adding target to known_hosts..."
ssh-keyscan -H "$TARGET_IP" >> ~/.ssh/known_hosts 2>/dev/null || true

# Run nixos-anywhere
info "Running nixos-anywhere..."
info "This will WIPE ALL DATA on the target machine!"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  error "Installation cancelled"
fi

SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- \
  --extra-files "$TEMP" \
  --build-on-remote \
  --flake ".#${HOSTNAME}" \
  "root@${TARGET_IP}"

info "Installation complete!"
info ""
info "Next steps:"
info "1. The machine will reboot automatically"
info "2. SSH into the machine: ssh root@${TARGET_IP}"
info "3. Clone your config: git clone <your-repo> ~/.nixos/nix-config"
info "4. Build full config: cd ~/.nixos/nix-config && nixos-rebuild switch --flake .#${HOSTNAME}"
