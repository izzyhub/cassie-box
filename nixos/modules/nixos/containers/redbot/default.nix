{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "redbot";
  category = "services";
  description = "Discord bot";
  image = "phasecorex/red-discordbot:core-audio";
  user = "568"; #string
  group = "568"; #string
  # port = ; #int
  appFolder = "/mnt/data/appdata/${app}";
  dataFolder = "${config.mySystem.dataFolder}";
  persistentFolder = "${config.mySystem.persistentFolder}/var/lib/${appFolder}";
  host = "${app}" + (if cfg.dev then "-dev" else "");
  url = "${host}.${config.networking.domain}";
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
      owner = "kah";
      group = "kah";
      restartUnits = [ "${app}.service" ];
    };

    users.users.izzy.extraGroups = [ group ];
    users.users.cassie.extraGroups = [ group ];


    # Folder perms - only for containers
    # systemd.tmpfiles.rules = [
    # "d ${appFolder}/ 0750 ${user} ${group} -"
    # ];

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; inherit user; inherit group; mode = "750"; }];
    };


    ## service
    # services.test= {
    #   enable = true;
    # };

    ## OR

    virtualisation.oci-containers.containers."${app}" = {
      inherit image;
      environment = {
        PREFIX="?";
        NICENESS="-15";
      };
      environmentFiles = [
        config.sops.secrets."${category}/${app}/env".path
      ];
      volumes = [
        "${appFolder}:/data:rw"
        "${dataFolder}/media/music:/music/localtracks:ro"
      ];
      extraOptions = [ "--cap-add=SYS_NICE" ];
    };


    # homepage integration
    # mySystem.services.homepage.infrastructure = mkIf cfg.addToHomepage [
    #   {
    #     ${app} = {
    #       icon = "${app}.svg";
    #       href = "https://${url}";
    #       inherit description;
    #     };
    #   }
    # ];

    ### gatus integration
    # mySystem.services.gatus.monitors = mkIf cfg.monitor [
    #   {
    #     name = app;
    #     group = "${category}";
    #     url = "https://${url}";
    #     interval = "1m";
    #     conditions = [ "[CONNECTED] == true" "[STATUS] == 200" "[RESPONSE_TIME] < 50" ];
    #   }
    # ];

    ### Ingress
    # services.nginx.virtualHosts.${url} = {
    #   forceSSL = true;
    #   useACMEHost = config.networking.domain;
    #   locations."^~ /" = {
    #     proxyPass = "http://127.0.0.1:${builtins.toString port}";
    #     extraConfig = "resolver 10.88.0.1;";
    #   };
    # };

    ### firewall config

    # networking.firewall = mkIf cfg.openFirewall {
    #   allowedTCPPorts = [ port ];
    #   allowedUDPPorts = [ port ];
    # };

    ### backups
    warnings = [
      (mkIf (!cfg.backup && config.mySystem.purpose != "Development")
        "WARNING: Backups for ${app} are disabled!")
    ];

    services.restic.backups = mkIf cfg.backup (config.lib.mySystem.mkRestic
      {
        inherit app user;
        paths = [ appFolder ];
        inherit appFolder;
      });


    # services.postgresqlBackup = {
    #   databases = [ app ];
    # };



  };
}
