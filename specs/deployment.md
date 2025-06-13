# Deployment Strategy

## Overview

This document outlines the deployment strategy for the Cassie Box NixOS system using deploy-rs. The goal is to establish a reliable, automated deployment process that ensures system consistency and provides easy rollback capabilities.

## Requirements

- SSH access to the target machine
- Nix with flakes enabled
- deploy-rs installed locally
- Proper network connectivity between deployment machine and target

## Implementation Steps

### 1. Add deploy-rs to flake.nix

```nix
{
  inputs = {
    deploy-rs.url = "github:serokell/deploy-rs";
    # ... other inputs
  };
}
```

### 2. Configure deploy-rs in flake.nix

Add the following to your flake.nix outputs:

```nix
deploy = {
  nodes = {
    "cassie-box" = {
      hostname = "cassie-box";  # or IP address
      profiles = {
        system = {
          sshUser = "izzy";  # or appropriate user
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations."cassie-box";
        };
      };
    };
  };
};
```

### 3. Create Deployment Script

Create a deployment script at `scripts/deploy.sh`:

```bash
#!/usr/bin/env bash
set -e

# Deploy to all nodes
deploy .#cassie-box
```

### 4. Deployment Workflow

1. Make changes to the NixOS configuration
2. Test changes locally using `nixos-rebuild build-vm`
3. Commit changes to version control
4. Run deployment script
5. Verify deployment success

### 5. Rollback Procedures

deploy-rs maintains a history of deployments. To rollback:

```bash
# List available generations
deploy-rs list-generations .#cassie-box

# Rollback to specific generation
deploy-rs rollback .#cassie-box --to <generation>
```

## Security Considerations

1. SSH keys should be used for authentication
2. Deploy user should have limited sudo privileges
3. Consider using deploy-rs's built-in secrets management

## Monitoring and Logging

1. Deploy-rs provides deployment logs
2. Consider integrating with existing monitoring solution
3. Set up alerts for failed deployments

## Best Practices

1. Always test configurations locally first
2. Keep deployment scripts in version control
3. Document any manual steps required
4. Maintain a deployment history
5. Regular backup of the system state

## Troubleshooting

Common issues and solutions:

1. SSH Connection Issues
   - Verify SSH configuration
   - Check network connectivity
   - Ensure proper permissions

2. Build Failures
   - Check system resources
   - Verify all dependencies
   - Review build logs

3. Activation Failures
   - Check system requirements
   - Verify configuration syntax
   - Review activation logs

## Future Improvements

1. Automated testing before deployment
2. Integration with CI/CD pipeline
3. Automated backup before deployment
4. Multi-node deployment support
5. Custom deployment hooks

## Automated Deployments

### GitHub Actions Integration

deploy-rs can be integrated with GitHub Actions to automatically deploy changes when they are pushed to specific branches. Here's an example workflow configuration:

```yaml
# .github/workflows/deploy.yml
name: Deploy NixOS Configuration

on:
  push:
    branches:
      - main  # or your default branch
  workflow_dispatch:  # allows manual triggering

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Nix
        uses: DeterminateSystems/nix-installer-action@main

      - name: Setup deploy-rs
        run: nix profile install github:serokell/deploy-rs

      - name: Deploy
        env:
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
          SSH_HOST: ${{ secrets.SSH_HOST }}
        run: |
          mkdir -p ~/.ssh
          echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -H $SSH_HOST >> ~/.ssh/known_hosts
          deploy .#cassie-box
```

### Required Secrets

The following secrets need to be configured in your GitHub repository:

1. `SSH_PRIVATE_KEY`: The private SSH key for deployment
2. `SSH_HOST`: The hostname or IP of your NixOS server

### Security Considerations

1. Use repository secrets for sensitive information
2. Limit the SSH key's permissions to only what's needed for deployment
3. Consider using deploy-rs's built-in secrets management
4. Use branch protection rules to control when deployments can occur

### Alternative CI/CD Options

1. **GitLab CI/CD**
   ```yaml
   deploy:
     image: nixos/nix:latest
     script:
       - nix profile install github:serokell/deploy-rs
       - deploy .#cassie-box
   ```

2. **Drone CI**
   ```yaml
   pipeline:
     deploy:
       image: nixos/nix
       commands:
         - nix profile install github:serokell/deploy-rs
         - deploy .#cassie-box
   ```

3. **Local Git Hooks**
   ```bash
   # .git/hooks/post-commit
   #!/bin/bash
   if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]; then
     ./scripts/deploy.sh
   fi
   ```

### Best Practices for Automated Deployments

