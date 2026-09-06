{ lib
, config
, pkgs
, inputs ? { }
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
  # 3000 is already taken on this host: the homepage container publishes
  # 127.0.0.1:3000:3000, so boat-ray binding 3000 died with EADDRINUSE.
  httpPort = 3001; # int - HTTP API + web UI
  grpcPort = 50051; # int - gRPC peer communication
  appFolder = "/mnt/data/appdata/${app}";
  url = "${app}.${config.networking.domain}";
in
{
  # Pull in boat-ray's own NixOS module (systemd service + package) from its
  # flake. Guarded on the input being present so that other hosts/flakes which
  # reuse these shared modules without a `boat-ray` flake input still evaluate
  # (they just can't enable the service) instead of failing with
  # "attribute 'boat-ray' missing".
  imports = lib.optionals (inputs ? boat-ray) [ inputs.boat-ray.nixosModules.default ];

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
      peerAddress = mkOption {
        type = lib.types.nullOr lib.types.str;
        description = ''
          BOAT_RAY_PEER_ADDRESS - the peer's gRPC endpoint as host:port.
          The port is NOT optional: boat-ray dials "http://''${peerAddress}", so a
          bare hostname resolves to port 80 and never reaches the peer's gRPC server.
        '';
        default = "sophie-001-1:${builtins.toString grpcPort}";
      };
      mediaDirs = mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Media directories for boat-ray to scan and sync into.";
        default = [ "${config.mySystem.dataFolder}/media" ];
      };

      # These three are `str`/`nullOr str` rather than lists to match the
      # upstream options they are forwarded to; boat-ray takes exactly one
      # directory for each, not a search path.
      downloadDir = mkOption {
        type = lib.types.str;
        description = ''
          Staging directory for in-progress downloads. Only the hidden
          `.{id}.partial` file lives here - a finished pull is moved to tvDir or
          movieDir.

          Dot-prefixed and kept inside mediaDirs on purpose: the scanner and the
          watcher both skip hidden names, so staging is invisible to the library,
          while sharing a filesystem with the landing directories keeps the final
          step a rename instead of a whole-file copy.
        '';
        default = "${config.mySystem.dataFolder}/media/.boat-ray-incoming";
      };
      tvDir = mkOption {
        type = lib.types.nullOr lib.types.str;
        description = ''
          Where a finished episode is filed, as `<Show Title>/Season NN/<file>`.
          Must be inside one of mediaDirs, or the file is written and then never
          scanned into the library. Null leaves episodes in downloadDir.
        '';
        default = "${config.mySystem.dataFolder}/media/tv";
      };
      movieDir = mkOption {
        type = lib.types.nullOr lib.types.str;
        description = ''
          Where a finished movie is filed, under the peer's own filename. Must be
          inside one of mediaDirs, or the file is written and then never scanned
          into the library. Null leaves movies in downloadDir.
        '';
        default = "${config.mySystem.dataFolder}/media/movies";
      };
    };

  config = mkIf cfg.enable {

    ## Secrets - TMDB/TVDB API keys (and any other env boat-ray needs).
    sops.secrets."${category}/${app}/env" = {
      sopsFile = ./secrets.sops.yaml;
      owner = user;
      inherit group;
      restartUnits = [ "${app}.service" ];
    };

    assertions = [{
      assertion = inputs ? boat-ray;
      message = "mySystem.services.boat-ray.enable requires a `boat-ray` flake input (inputs.boat-ray.nixosModules.default).";
    }];

    # Host port registry (nixos/modules/nixos/ports.nix): declaring these makes
    # a collision an eval error instead of an EADDRINUSE crash loop.
    mySystem.ports.claims = {
      "${app}-http" = { port = httpPort; claimedBy = "${app} HTTP/UI"; };
      "${app}-grpc" = { port = grpcPort; claimedBy = "${app} gRPC peer"; };
    };

    # boat-ray transfers files into the media directories, so its service user
    # needs membership in the `media` group (media root is root:media 0775).
    users.users.${user}.extraGroups = [ "media" ];

    # State/cache live under the repo's appdata convention so restic backs it up.
    systemd.tmpfiles.rules = [
      "d ${appFolder} 0750 ${user} ${group} -"
      "d ${appFolder}/cache 0750 ${user} ${group} -"
    ];

    # The TV and movie trees are now shared between the *arr stack and boat-ray,
    # so they are declared here the way system/basic.nix declares every other
    # shared media directory - `root:media`, group-writable - rather than left
    # to whichever service happened to create them first (they existed as
    # `kah:kah 0755`, which no second writer can use).
    #
    # 2775 rather than 0775: the setgid bit makes a subdirectory inherit `media`
    # from its parent, so a show directory sonarr creates stays writable by
    # boat-ray and a season directory boat-ray creates stays writable by sonarr.
    # Setgid carries the group down but not the write bit, so both services also
    # need UMask=0002 - see below for boat-ray, and the sonarr/radarr modules for
    # the other side.
    #
    # This has to be a `settings` file rather than a `rules` entry, and it has to
    # sort where it does. boat-ray's upstream module emits
    # `d <dir> 0755 boat-ray boat-ray -` for every directory it is handed, which
    # for a directory that already exists is applied, not skipped - it would chown
    # these two trees out from under sonarr and radarr. systemd-tmpfiles keeps the
    # first line it reads for a path and ignores later duplicates, and reads files
    # in lexicographic order, so `00-boat-ray-media.conf` beats the shared
    # `00-nixos.conf` that every `systemd.tmpfiles.rules` entry - upstream's
    # included - is concatenated into. Ordering *within* that shared file would
    # depend on module merge order, which is why this does not live in basic.nix
    # next to the media directories it otherwise belongs with.
    systemd.tmpfiles.settings."00-boat-ray-media" =
      lib.genAttrs
        (lib.filter (d: d != null) [ cfg.tvDir cfg.movieDir ])
        (_: { d = { mode = "2775"; user = "root"; group = "media"; }; });

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
      peerAddress = cfg.peerAddress;
      # Without these three forwarded, upstream keeps its own defaults:
      # downloadDir=/var/lib/boat-ray/downloads with tvDir/movieDir unset, which
      # means "leave a finished pull in the download directory". That directory
      # is outside mediaDirs, so the watcher never sees the file and a completed
      # download never reaches the library.
      inherit (cfg) downloadDir tvDir movieDir;
      # TMDB/TVDB keys (and any other env) decrypted by sops at runtime.
      environmentFile = config.sops.secrets."${category}/${app}/env".path;
    };

    ### Tailnet ordering
    # The peer is reached by its MagicDNS name, so boat-ray must not start
    # until tailscaled is up (it owns the 100.100.100.100 resolver and the
    # tailscale0 route) and the underlying network is online. Upstream already
    # orders after network-online.target; tailscaled is added here because only
    # this repo knows the peer is a tailnet host.
    # (Guarded on tailscale actually being enabled, so a host reusing these
    # shared modules without tailscale doesn't get an unsatisfiable dependency.)
    #
    # nss-lookup.target is the synchronisation point for name resolution:
    # resolvers declare Before=/Wants= on it, consumers order After= it. It is
    # only ordering, never pulled in from here - a host with no resolver unit
    # simply has nothing before it, so this stays a no-op rather than an
    # unsatisfiable dependency.
    systemd.services.${app} = {
      after = [ "network-online.target" "nss-lookup.target" ]
        ++ lib.optional config.services.tailscale.enable "tailscaled.service";
      wants = [ "network-online.target" ];
      requires = lib.optional config.services.tailscale.enable "tailscaled.service";

      serviceConfig = {
        # Whatever boat-ray files into the shared TV and movie trees has to stay
        # writable by the *arr stack. The setgid bit on those trees carries the
        # `media` group down to the season directories boat-ray creates, but not
        # the group write bit: with the default 0022 they come out
        # 0775 & ~0022 = 0755 and sonarr cannot write into a season boat-ray got
        # to first.
        UMask = "0002";
      }

      # tailscaled being *started* doesn't mean the tailnet is usable yet:
      # MagicDNS only answers once the node has come up and pulled the netmap.
      # Wait (bounded) for the peer name to resolve so the first connection
      # attempt doesn't fail on NXDOMAIN. Never fails the unit - boat-ray's
      # Restart=on-failure handles a peer that is genuinely down.
      // lib.optionalAttrs (cfg.peerAddress != null) {
        ExecStartPre = [
          "${pkgs.writeShellScript "${app}-wait-for-peer-dns" ''
            host="${lib.head (lib.splitString ":" cfg.peerAddress)}"
            i=0
            while [ "$i" -lt 30 ]; do
              if ${pkgs.getent}/bin/getent hosts "$host" > /dev/null; then
                exit 0
              fi
              i=$((i + 1))
              ${pkgs.coreutils}/bin/sleep 2
            done
            echo "boat-ray: peer $host did not resolve within 60s, starting anyway" >&2
          ''}"
        ];
      };
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
