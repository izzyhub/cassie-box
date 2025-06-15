# Converting to tmpfs Impermanence

This document outlines the steps to convert cassie-box from a persistent ext4 root filesystem to tmpfs-based impermanence with ext4 persistent storage.

## Overview

**Current Setup**: Regular ext4 root filesystem (`/`) - everything persists across reboots
**Target Setup**: tmpfs root (`/`) + ext4 persistent storage (`/persist`) - only explicitly configured data survives reboots

## Storage Layout Changes

### Current disko.nix Structure
```nix
root = {
  size = "500G";
  content = {
    type = "filesystem";
    format = "ext4";
    mountpoint = "/";
  };
};
```

### New disko.nix Structure
```nix
persist = {
  size = "500G";
  content = {
    type = "filesystem";
    format = "ext4";
    mountpoint = "/persist";
  };
};
```

### Additional NixOS Configuration
```nix
# Root filesystem as tmpfs
fileSystems."/" = {
  device = "none";
  fsType = "tmpfs";
  options = [ "defaults" "size=8G" "mode=755" ];
};

# Enable impermanence module
mySystem.system.impermanence.enable = true;
```

## Migration Steps

### 1. Backup Everything
```bash
# Backup all service data
rsync -av /var/lib/ backup-location/var-lib/
rsync -av /etc/ backup-location/etc/
rsync -av /home/ backup-location/home/
rsync -av /mnt/data/ backup-location/data/
```

### 2. Update Configuration Files

#### disko.nix
- Change root partition to persistent storage partition
- Ensure adequate tmpfs size (8-16GB recommended)

#### hosts/cassie-box/default.nix
```nix
mySystem.system.impermanence.enable = true;
mySystem.persistentFolder = "/persist";
```

#### Restore impermanence.nix
- Enable the impermanence module in `nixos/modules/nixos/system/default.nix`
- Ensure it properly handles ext4 + tmpfs (not ZFS)

### 3. Service Configuration Updates

Each service needs persistence configured. Example pattern:

```nix
# Service module (e.g., plex.nix)
config = lib.mkIf cfg.enable {
  # Service definition...

  # Persistent storage
  environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
    directories = [
      { directory = appFolder; user = user; group = group; mode = "750"; }
    ];
  };
};
```

### 4. Critical Persistence Requirements

Must be explicitly persisted:
- **SSH host keys**: `/etc/ssh/ssh_host_*`
- **Machine ID**: `/etc/machine-id`
- **All service data**: `/var/lib/*` directories
- **User data**: `/home/*` directories
- **System state**: `/var/lib/nixos`
- **Container data**: `/var/lib/containers`
- **Logs**: `/var/log` (optional)

### 5. Installation Process

Since this changes the root filesystem type, requires complete reinstall:

```bash
# Build new ISO with updated configuration
task nix:build-iso

# Boot from ISO and reinstall
task nix:install-anywhere target=root@cassie-box-ip

# Or use nixos-anywhere directly
./install-nixos-anywhere.sh root@cassie-box-ip
```

### 6. Data Recovery

After installation:
```bash
# Restore service data to persistent locations
rsync -av backup-location/var-lib/ /persist/var/lib/
rsync -av backup-location/home/ /persist/home/
# etc...
```

## Service Migration Checklist

Each service must be verified for proper persistence:

- [ ] **Databases** (PostgreSQL, MariaDB): Data directories persisted
- [ ] **Media Services** (Plex, *arr stack): Configuration and databases persisted
- [ ] **Container Services**: All `/var/lib/containers/storage` persisted
- [ ] **User Authentication**: SSH keys, user home directories
- [ ] **System Services**: Any stateful system services
- [ ] **Custom Configurations**: Any manually created config files

## Testing Strategy

1. **VM Testing**: Test configuration in VM first
2. **Incremental Migration**: Enable impermanence on subset of services
3. **Rollback Plan**: Keep current disk image as backup
4. **Service Validation**: Verify each service starts and functions correctly

## Risks and Considerations

### High Risk
- **Data Loss**: Incorrect persistence configuration can lose data permanently
- **Boot Failure**: tmpfs issues can prevent system boot
- **Service Failure**: Services may fail if persistence is incomplete

### Mitigation
- **Complete Backups**: Full system backup before migration
- **Test Environment**: Validate configuration in test environment
- **Staged Rollout**: Enable impermanence incrementally
- **Recovery Plan**: Maintain ability to boot from backup

## Benefits vs. Drawbacks

### Benefits
- **Clean State**: Every boot starts with clean system
- **Security**: Malware cannot persist across reboots
- **Consistency**: Forces declarative configuration
- **Testing**: Easy to test system changes

### Drawbacks
- **Complexity**: All state must be explicitly managed
- **Performance**: Some overhead from tmpfs and bind mounts
- **Debugging**: More complex troubleshooting
- **Risk**: Higher risk of data loss from misconfiguration

## Recommendation

For a home media server, **persistent ext4 is typically better** because:
- Simpler management and troubleshooting
- Better performance for large media files
- Lower risk of data loss
- Easier backup and recovery

Consider tmpfs impermanence only if:
- You want maximum security (clean slate on reboot)
- You enjoy complex system administration
- You have robust backup/recovery procedures
- You frequently experiment with system configuration

## Recovery Procedures

If impermanence setup fails:
1. Boot from NixOS ISO
2. Mount original ext4 partition
3. Restore from backups
4. Rebuild with persistent configuration
