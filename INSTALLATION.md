# Cassie-Box Installation Guide

This guide covers automated installation methods for the cassie-box NixOS configuration.

## Prerequisites

- A target machine with UEFI boot capability
- Network connectivity for both build machine and target
- SSH access to target machine (for nixos-anywhere method)

## Method 1: nixos-anywhere (Remote Installation)

This method installs directly to a target machine over SSH.

### Setup

1. **Prepare SSH access**: Ensure you can SSH to the target machine as root
2. **Add your SSH key**: Edit `nixos/profiles/installer.nix` and add your SSH public key:
   ```nix
   users.users.root.openssh.authorizedKeys.keys = [
     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your-key-here"
   ];
   ```

### Installation

Using the task runner:
```bash
task nix:install-anywhere target=root@192.168.1.100
```

Or directly with the script:
```bash
./install-nixos-anywhere.sh root@192.168.1.100
```

## Method 2: Installation ISO

This method creates a bootable ISO that automatically installs the system.

### Build ISO

Using the task runner:
```bash
task nix:build-iso
```

Or directly with the script:
```bash
./build-iso.sh
```

### Write to USB

```bash
# Find your USB device
lsblk

# Write ISO to USB (replace /dev/sdX with your device)
sudo dd if=./result-iso of=/dev/sdX bs=4M status=progress sync
```

### Boot and Install

1. Boot from the USB drive
2. The system will automatically start the installation process
3. Follow any on-screen prompts

## Post-Installation

After installation completes:

1. **Update SSH configuration**: The installer uses a temporary root password. Update your SSH keys and disable password auth:
   ```bash
   # SSH to the new system
   ssh root@cassie-box

   # Deploy the full configuration
   task nix:deploy-single host=cassie-box
   ```

2. **Verify services**: Check that all expected services are running:
   ```bash
   systemctl status
   ```

## Storage Layout

The automated installation creates:

- **Boot partition**: 1GB EFI System Partition on main SSD
- **Root partition**: 50% of main SSD (ext4)
- **Data partition 1**: 50% of main SSD (ext4, mounted at `/mnt/data1`)
- **Data partition 2**: 100% of NVMe drive (ext4, mounted at `/mnt/data2`)
- **MergerFS pool**: Combined storage at `/mnt/data`

## Disk Configuration

The installation targets these specific devices:
- Main SSD: `/dev/disk/by-id/ata-CT2000BX500SSD1_2425E8B9A602`
- NVMe drive: `/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_241958806974`

**⚠️ Warning**: The installation will completely wipe these drives. Ensure you have backups of any important data.

## Troubleshooting

### SSH Access Issues

If you can't SSH to the target machine:
1. Ensure the machine is booted from a live NixOS environment
2. Set a root password: `sudo passwd root`
3. Enable SSH: `sudo systemctl start sshd`

### Disk Detection Issues

If the installation fails due to disk detection:
1. Check available disks: `lsblk` or `ls -la /dev/disk/by-id/`
2. Update disk IDs in `nixos/hosts/cassie-box/disko.nix`
3. Rebuild the installer configuration

### Network Issues

- Ensure NetworkManager is enabled: `sudo systemctl start NetworkManager`
- Connect to WiFi: `nmcli device wifi connect SSID password PASSWORD`

## Advanced Configuration

### Custom Disk Layout

To modify the partitioning scheme, edit `nixos/hosts/cassie-box/disko.nix` and rebuild:

```bash
# After editing disko.nix
nix build .#nixosConfigurations.cassie-box-installer
```

### Adding Encryption

To add disk encryption, modify the disko configuration to include LUKS:

```nix
# Example for encrypted root
root = {
  size = "50%";
  content = {
    type = "luks";
    name = "crypted";
    content = {
      type = "filesystem";
      format = "ext4";
      mountpoint = "/";
    };
  };
};
```

## Security Notes

- The installer profile includes a default root password (`nixos`) for initial access
- SSH password authentication is enabled during installation
- Change these defaults immediately after installation
- Consider using SSH keys only for production deployments
