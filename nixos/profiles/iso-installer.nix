# ISO installer profile - minimal configuration for live ISO
{ config, lib, pkgs, ... }:

{
  # Enable SSH for remote installation
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  # Set root password for installation
  users.users.root.initialPassword = "nixos";

  # Add your SSH keys for passwordless access
  users.users.root.openssh.authorizedKeys.keys = [
    # Add your SSH public key here for nixos-anywhere
    # Example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
  ];

  # Essential packages for installation
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    rsync
    nixos-anywhere
  ];

  # Network configuration for installer
  networking = {
    useDHCP = lib.mkDefault false;
    firewall.allowedTCPPorts = [ 22 ];
    networkmanager.enable = true;
    wireless.enable = false;
  };

  # Basic hardware support
  boot = {
    initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
    kernelModules = [ ];
    extraModulePackages = [ ];
    supportedFilesystems = [ "ntfs" ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  # Installer-specific settings
  system.stateVersion = "23.11";

  # Enable experimental features needed for flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ISO-specific configuration
  isoImage = {
    makeEfiBootable = true;
    makeUsbBootable = true;
  };
}
