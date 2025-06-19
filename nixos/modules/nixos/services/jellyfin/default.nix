{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.mySystem.${category}.${app};
  app = "jellyfin";
  category = "services";
  description = "TV organizer";
  user = "kah"; #string
  group = "kah"; #string
  port = 8096; #int
  appFolder = "/var/lib/${app}";
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
    #sops.secrets."${category}/${app}/env" = {
    #sopsFile = ./secrets.sops.yaml;
    #owner = user;
    #inherit group;
    #restartUnits = [ "${app}.service" ];
    #};

    users.users.izzy.extraGroups = [ group ];
    users.users.cassie.extraGroups = [ group ];

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; user = "kah"; group = "kah"; mode = "750"; }];
    };

    services.jellyfin = {
      enable = true;
      dataDir = "${appFolder}";
      inherit user group;
    };

    mySystem.services.homepage.media = mkIf cfg.addToHomepage [
      {
        Jellyfin = {
          icon = "${app}.svg";
          href = "https://${app}.${config.mySystem.domain}";

          description = "Media streaming service";
          container = "${app}";
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

    # Set environment variables for VAAPI
    systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME = "iHD";
    environment.sessionVariables = { LIBVA_DRIVER_NAME = "iHD"; };

    # Add Jellyfin packages
    environment.systemPackages = with pkgs; [
      jellyfin
      jellyfin-web
      jellyfin-ffmpeg
    ];

    # Add Intro Skipper plugin support
    nixpkgs.overlays = [
      (final: prev: {
        jellyfin-web = prev.jellyfin-web.overrideAttrs (finalAttrs: previousAttrs: {
          installPhase = ''
            runHook preInstall

            # Add Intro Skipper plugin script
            sed -i "s#</head>#<script src=\"configurationpage?name=skip-intro-button.js\"></script></head>#" dist/index.html

            mkdir -p $out/share
            cp -a dist $out/share/jellyfin-web

            runHook postInstall
          '';
        });
      })
    ];

    ### Ingress
    services.nginx.virtualHosts.${url} = {
      forceSSL = true;
      useACMEHost = config.networking.domain;
      locations."^~ /" = {
        proxyPass = "http://127.0.0.1:${builtins.toString port}";
      };
    };
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

    # Open firewall ports if enabled
    networking.firewall = {
      allowedTCPPorts = [ 8096 8920 ];
      allowedUDPPorts = [ 1900 7359 ];
    };
  };
}
