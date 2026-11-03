#!/usr/bin/env bash
# Deploy the local flake to every host in nixosConfigurations, except those in
# `skip`. Same -r and DEPLOY_DOMAIN behaviour as update-single-machine.sh.
set -euo pipefail

skip=(
    # nixos-anywhere install target, not a running machine.
    "cassie-box-installer"
)

args=()
while getopts ":r" option; do
    case $option in
    r) args+=(-r) ;;
    *)
        echo "usage: $0 [-r]" >&2
        exit 2
        ;;
    esac
done

mapfile -t hosts < <(nix eval --raw .#nixosConfigurations --apply 'c: builtins.concatStringsSep "\n" (builtins.attrNames c)')

for host in "${hosts[@]}"; do
    if [[ " ${skip[*]} " == *" $host "* ]]; then
        continue
    fi
    "$(dirname "$0")/update-single-machine.sh" "${args[@]}" "$host"
    echo
done
