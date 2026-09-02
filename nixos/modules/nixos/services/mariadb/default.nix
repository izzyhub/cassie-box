{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "mariadb";
  category = "services";
  description = "mysql-compatiable database";
  # image = "";
  inherit (config.services.mysql) user;#string
  inherit (config.services.mysql) group;#string
  # port = ; #int
  # appFolder = "/var/lib/${app}";
  # persistentFolder = "${config.mySystem.persistentFolder}/var/lib/${appFolder}";
  host = "${app}" + (if cfg.dev then "-dev" else "");
  url = "${host}.${config.networking.domain}";
in
{
  options.mySystem.${category}.${app} =
    {
      enable = mkEnableOption "${app}";
      prometheus = mkOption
        {
          type = lib.types.bool;
          description = "Enable prometheus scraping";
          default = true;
        };
    };

  config = mkIf cfg.enable {

    ## Secrets
    # sops.secrets."${category}/${app}/env" = {
    #   sopsFile = ./secrets.sops.yaml;
    #   owner = user;
    #   group = group;
    #   restartUnits = [ "${app}.service" ];
    # };

    users.users.cassie.extraGroups = [ group ];
    users.users.izzy.extraGroups = [ group ];


    ## service
    services.mysql = {
      enable = true;
      # 11.4 LTS (EOL 2029-05). Upgraded from 10.11 deliberately, out of band
      # from an autoUpgrade switch, since the NixOS module does not run
      # `mariadb-upgrade` for you and the bump is one-way.
      package = pkgs.mariadb;
    };

  };
}
