{ lib
, config
, pkgs
, inputs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "boat-ray";
  category = "services";
  description = "Peer-to-peer media synchronization";
  # boat-ray's upstream module runs the service as its own dedicated
  # "boat-ray" system user/group (see inputs.boat-ray.nixosModules.default).
  user = "boat-ray";
  group = "boat-ray";
  httpPort = 3000; # int - HTTP API + web UI
  grpcPort = 50051; # int - gRPC peer communication
  appFolder = "/mnt/data/appdata/${app}";
  url = "${app}.${config.networking.domain}";
in
{
  # Pull in boat-ray's own NixOS module (systemd service + package) from its flake.
  imports = [ inputs.boat-ray.nixosModules.default ];

  options.mySystem.${category}.${app} =
    {
      enable = mkEnableOption "${app}";
      addToHomepage = mkEnableOption "Add ${app} to homepage" // { default = true; };
      monitor = mkOption {
        type = lib.types.bool;
        description = "Enable gatus monitoring";
        default = true;
      };
      addToDNS = mkOption {
        type = lib.types.bool;
        description = "Add to DNS list";
        default = true;
      };
      backup = mkOption {
        type = lib.types.bool;
        description = "Enable backups";
        default = true;
      };
      openFirewall = mkOption {
        type = lib.types.bool;
        description = "Open the gRPC peer port on the tailscale0 interface only";
        default = true;
      };
      mediaDirs = mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Media directories for boat-ray to scan and sync into.";
        default = [ "${config.mySystem.dataFolder}/media" ];
      };
    };

  config = mkIf cfg.enable {

    # boat-ray transfers files into the media directories, so its service user
    # needs membership in the `media` group (media root is root:media 0775).
    users.users.${user}.extraGroups = [ "media" ];

    # State/cache live under the repo's appdata convention so restic backs it up.
    systemd.tmpfiles.rules = [
      "d ${appFolder} 0750 ${user} ${group} -"
      "d ${appFolder}/cache 0750 ${user} ${group} -"
    ];

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; inherit user group; mode = "750"; }];
    };

    # Configure boat-ray's upstream module.
    services.boat-ray = {
      enable = true;
      inherit httpPort grpcPort;
      databasePath = "${appFolder}/boat-ray.db";
      cacheDir = "${appFolder}/cache";
      mediaDirs = cfg.mediaDirs;
      # environmentFile = ...;  # TMDB/TVDB keys - wire up via sops when needed.
    };

    # homepage integration
    mySystem.services.homepage.media = mkIf cfg.addToHomepage [
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
        conditions = [ "[CONNECTED] == true" "[STATUS] == 200" ];
      }
    ];

    ### Ingress (web UI + REST API + WebSocket)
    services.nginx.virtualHosts.${url} = {
      forceSSL = true;
      useACMEHost = config.networking.domain;
      locations."^~ /" = {
        proxyPass = "http://127.0.0.1:${builtins.toString httpPort}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };

    ### Firewall - expose the gRPC peer port to tailnet peers only.
    # Being on the same tailnet provides reachability, but the NixOS firewall
    # still drops inbound traffic on tailscale0 unless explicitly allowed here.
    networking.firewall.interfaces.tailscale0 = mkIf cfg.openFirewall {
      allowedTCPPorts = [ grpcPort ];
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

  };
}
