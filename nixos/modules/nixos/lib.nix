{ lib, config, pkgs, ... }:
with lib;
{

  # container builder
  lib.mySystem.mkContainer = options: (
    let
      # nix doesnt have an exhausive list of options for oci
      # so here i try to get a robust list of security options for containers
      # because everyone needs more tinfoild hat right?  RIGHT?

      containerExtraOptions = lib.optionals (lib.attrsets.attrByPath [ "caps" "privileged" ] false options) [ "--privileged" ]
        ++ lib.optionals (lib.attrsets.attrByPath [ "caps" "readOnly" ] false options) [ "--read-only" ]
        ++ lib.optionals (lib.attrsets.attrByPath [ "caps" "tmpfs" ] false options) (map (folders: "--tmpfs=${folders}") options.caps.tmpfsFolders)
        ++ lib.optionals (lib.attrsets.attrByPath [ "caps" "noNewPrivileges" ] false options) [ "--security-opt=no-new-privileges" ]
        ++ lib.optionals (lib.attrsets.attrByPath [ "caps" "dropAll" ] false options) [ "--cap-drop=ALL" ];

    in
    {
      ${options.app} = {
        image = "${options.image}";
        user = "${options.user}:${options.group}";
        environment = {
          TZ = config.time.timeZone;
        } // lib.attrsets.attrByPath [ "env" ] { } options;
        dependsOn = lib.attrsets.attrByPath [ "dependsOn" ] [ ] options;
        entrypoint = lib.attrsets.attrByPath [ "entrypoint" ] null options;
        cmd = lib.attrsets.attrByPath [ "cmd" ] [ ] options;
        environmentFiles = lib.attrsets.attrByPath [ "envFiles" ] [ ] options;
        volumes = [ "/etc/localtime:/etc/localtime:ro" ]
          ++ lib.attrsets.attrByPath [ "volumes" ] [ ] options;
        ports = lib.attrsets.attrByPath [ "ports" ] [ ] options;
        extraOptions = containerExtraOptions;
      };
    }
  );


  # nginx vhost builder — the common `forceSSL` + wildcard cert + one proxied
  # `^~ /` location that nearly every module used to hand-roll.
  #
  #   * host: `<subdomain>.<domain>`; subdomain defaults to `app`, `host` overrides it.
  #   * upstream: 127.0.0.1 for native services. `container = true` proxies to the
  #     container name over the podman DNS net instead (and adds the resolver line);
  #     `upstreamHost` / `resolver` override either half.
  #   * websockets, maxBodySize, longTimeouts, extraConfig (server block),
  #     extraLocationConfig (the proxied location(s)): the usual one-liners.
  #   * sso / ssoBypass / ssoGroup — forward-auth via oauth2-proxy in front of Kanidm
  #     (docs/security/sso-kanidm.md). Inert until `mySystem.services.sso.enable` is on,
  #     so `sso = true` is a safe no-op today. `ssoBypass` lists path prefixes that skip
  #     auth (homepage widget APIs, *arr /api, Subsonic /rest ...) — the #1 forward-auth
  #     footgun. `ssoGroup` narrows the vhost to one Kanidm group (e.g. "admins") on
  #     top of the portal-wide group.
  #
  # Returns the whole `virtualHosts` fragment, so assign it directly:
  #   services.nginx.virtualHosts = config.lib.mySystem.mkVhost {
  #     app = "jellyfin"; port = 8096; websockets = true;
  #   };
  lib.mySystem.mkVhost = options:
    let
      inherit (config.networking) domain;
      subdomain = options.subdomain or options.app;
      host = options.host or "${subdomain}.${domain}";

      container = options.container or false;
      upstreamHost = options.upstreamHost or (if container then options.app else "127.0.0.1");
      scheme = options.scheme or "http";
      proxyTarget = "${scheme}://${upstreamHost}:${builtins.toString options.port}";

      resolver = options.resolver or container;
      resolverLine = lib.optionalString resolver "resolver 10.88.0.1;\n";
      bodyLine = lib.optionalString (options ? maxBodySize) "client_max_body_size ${options.maxBodySize};\n";
      timeoutLines = lib.optionalString (options.longTimeouts or false) ''
        proxy_connect_timeout 600;
        proxy_read_timeout 600;
        proxy_send_timeout 600;
      '';

      # --- forward-auth, only emitted when the sso module is enabled ---
      inherit (config.mySystem.services) sso;
      ssoOn = (options.sso or false) && sso.enable;
      authLocation = "/internal-forward-auth";
      verifyUrl = sso.verifyUrl
        + lib.optionalString (options ? ssoGroup) "?allowed_groups=${sso.groupSpn options.ssoGroup}";
      # per claim: a unique nginx var (header name -> lowercased, `-`->`_`) carrying the
      # verifier's response header, then forwarded to the upstream app.
      claimVar = header: "$claim_" + lib.toLower (builtins.replaceStrings [ "-" ] [ "_" ] header);
      claimLines = lib.concatStrings (lib.mapAttrsToList
        (header: upstreamVar: ''
          auth_request_set ${claimVar header} ${upstreamVar};
          proxy_set_header ${header} ${claimVar header};
        '')
        sso.claims);
      authRequestLines = ''
        auth_request ${authLocation};
      '' + claimLines + ''
        auth_request_set $fa_redirect $scheme://$http_host$request_uri;
        error_page 401 =302 ${sso.signInUrl}$fa_redirect;
      '';

      mkLocation = extra: {
        proxyPass = proxyTarget;
        proxyWebsockets = options.websockets or false;
        extraConfig = (options.extraLocationConfig or "") + extra;
      };

      # bypass locations (no auth) for machine/API prefixes, in front of the guarded root
      bypassLocations = lib.listToAttrs (map
        (prefix: {
          name = "^~ ${prefix}";
          value = mkLocation "";
        })
        (lib.optionals ssoOn (options.ssoBypass or [ ])));

      # The internal verify subrequest (only when SSO is on for this vhost).
      # Deliberately NOT `proxyPass = ...`: with proxyResolveWhileRunning (set in
      # services/nginx) nixpkgs renders that as `set $nix_proxy_target "<url>";
      # proxy_pass $nix_proxy_target;`, and nginx subrequests share variables with
      # their parent — the auth subrequest would clobber the page's target and the
      # page itself would be proxied to /oauth2/auth (a blank 202). A literal
      # proxy_pass keeps the parent's target untouched.
      authInternalLocation = lib.optionalAttrs ssoOn {
        "= ${authLocation}" = {
          extraConfig = ''
            internal;
            proxy_pass ${verifyUrl};
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Uri $request_uri;
            proxy_set_header X-Original-Method $request_method;
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          '';
        };
      };
    in
    {
      ${host} = {
        forceSSL = true;
        useACMEHost = domain;
        locations = {
          "^~ /" = mkLocation (lib.optionalString ssoOn authRequestLines);
        } // bypassLocations // authInternalLocation;
        extraConfig = resolverLine + bodyLine + timeoutLines + (options.extraConfig or "");
      };
    };

  # build a restic restore set for both local and remote
  lib.mySystem.mkRestic = options: (
    let
      excludePaths = if builtins.hasAttr "excludePaths" options then options.excludePaths else [ ];
      timerConfig = {
        OnCalendar = "02:05";
        Persistent = true;
        RandomizedDelaySec = "3h";
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];
      initialize = true;
      backupPrepareCommand = ''
        # remove stale locks - this avoids some occasional annoyance
        #
        ${pkgs.restic}/bin/restic unlock --remove-all || true
      '';

    in
    {
      # local backup
      "${options.app}-local" = {
        inherit pruneOpts timerConfig initialize backupPrepareCommand;
        # Move the path to the zfs snapshot path
        paths = map (x: "${config.mySystem.system.resticBackup.mountPath}/${x}") options.paths;
        passwordFile = config.sops.secrets."services/restic/password".path;
        exclude = excludePaths;
        repository = "${config.mySystem.system.resticBackup.local.location}/${options.appFolder}";
        # inherit (options) user;
      };

      # remote backup
      "${options.app}-remote" = {
        inherit pruneOpts timerConfig initialize backupPrepareCommand;
        # Move the path to the zfs snapshot path
        paths = map (x: "${config.mySystem.system.resticBackup.mountPath}/${x}") options.paths;
        environmentFile = config.sops.secrets."services/restic/env".path;
        passwordFile = config.sops.secrets."services/restic/password".path;
        repository = "${config.mySystem.system.resticBackup.remote.location}/${options.appFolder}";
        exclude = excludePaths;
        # inherit (options) user;
      };

    }
  );

}
