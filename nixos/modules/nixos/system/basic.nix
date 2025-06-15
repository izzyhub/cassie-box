{ lib
, config
, ...
}:
with lib;
{
  config = {
    # Create media group for data access
    users.groups.media = {};
    users.users.izzy.extraGroups = [ "media" ];
    users.users.cassie.extraGroups = [ "media" ];

    # System-wide tmpfiles rules
    systemd.tmpfiles.rules = [
      # Fix /var/lib/private permissions for systemd DynamicUser services
      "Z /var/lib/private 0700 root root -"
    ] ++ (optionals (config.mySystem.dataFolder != null) [
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
  };
}
