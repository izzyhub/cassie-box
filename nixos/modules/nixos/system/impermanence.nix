{ lib
, config
, pkgs
, ...
}:
let
  cfg = config.mySystem.system.impermanence;
in
with lib;
{
  options.mySystem.system.impermanence = {
    enable = mkEnableOption "system impermanence";
    rootBlankSnapshotName = lib.mkOption {
      type = lib.types.str;
      default = "blank";
    };
    rootPoolName = lib.mkOption {
      type = lib.types.str;
      default = "rpool/local/root";
    };
    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
    };

  };


  config = lib.mkIf cfg.enable {
    # Create media group for data access
    users.groups.media = {};
    users.users.izzy.extraGroups = [ "media" ];
    users.users.cassie.extraGroups = [ "media" ];

    # move ssh keys

    systemd.tmpfiles.rules = [
      # Fix permissions for systemd DynamicUser services
      "Z /var/lib/private 0700 root root -" # Use Z to recursively fix permissions
    ] ++ (mkIf config.services.openssh.enable [
      # Ensure SSH directory exists in persistent storage
      "d ${cfg.persistPath}/etc/ssh 0755 root root -"
    ]) ++ (mkIf (config.mySystem.dataFolder != null) [
      # Create common data directories with media group ownership
      "d ${config.mySystem.dataFolder} 0775 root media -"
      "d ${config.mySystem.dataFolder}/media 0775 root media -"
      "d ${config.mySystem.dataFolder}/media/music 0775 root media -"
      "d ${config.mySystem.dataFolder}/documents 0775 root media -"
      "d ${config.mySystem.dataFolder}/documents/paperless 0775 root media -"
      "d ${config.mySystem.dataFolder}/documents/paperless/media 0775 root media -"
      "d ${config.mySystem.dataFolder}/documents/paperless/inbound 0775 root media -"
      "d ${config.mySystem.dataFolder}/photos 0775 root media -"
      "d ${config.mySystem.dataFolder}/photos/immich 0775 root media -"
      "d ${config.mySystem.dataFolder}/torrents 0775 root media -"
      "d ${config.mySystem.dataFolder}/syncthing 0775 root media -"
    ]);

    # Generate SSH host keys in persistent location if they don't exist
    system.activationScripts.sshHostKeys = lib.mkIf config.services.openssh.enable {
      text = ''
        if [ ! -f "${cfg.persistPath}/etc/ssh/ssh_host_ed25519_key" ]; then
          mkdir -p "${cfg.persistPath}/etc/ssh"
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f "${cfg.persistPath}/etc/ssh/ssh_host_ed25519_key" -N ""
          chmod 600 "${cfg.persistPath}/etc/ssh/ssh_host_ed25519_key"
          chmod 644 "${cfg.persistPath}/etc/ssh/ssh_host_ed25519_key.pub"
        fi
        if [ ! -f "${cfg.persistPath}/etc/ssh/ssh_host_rsa_key" ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f "${cfg.persistPath}/etc/ssh/ssh_host_rsa_key" -N ""
          chmod 600 "${cfg.persistPath}/etc/ssh/ssh_host_rsa_key"
          chmod 644 "${cfg.persistPath}/etc/ssh/ssh_host_rsa_key.pub"
        fi
      '';
      deps = [ "specialfs" ];
    };

    environment.persistence."${cfg.persistPath}" = {
      hideMounts = true;
      directories =
        [
          "/var/log" # persist logs between reboots for debugging
          "/var/lib/containers" # cache files (restic, nginx, contaienrs)
          "/var/lib/nixos" # nixos state

        ];
      files = [
        "/etc/machine-id"
        # "/etc/adjtime" # hardware clock adjustment
        # ssh keys
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];
    };

  };
}