1. **Branch Strategy**
   - Use feature branches for development
   - Only deploy from main/master branch
   - Require pull request reviews before merging

2. **Testing**
   - Run `nixos-rebuild build-vm` in CI before deployment
   - Test configuration changes in a staging environment
   - Use deploy-rs's dry-run feature

3. **Monitoring**
   - Set up deployment notifications
   - Monitor deployment logs
   - Configure rollback triggers for failed deployments

4. **Security**
   - Rotate deployment keys regularly
   - Use deploy-rs's built-in secrets management
   - Implement IP restrictions for deployment access

### Troubleshooting Automated Deployments

1. **SSH Connection Issues**
   - Verify SSH key permissions
   - Check network connectivity
   - Ensure CI environment has proper access

2. **Build Failures**
   - Check CI logs for detailed error messages
   - Verify all dependencies are available
   - Test builds locally before pushing

3. **Deployment Failures**
   - Review deploy-rs logs
   - Check system resources on target
   - Verify configuration syntax

## Local Deployment Service

Instead of using external CI/CD, we can set up a systemd service on the NixOS machine itself to handle deployments. This approach is more secure as it doesn't require public access to the machine.

### Systemd Service Configuration

```nix
# nixos/modules/services/deploy.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.mySystem.services.deploy;
in
{
  options.mySystem.services.deploy = {
    enable = mkEnableOption "automatic deployment service";
    interval = mkOption {
      type = types.str;
      default = "5m";
      description = "How often to check for updates";
    };
    repo = mkOption {
      type = types.str;
      description = "Git repository URL";
    };
    branch = mkOption {
      type = types.str;
      default = "main";
      description = "Branch to track";
    };
    user = mkOption {
      type = types.str;
      description = "User to run the deployment as";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.deploy = {
      description = "Automatic NixOS deployment service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        WorkingDirectory = "/etc/nixos";
        ExecStart = "${pkgs.writeScript "deploy.sh" ''
          #!${pkgs.bash}/bin/bash
          set -e

          # Fetch latest changes
          git fetch origin

          # Check if we need to update
          if [[ $(git rev-parse HEAD) != $(git rev-parse origin/${cfg.branch}) ]]; then
            echo "Changes detected, deploying..."

            # Pull changes
            git pull origin ${cfg.branch}

            # Deploy
            ${pkgs.deploy-rs}/bin/deploy .#cassie-box

            # Notify on success
            echo "Deployment completed successfully"
          else
            echo "No changes detected"
          fi
        ''}";
      };
    };

    systemd.timers.deploy = {
      description = "Timer for automatic NixOS deployment";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:*:0/5";  # Every 5 minutes
        AccuracySec = "1m";
      };
    };
  };
}
```

### Usage

1. Enable the service in your NixOS configuration:
   ```nix
   mySystem.services.deploy = {
     enable = true;
     repo = "https://github.com/yourusername/cassie-box.git";
     user = "izzy";  # or appropriate user
   };
   ```

2. Ensure the deployment user has:
   - SSH access to the repository
   - Necessary sudo privileges
   - Proper git configuration

### Security Considerations

1. **Repository Access**
   - Use SSH keys for repository access
   - Consider using deploy keys with read-only access
   - Store keys in a secure location

2. **User Permissions**
   - Limit the deployment user's sudo access
   - Use `sudoers.d` to restrict commands
   - Consider using `nixos-rebuild` with specific flags

3. **Network Security**
   - No need for public access
   - Can use internal network only
   - Consider using a VPN for remote access

### Monitoring and Logging

1. **Systemd Journal**
   ```bash
   # View deployment logs
   journalctl -u deploy.service

   # Follow deployment logs
   journalctl -u deploy.service -f
   ```

2. **Deployment Notifications**
   - Can be integrated with systemd's notification system
   - Can send emails or use other notification methods
   - Can log to a central logging system

### Best Practices

1. **Error Handling**
   - Service includes error checking
   - Failed deployments are logged
   - Consider adding rollback capabilities

2. **Resource Management**
   - Service runs at configurable intervals
   - Can be adjusted based on system load
   - Includes basic resource limits

3. **Maintenance**
   - Regular key rotation
   - Log rotation
   - Service health monitoring

### Troubleshooting

1. **Service Issues**
   - Check systemd status: `systemctl status deploy.service`
   - Verify user permissions
   - Check git configuration

2. **Deployment Failures**
   - Review deployment logs
   - Check system resources
   - Verify configuration syntax

3. **Network Issues**
   - Verify repository access
   - Check DNS resolution
   - Ensure proper network configuration
