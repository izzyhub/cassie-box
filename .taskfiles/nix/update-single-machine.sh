#!/usr/bin/env bash
# Deploy the local flake to one host over SSH.
#
#   update-single-machine.sh [-r] <host>
#
# <host> is the flake's nixosConfigurations name, and also the SSH target unless
# DEPLOY_DOMAIN is set (then <host>.$DEPLOY_DOMAIN). -r installs as the boot
# generation and reboots instead of switching live.
set -euo pipefail

reboot=0
while getopts ":r" option; do
    case $option in
    r) reboot=1 ;;
    *)
        echo "usage: $0 [-r] <host>" >&2
        exit 2
        ;;
    esac
done
shift $((OPTIND - 1))

host=${1:?usage: $0 [-r] <host>}
target=$host${DEPLOY_DOMAIN:+.$DEPLOY_DOMAIN}

if [ "$reboot" -eq 1 ]; then
    echo "$target with reboot"
    nixos-rebuild boot -j auto --sudo --target-host "$target" --flake ".#$host"
    ssh "$target" 'sudo reboot'
else
    echo "$target"
    nixos-rebuild switch -j auto --sudo --target-host "$target" --flake ".#$host"
fi
