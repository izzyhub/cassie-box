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
    # move ssh keys

    systemd.tmpfiles.rules = [
      # Fix permissions for systemd DynamicUser services
      "d /var/lib/private 0700 root root -"
    ] ++ (mkIf config.services.openssh.enable [
      # Ensure SSH directory exists in persistent storage
      "d ${cfg.persistPath}/etc/ssh 0755 root root -"
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
