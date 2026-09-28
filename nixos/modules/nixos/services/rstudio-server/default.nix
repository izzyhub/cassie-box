{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "rstudio-server";
  category = "services";
  description = "R IDE in the browser";
  user = "rstudio-server";
  group = "users";
  # 8787 is RStudio's upstream default, but readarr already holds it here.
  port = 8788; #int
  appFolder = "/mnt/data/appdata/${app}";
  persistentFolder = "${config.mySystem.persistentFolder}/var/lib/${appFolder}";
  host = "${app}" + (if cfg.dev then "-dev" else "");
  url = "${host}.${config.networking.domain}";

  # A sensible baseline for coursework and thesis work. Deliberately excludes
  # the Stan family (rstan/brms): those compile against a local toolchain, take
  # a long time to build, and are better added per-project once someone
  # actually needs them.
  defaultRPackages = with pkgs.rPackages; [
    tidyverse # dplyr/ggplot2/tidyr/readr/purrr/tibble/stringr/forcats
    data_table
    knitr
    rmarkdown # the .Rmd/.qmd render path; needs pandoc + tex on PATH
    broom
    janitor
    here
    lme4
    survival
    MASS
    car
    glmnet
    randomForest
    DBI
    RPostgres # the box already runs postgres, so this is a free win
    gt
    kableExtra
    patchwork
    shiny
    languageserver
    Rcpp
  ];

  # RStudio resolves R and its library paths from the wrapper it was built
  # against. The nix store is read-only, so install.packages() inside a session
  # will not work - every library() a user needs has to be listed here (or in
  # extraRPackages) and rebuilt.
  rstudioPkg = pkgs.rstudioServerWrapper.override {
    packages = defaultRPackages ++ cfg.extraRPackages;
  };
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
      extraRPackages = mkOption
        {
          type = with lib.types; listOf package;
          description = ''
            Extra R packages to build into the RStudio wrapper, on top of the
            module's stats baseline. Sessions cannot install packages at
            runtime, so anything needed has to be declared here.
          '';
          default = [ ];
          example = literalExpression "with pkgs.rPackages; [ brms tidymodels ]";
        };
    };

  config = mkIf cfg.enable {

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; inherit user; inherit group; mode = "2775"; }];
    };

    # Host port registry (nixos/modules/nixos/ports.nix).
    mySystem.ports.claims = {
      "${app}-http" = { port = port; address = "127.0.0.1"; claimedBy = "${app} web UI"; };
    };

    # Sessions run as the logged-in user, so per-user state lands in their home
    # (~/.local/share/rstudio). This folder is the shared default working
    # directory - setgid so files created here stay group-readable.
    systemd.tmpfiles.rules = [
      "d ${appFolder} 2775 ${user} ${group} -"
    ];

    services.rstudio-server = {
      enable = true;
      package = rstudioPkg;
      listenAddr = "127.0.0.1";
      serverWorkingDir = appFolder;
      rserverExtraConfig = ''
        www-port=${builtins.toString port}
      '';
    };

    # Auth is PAM against real system accounts (the upstream module points
    # /etc/pam.d/rstudio at /etc/pam.d/login), so izzy and cassie sign in with
    # their normal passwords - the ones sops sets via hashedPasswordFile.

    # homepage integration
    mySystem.services.homepage.infrastructure = mkIf cfg.addToHomepage [
      {
        ${app} = {
          icon = "rstudio.svg";
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
        # The sign-in page is heavier than the repo's usual 50ms budget.
        conditions = [ "[CONNECTED] == true" "[STATUS] == 200" "[RESPONSE_TIME] < 500" ];
      }
    ];

    ### Ingress
    services.nginx.virtualHosts = config.lib.mySystem.mkVhost {
      inherit app port;
      host = url;
      # RStudio drives the whole IDE over a websocket, and a long-running
      # chunk must not be cut off mid-render by the default 60s proxy read
      # timeout.
      websockets = true;
      extraLocationConfig = ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        client_max_body_size 0;
      '';
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
