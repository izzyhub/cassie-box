{ lib
, config
, ...
}:
with lib;
{
  config = {
    # Create media group for data access
    users = {
      groups.media = { };
      users.izzy.extraGroups = [ "media" ];
      users.cassie.extraGroups = [ "media" ];
    };

    # System-wide tmpfiles rules
    systemd.tmpfiles.rules = [
      # Ensure /var/lib/private itself is 0700 root, as systemd DynamicUser expects.
      # Must stay non-recursive (`d`, not `Z`): a recursive chown to root runs on
      # every config switch and takes the state files away from running
      # DynamicUser services (vikunja crashed with "permission denied" after each
      # hourly auto-upgrade).
      "d /var/lib/private 0700 root root -"
    ] ++ (optionals (config.mySystem.dataFolder != null) [
      # Create common data directories with media group ownership
      "d ${config.mySystem.dataFolder} 0775 root media -"
      "d ${config.mySystem.dataFolder}/media 0775 root media -"
      "d ${config.mySystem.dataFolder}/media/music 0775 root media -"
      "d ${config.mySystem.dataFolder}/documents 0775 root media -"
      "d ${config.mySystem.dataFolder}/documents/paperless 0775 root media -"
      "d ${config.mySystem.dataFolder}/photos 0775 root media -"
      "d ${config.mySystem.dataFolder}/photos/immich 0775 root media -"
      "d ${config.mySystem.dataFolder}/torrents 0775 root media -"
      "d ${config.mySystem.dataFolder}/syncthing 0775 root media -"
    ]);
  };
}
