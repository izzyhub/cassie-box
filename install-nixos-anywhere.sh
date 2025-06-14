#!/usr/bin/env bash
#
# Install cassie-box using nixos-anywhere
#
# Usage: ./install-nixos-anywhere.sh <target-host>
# Example: ./install-nixos-anywhere.sh root@192.168.1.100
#

set -euo pipefail

TARGET_HOST="${1:-}"
FLAKE_ATTR="${2:-cassie-box-installer}"

if [ -z "$TARGET_HOST" ]; then
  echo "Usage: $0 <target-host> [flake-attr]"
  echo "Example: $0 root@192.168.1.140"
  echo "Example: $0 root@192.168.1.140 cassie-box-installer"
  exit 1
fi

echo "=== Installing cassie-box to $TARGET_HOST ==="
echo "Using flake attribute: $FLAKE_ATTR"

# Check if nixos-anywhere is available
if ! command -v nixos-anywhere >/dev/null 2>&1; then
  echo "nixos-anywhere not found. Installing..."
  nix profile install github:nix-community/nixos-anywhere
fi

# Optional: add SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_ed25519.pub ]; then
  echo "No SSH key found. You may want to:"
  echo "1. Generate an SSH key: ssh-keygen -t ed25519"
  echo "2. Add it to nixos/profiles/installer.nix"
  echo "3. Rebuild the installer configuration"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo "Starting installation..."
nixos-anywhere \
  --flake ".#$FLAKE_ATTR" \
  "$TARGET_HOST"

echo "=== Installation complete! ==="
echo "The system should now be accessible at: $TARGET_HOST"
echo "You can now deploy the full configuration with:"
echo "  task nix:deploy-single"
