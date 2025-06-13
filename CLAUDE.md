# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NixOS configuration repository for "cassie-box", a home media server and self-hosted services infrastructure. The system manages a comprehensive media stack (Plex, *arr services, downloaders) alongside productivity tools and infrastructure services, all deployed using NixOS containers and services.

## Common Commands

### Development and Testing
```bash
task build               # Build configuration and show differences
task nix:dry-run        # Show what would change without applying
task nix:test           # Test configuration without applying
task test-all           # Run comprehensive testing suite
task check              # Run linting and pre-commit checks
task format             # Format nix files with nixpkgs-fmt
```

### Deployment
```bash
task nix:switch         # Build and apply configuration locally
task nix:deploy-single  # Deploy to remote host
task nix:deploy-all     # Deploy to all configured hosts
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
