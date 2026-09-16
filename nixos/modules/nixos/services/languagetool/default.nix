{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "languagetool";
  category = "services";
  description = "Self-hosted grammar and style checking";
  # 8081 is LanguageTool's upstream default, but the calibre container
  # publishes 8081 on every interface already.
  port = 8082; #int
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
      allowOrigin = mkOption
        {
          type = lib.types.nullOr lib.types.str;
          description = ''
            Access-Control-Allow-Origin for the API. The browser add-ons and the
            LibreOffice integration call this server directly from pages on
            other origins, so they need CORS to be permitted.
          '';
          default = "*";
        };
      jvmOptions = mkOption
        {
          type = with lib.types; listOf str;
          description = "Extra JVM flags for the LanguageTool server.";
          default = [ "-Xmx1g" ];
        };
    };

  config = mkIf cfg.enable {

    # Host port registry (nixos/modules/nixos/ports.nix).
    mySystem.ports.claims = {
      "${app}-http" = { port = port; address = "127.0.0.1"; claimedBy = "${app} API"; };
    };

    # No backups and no appdata folder on purpose: the upstream module runs
    # this under DynamicUser with no state directory. Everything it knows is in
    # the package, so a rebuild is the whole restore path.
    services.languagetool = {
      enable = true;
      inherit port;
      # Stays on loopback; nginx is the only thing in front of it.
      public = false;
      inherit (cfg) allowOrigin jvmOptions;
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
        # `/` is a 404 - this server is an API, not a site. /v2/languages is the
        # cheapest endpoint that proves the JVM is actually up.
        url = "https://${url}/v2/languages";
        interval = "1m";
        conditions = [ "[CONNECTED] == true" "[STATUS] == 200" "[RESPONSE_TIME] < 500" ];
      }
    ];

    ### Ingress
    services.nginx.virtualHosts.${url} = {
      forceSSL = true;
      useACMEHost = config.networking.domain;
      locations."^~ /" = {
        proxyPass = "http://127.0.0.1:${builtins.toString port}";
        # Checking a whole chapter in one request goes well past the 1m default.
        extraConfig = ''
          client_max_body_size 32m;
        '';
      };
    };

  };
}
