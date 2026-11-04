{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "immich";
  category = "services";
  description = "Photo managment";
  # image = "";
  user = "kah"; #string
  group = "kah"; #string
  port = 2283; #int
  appFolder = "/mnt/data/appdata/${app}";
  persistentFolder = "${config.mySystem.persistentFolder}/var/lib/${appFolder}";
  host = "${app}" + (if cfg.dev then "-dev" else "");
  url = "${host}.${config.networking.domain}";
  environment = {
    DB_HOSTNAME = "immich-postgres";
    REDIS_HOSTNAME = "immich-redis";
    IMMICH_METRICS = "true";
  };
  dataFolder = "${config.mySystem.dataFolder}";
in
{
  options.mySystem.${category}.${app} =
    {
      enable = mkEnableOption "${app}";
      addToHomepage = mkEnableOption "Add ${app} to homepage" // { default = true; };
      monitor = mkOption
        {
          type = lib.types.bool;
          description = "Enable gatus monitoring";
          default = true;
        };
      prometheus = mkOption
        {
          type = lib.types.bool;
          description = "Enable prometheus scraping";
          default = true;
        };
      addToDNS = mkOption
        {
          type = lib.types.bool;
          description = "Add to DNS list";
          default = true;
        };
      dev = mkOption
        {
          type = lib.types.bool;
          description = "Development instance";
          default = false;
        };
      backup = mkOption
        {
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
      restartUnits = [ "${app}-server.service" "${app}-postgres.service" ];
    };

    # users = {
    #   users = {

    #     # Create immich user
    #     immich = {
    #       isSystemUser = true;
    #       group = "immich";
    #       description = "Immich daemon user";
    #       # home = cfg.dataDir;
    #       uid = 390;
    #     };

    #     cassie.extraGroups = [ "immich" ];
    #     # Add admins to the immich group
    #   };

    #   # Create immich group
    #   groups.immich = {
    #     gid = 390;
    #   };

    # };


    # Folder perms - only for containers
    systemd.tmpfiles.rules = [
      "d ${appFolder}/ 0750 ${user} ${group} -"
      "d ${appFolder}/machine-learning 0750 ${user} ${group} -"
      "d ${appFolder}/postgres 0750 acme acme -"
      # Podman won't create a missing bind-mount source. The postgres entrypoint
      # runs as uid 999; owning it as root here would be re-applied on every
      # switch and lock postgres out of its own data dir.
      "d /var/lib/immich/postgres-v3 0700 999 999 -"

    ];

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; inherit user; inherit group; mode = "750"; }];
    };

    virtualisation.oci-containers.containers =
      {
        immich-server = {
          image = "ghcr.io/immich-app/immich-server:v3.3.6@sha256:e1981983b1c13f6024b57d72e7ecae3342eed1581201ab09fb248932d86c593a";
          environmentFiles = [ config.sops.secrets."${category}/${app}/env".path ];
          inherit environment;
          volumes = [
            "/etc/localtime:/etc/localtime:ro"
            # /data since v1.136; /usr/src/app/upload is the old location.
            "${dataFolder}/photos/immich/:/data"
          ];
          dependsOn = [ "immich-redis" "immich-postgres" ];
          ports = [ "${builtins.toString port}:${builtins.toString port}" ];
          extraOptions = [
            # Force DNS resolution to only be the podman dnsname name server; by default podman provides a resolv.conf
            # that includes both this server and the upstream system server, causing resolutions of other pod names
            # to be inconsistent.
            "--dns=10.88.0.1"
            "--device=/dev/dri:/dev/dri"
          ];
        };



        immich-machine-learning = {
          image = "ghcr.io/immich-app/immich-machine-learning:v3.3.6@sha256:14367bfb374b8576ddf49abd67c5ca0190a4c7fcf6303cdad65d7f7bf1a50bc2";
          inherit environment;
          volumes = [
            "/var/lib/immich/machine-learning:/cache"
          ];
          extraOptions = [
            # Force DNS resolution to only be the podman dnsname name server; by default podman provides a resolv.conf
            # that includes both this server and the upstream system server, causing resolutions of other pod names
            # to be inconsistent.
            "--dns=10.88.0.1"
          ];

        };

        immich-redis = {
          # Upstream's compose switched redis to valkey.
          image = "docker.io/valkey/valkey:9@sha256:3add1a336a920ea54770a001ab6feb3da5fceea96a40373a3a2cd469b815f0b7";
          extraOptions = [
            "--health-cmd=redis-cli ping || exit 1"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-start-period=30s"
          ];

        };


        immich-postgres = {
          image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
          environmentFiles = [ config.sops.secrets."${category}/${app}/env".path ];
          environment = {
            # Match DB_USERNAME / DB_DATABASE_NAME in the sops env, as upstream's compose
            # does. Without POSTGRES_DB, initdb never creates the `immich` database.
            POSTGRES_USER = "postgres";
            POSTGRES_DB = "immich";
            POSTGRES_INITDB_ARGS = "--data-checksums";
          };
          # A fresh data dir for the v3 jump (2026-11-02). The old v1.125 cluster in
          # /var/lib/immich/postgres held no real data; delete it once v3 is up.
          volumes = [ "/var/lib/immich/postgres-v3/:/var/lib/postgresql/data" ];
          extraOptions = [ "--shm-size=128m" ];
        };
      };


    # services.redis.servers.immich = {
    #   enable = true;
    #   user = "immich";
    # };

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

    services = {
      ### Ingress
      nginx.virtualHosts = config.lib.mySystem.mkVhost {
        inherit app port;
        host = url;
        websockets = true;
        maxBodySize = "0";
        longTimeouts = true;
      };

      ### firewall config

      # networking.firewall = mkIf cfg.openFirewall {
      #   allowedTCPPorts = [ port ];
      #   allowedUDPPorts = [ port ];
      # };

      vmagent = {
        prometheusConfig = {
          scrape_configs = [
            {
              job_name = "immich";
              # scrape_timeout = "40s";
              static_configs = [
                {
                  targets = [ "http://127.0.0.1:${builtins.toString port}" ];
                }
              ];
            }
          ];
        };
      };

      restic.backups = mkIf cfg.backup (config.lib.mySystem.mkRestic
        {
          inherit app user;
          paths = [ appFolder ];
          inherit appFolder;
        });
    };

    ### backups
    warnings = [
      (mkIf (!cfg.backup && config.mySystem.purpose != "Development")
        "WARNING: Backups for ${app} are disabled!")
    ];


    # services.postgresqlBackup = {
    #   databases = [ app ];
    # };



  };
}
