{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.system.resticBackup;
in
{
  options.mySystem.system.resticBackup = {
    local = {
      enable = mkEnableOption "Local backups" // { default = true; };
      location = mkOption
        {
          type = types.str;
          description = "Location for local backups";
          default = "";
        };
    };
    remote = {
      enable = mkEnableOption "Remote backups" // { default = true; };
      location = mkOption
        {
          type = types.str;
          description = "Location for remote backups";
          default = "";
        };
    };
    mountPath = mkOption
      {
        type = types.str;
        description = "Location for  snapshot mount";
        default = "/mnt/data/nightly_backup";
      };

  };


  config = {

    # Warn if backups are disable and machine isnt a dev box
    warnings = [
      (mkIf (!cfg.local.enable && config.mySystem.purpose != "Development") "WARNING: Local backups are disabled!")
      (mkIf (!cfg.remote.enable && config.mySystem.purpose != "Development") "WARNING: Remote backups are disabled!")
    ];

    sops.secrets = mkIf (cfg.local.enable || cfg.remote.enable) {
      "services/restic/password" = {
        sopsFile = ./secrets.sops.yaml;
        owner = "kah";
        group = "kah";
      };

      "services/restic/env" = {
        sopsFile = ./secrets.sops.yaml;
        owner = "kah";
        group = "kah";
      };
    };


    # useful commands:
    # view snapshots - zfs list -t snapshot

    # below takes a snapshot of the zfs persist volume
    # ready for restic syncs
    # essentially its a nightly rotation of atomic state at 2am.

    # this is the safest option, as if you run restic
    # on live services/databases/etc, you will have
    # a bad day when you try and restore
    # (backing up a in-use file can and will cause corruption)

  };
}
