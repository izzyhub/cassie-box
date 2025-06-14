# Installer profile for automated installation with nixos-anywhere
{ config, lib, pkgs, ... }:

{
  # Enable SSH for remote installation
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkForce true;
      PermitRootLogin = lib.mkForce "yes";
    };
  };

  # Set root password for installation (change this!)
  users.users.root.initialPassword = "nixos";

  # Add your SSH keys for passwordless access
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGlH7ndB1lbWNBlOFvuPLVFOKbbJDJE4M+oNtEGw0kqi m2-14-mac"
  ];

  # Essential packages for installation
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    rsync
    neovim
  ];

  # Network configuration for installer
  networking = {
    useDHCP = true;
    firewall.allowedTCPPorts = [ 22 ];
  };

  # Installer-specific settings
  system.stateVersion = lib.mkForce "23.11";

  # Enable experimental features needed for flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
