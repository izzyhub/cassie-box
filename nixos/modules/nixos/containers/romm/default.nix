{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "romm";
  category = "services";
  description = "ROM Manager";
  user = "kah";
  group = "kah";
  port = 3000;
  appFolder = "/var/lib/${app}";
  persistentFolder = "${config.mySystem.persistentFolder}/var/lib/${appFolder}";
  host = "${app}" + (if cfg.dev then "-dev" else "");
  url = "${host}.${config.networking.domain}";
  dataFolder = "${config.mySystem.dataFolder}";
in
{
  options.mySystem.${category}.${app} = {
    enable = mkEnableOption "${app}";
    addToHomepage = mkEnableOption "Add ${app} to homepage" // { default = true; };
    monitor = mkOption {
      type = lib.types.bool;
      description = "Enable gatus monitoring";
      default = true;
    };
    prometheus = mkOption {
      type = lib.types.bool;
      description = "Enable prometheus scraping";
      default = true;
    };
    addToDNS = mkOption {
      type = lib.types.bool;
      description = "Add to DNS list";
      default = true;
    };
    dev = mkOption {
      type = lib.types.bool;
      description = "Development instance";
      default = false;
    };
    backup = mkOption {
      type = lib.types.bool;
      description = "Enable backups";
      default = true;
    };
  };

  config = mkIf cfg.enable {
    ## Secrets
    sops.secrets."${category}/${app}/env" = {
      sopsFile = ./secrets.sops.yaml;
      owner = user;
      inherit group;
      restartUnits = [ "${app}.service" "${app}-db.service" ];
    };

    # Folder perms
    systemd.tmpfiles.rules = [
      "d ${appFolder}/ 0750 ${user} ${group} -"
      "d ${appFolder}/resources 0750 ${user} ${group} -"
      "d ${appFolder}/redis-data 0750 ${user} ${group} -"
      "d ${appFolder}/config 0750 ${user} ${group} -"
    ];

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; inherit user; inherit group; mode = "750"; }];
    };

    virtualisation.oci-containers.containers = {
      "${app}" = {
        image = "rommapp/romm:latest";
        environmentFiles = [ config.sops.secrets."${category}/${app}/env".path ];
        environment = {
          DB_HOST = "${app}-db";
          DB_NAME = app;
          DB_USER = "${app}-user";
        };
        volumes = [
          "/etc/localtime:/etc/localtime:ro"
          "${appFolder}/resources:/romm/resources"
          "${appFolder}/redis-data:/redis-data"
          "${dataFolder}/roms:/romm/library"
          "${dataFolder}/roms/assets:/romm/assets"
          "${appFolder}/config:/romm/config"
        ];
        dependsOn = [ "${app}-db" ];
        ports = [ "${builtins.toString port}:8080" ];
        extraOptions = [
          "--dns=10.88.0.1"
        ];
      };

      "${app}-db" = {
        image = "mariadb:latest";
        environmentFiles = [ config.sops.secrets."${category}/${app}/env".path ];
        environment = {
          MARIADB_DATABASE = app;
          MARIADB_USER = "${app}-user";
        };
        volumes = [ "${appFolder}/db:/var/lib/mysql" ];
        extraOptions = [
          "--health-cmd=healthcheck.sh --connect --innodb_initialized"
          "--health-interval=10s"
          "--health-timeout=5s"
          "--health-start-period=30s"
          "--health-retries=5"
        ];
      };
    };

    # homepage integration
    mySystem.services.homepage.infrastructure = mkIf cfg.addToHomepage [
      {
        ${app} = {
          icon = "${app}.svg";
          href = "https://${url}";
          inherit description;
        };
      }
    ];

    ### gatus integration
    mySystem.services.gatus.monitors = mkIf cfg.monitor [
      {
        name = app;
        group = "${category}";
        url = "https://${url}";
        interval = "1m";
        conditions = [ "[CONNECTED] == true" "[STATUS] == 200" "[RESPONSE_TIME] < 50" ];
      }
    ];

    ### Ingress
    services.nginx.virtualHosts.${url} = {
      forceSSL = true;
      useACMEHost = config.networking.domain;
      locations."^~ /" = {
        proxyPass = "http://127.0.0.1:${builtins.toString port}";
        proxyWebsockets = true;
      };
    };

    ### backups
    warnings = [
      (mkIf (!cfg.backup && config.mySystem.purpose != "Development")
        "WARNING: Backups for ${app} are disabled!")
    ];

    services.restic.backups = mkIf cfg.backup (config.lib.mySystem.mkRestic {
      inherit app user;
      paths = [ appFolder ];
      inherit appFolder;
    });
  };
}
