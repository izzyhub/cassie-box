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
      # Pinned to the 10.11 LTS (EOL 2028-02) rather than `pkgs.mariadb`, which
      # became 11.4 in 26.05. That major bump is one-way and the NixOS module
      # does not run `mariadb-upgrade` for you -- with hourly autoUpgrade on,
      # it must not ride along with an unattended switch. To do it later:
      # dump first, switch to `pkgs.mariadb`, then run `mariadb-upgrade`.
      package = pkgs.mariadb_1011;
    };

  };
}
