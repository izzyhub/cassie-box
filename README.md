# The box for Cassie

[![NixOS](https://img.shields.io/badge/NIXOS-5277C3.svg?style=for-the-badge&logo=NixOS&logoColor=white)](https://nixos.org)
[![NixOS](https://img.shields.io/badge/NixOS-23.11-blue?style=for-the-badge&logo=nixos&logoColor=white)](https://nixos.org)
[![MIT License](https://img.shields.io/github/license/truxnell/nix-config?style=for-the-badge)](https://github.com/truxnell/nix-config/blob/ci/LICENSE)

[![renovate](https://img.shields.io/badge/renovate-enabled-%231A1F6C?logo=renovatebot)](https://developer.mend.io/github/truxnell/nix-config)
[![built with garnix](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fgarnix.io%2Fapi%2Fbadges%2Ftruxnell%2Fnix-config%3Fbranch%3Dmain)](https://garnix.io)
![Code Comprehension](https://img.shields.io/badge/Code%20comprehension-26%25-red)

Leveraging nix, nix-os and other funny magic man words to apply machine and home configurations

[Repository Documentation](https://truxnell.github.io/nix-config/)

## Background

Largely inspired/stolen from [Truxnell](https://github.com/truxnell/nix-config)

## Getting started

To Install

```
# nixos-rebuild switch --flake github:truxnell/nix-config#HOST
```

## Goals

- [ ] Learn nix
- [ ] A box to make watching stuff together easier/less prone to network issues
- [ ] Hosting with local services for Cassie like an image backup and a password manager.
- [ ] Figure out how to use this to eventually manage my own home infrastructure
- [X] handle secrets - decide between sweet and simple SOPS or re-use my doppler setup.

## TODO

- [ ] Update Documentation!
- [ ] Add taskfiles

## Checklist

### Adding new node

- Ensure secrets are grabbed from node and all sops re-encrypted with task sops:re-encrypt
- Add to relevant github action workflows
- Add to .github/settings.yaml for PR checks

## Applying configuration changes on a local machine can be done as follows:

```sh
cd ~/dotfiles
sudo nixos-rebuild switch --flake .
# This will automatically pick the configuration name based on the hostname
```

Applying configuration changes to a remote machine can be done as follows:

```sh
cd ~/dotfiles
nixos-rebuild switch --flake .#nameOfMachine --target-host machineToSshInto --use-remote-sudo
```

## Hacking at nix files

Eval config to see what keys are being set.

```bash
nix eval .#nixosConfigurations.rickenbacker.config.security.sudo.WheelNeedsPassword
nix eval .#nixosConfigurations.rickenbacker.config.mySystem.security.wheelNeedsPassword
```

And browsing whats at a certain level in options - or just use [nix-inspect](https://github.com/bluskript/nix-inspect) TUI

```bash
nix eval .#nixosConfigurations.rickenbacker.config.home-manager.users.truxnell --apply builtins.attrNames --json
```

Quickly run a flake to see what the next error message is as you hack.

```bash
nixos-rebuild dry-run --flake . --fast --impure
```

## Links & References

- [Misterio77/nix-starter-config](https://github.com/Misterio77/nix-starter-configs)
- [billimek/dotfiles](https://github.com/billimek/dotfiles/)
- [truxnell/nix-config](https://github.com/truxnell/nix-config/)
- [Erase your Darlings](https://grahamc.com/blog/erase-your-darlings/)
- [NixOS Flakes](https://www.tweag.io/blog/2020-07-31-nixos-flakes/)
