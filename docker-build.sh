#!/usr/bin/env bash
#
# Build cassie-box configurations using Docker
#

set -euo pipefail

COMMAND="${1:-help}"

case "$COMMAND" in
  "iso")
    echo "Building ISO in Docker container..."
    docker run --rm \
      --platform linux/amd64 \
      --privileged \
      --security-opt seccomp=unconfined \
      -v "$(pwd):/workspace" \
      -w /workspace \
      nixos/nix:latest \
      sh -c "
        nix --extra-experimental-features 'nix-command flakes' \
        build .#packages.x86_64-linux.iso -o ./result-iso
      "
    ;;
  "check")
    echo "Checking flake in Docker container..."
    docker run --rm \
      --platform linux/amd64 \
      --privileged \
      --security-opt seccomp=unconfined \
      -v "$(pwd):/workspace" \
      -w /workspace \
      nixos/nix:latest \
      sh -c "
        nix --extra-experimental-features 'nix-command flakes' \
        flake check --show-trace
      "
    ;;
  "shell")
    echo "Starting Nix shell in Docker container..."
    docker run --rm -it \
      --platform linux/amd64 \
      -v "$(pwd):/workspace" \
      -w /workspace \
      nixos/nix:latest \
      sh -c "
        nix --extra-experimental-features 'nix-command flakes' \
        develop
      "
    ;;
  "help"|*)
    echo "Usage: $0 <command>"
    echo "Commands:"
    echo "  iso    - Build installation ISO"
    echo "  check  - Check flake configuration"
    echo "  shell  - Start development shell"
    ;;
esac
