#!/usr/bin/env bash
#
# Build installation ISO for cassie-box
#
# Usage: ./build-iso.sh [output-dir]
#

set -euo pipefail

OUTPUT_DIR="${1:-./result}"

echo "=== Building cassie-box installation ISO ==="

# Build the ISO
echo "Building ISO image..."
nix build .#packages.x86_64-linux.iso -o "$OUTPUT_DIR"

if [ -L "$OUTPUT_DIR" ]; then
  ISO_PATH=$(readlink -f "$OUTPUT_DIR")
  echo "=== ISO built successfully! ==="
  echo "ISO location: $ISO_PATH"
  echo "ISO size: $(du -h "$ISO_PATH" | cut -f1)"
  echo ""
  echo "To write to USB:"
  echo "  sudo dd if='$ISO_PATH' of=/dev/sdX bs=4M status=progress"
  echo ""
  echo "Or use a tool like balenaEtcher, Rufus, or Ventoy"
else
  echo "Failed to build ISO"
  exit 1
fi
