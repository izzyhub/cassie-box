# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NixOS configuration repository for "cassie-box", a home media server and self-hosted services infrastructure. The system manages a comprehensive media stack (Plex, *arr services, downloaders) alongside productivity tools and infrastructure services, all deployed using NixOS containers and services.

## Common Commands

**IMPORTANT**: This development machine does not have Nix installed. All configuration testing must be done on the remote cassie-box system via SSH.

### Development and Testing
```bash
# LOCAL COMMANDS (development machine)
task check              # Run linting and pre-commit checks (if available)
task format             # Format nix files with nixpkgs-fmt (if available)

# REMOTE COMMANDS (via SSH to cassie-box)
ssh izzy@cassie-box "sudo nixos-rebuild dry-run --flake /etc/nixos#cassie-box"  # Show what would change
ssh izzy@cassie-box "sudo nixos-rebuild test --flake /etc/nixos#cassie-box"     # Test without switching
ssh izzy@cassie-box "sudo nixos-rebuild switch --flake /etc/nixos#cassie-box"   # Apply changes
```

### Deployment
```bash
task nix:switch         # Build and apply configuration locally
task nix:deploy-single  # Deploy to remote host
task nix:deploy-all     # Deploy to all configured hosts
```

### Installation
```bash
task nix:build-iso      # Build installation ISO
task nix:install-anywhere target=root@192.168.1.100  # Install via nixos-anywhere
./build-iso.sh          # Alternative: build ISO directly
./install-nixos-anywhere.sh root@192.168.1.100       # Alternative: install directly
```

### Secret Management
```bash
task sop:encrypt        # Encrypt new sops secrets
task sop:re-encrypt     # Re-encrypt all secrets after key changes
```

### Testing Environment
```bash
task docker-build       # Build testing container
task docker-test        # Run tests in container
task nixos-test         # Test configuration in VM
```

## Architecture

### Module Organization
- **nixos/modules/nixos/containers/**: Container-based services (Plex, Immich, etc.)
- **nixos/modules/nixos/services/**: Native NixOS services (databases, system services)
- **nixos/hosts/cassie-box/**: Host-specific configuration
- **nixos/profiles/**: Reusable configuration profiles (global, hardware, roles)
- **nixos/home/**: Home-manager configurations per user

### Service Patterns
All services follow a consistent pattern using the `mySystem` namespace:
- Services are enabled via `mySystem.services.<name>.enable = true;`
- Containers automatically integrate with Traefik reverse proxy
- Secrets are managed via SOPS with `.sops.yaml` files alongside service definitions
- Services include built-in backup, monitoring, and homepage integration

### Infrastructure Components
- **Traefik**: Reverse proxy with automatic service discovery
- **SOPS**: Secret encryption using age keys
- **MergerFS**: Storage pooling across multiple drives
- **Containers**: Podman-based container management
- **Monitoring**: Grafana + VictoriaMetrics stack

## Working with Services

### Adding a New Container Service
1. Create module in `nixos/modules/nixos/containers/<service>/`
2. Follow existing patterns from similar services
3. Use `mySystem.services.<name>` options structure
4. Include secrets file if needed: `secrets.sops.yaml`
5. Add to `nixos/modules/nixos/containers/default.nix`

### Adding a New System Service
1. Create module in `nixos/modules/nixos/services/<service>/`
2. Follow the same `mySystem.services.<name>` pattern
3. Add to `nixos/modules/nixos/services/default.nix`

### Managing Secrets
- Secrets are encrypted with SOPS using age keys
- Each service with secrets has a `secrets.sops.yaml` file
- Use `task sop:encrypt` to encrypt new secrets
- Keys are stored in `.sops.yaml` configuration

## Storage Layout
- Root: 1TB partition on main SSD
- Data: MergerFS pool combining:
  - 1TB partition on main SSD (`/mnt/data1`)
  - 2TB NVMe drive (`/mnt/data2`)
- Services store data in `/mnt/data/<service>/`

## Key Files
- `flake.nix`: Main flake configuration
- `Taskfile.yaml`: Task definitions and common commands
- `nixos/hosts/cassie-box/default.nix`: Host configuration
- `nixos/lib/default.nix`: Custom library functions including `mkService`
- `.sops.yaml`: SOPS configuration for secret encryption

## Memories
- Do not disable any services without confirmation
