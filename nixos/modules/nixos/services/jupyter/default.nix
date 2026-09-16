{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "jupyter";
  category = "services";
  description = "Notebooks for Python and R";
  # The upstream module creates this user for us (home /var/lib/jupyter).
  # Group `users` so cassie and izzy can reach the shared notebook folder.
  user = "jupyter";
  group = "users";
  port = 8888; #int
  appFolder = "/mnt/data/appdata/${app}";
  persistentFolder = "${config.mySystem.persistentFolder}/var/lib/${appFolder}";
  host = "${app}" + (if cfg.dev then "-dev" else "");
  url = "${host}.${config.networking.domain}";

  # Kernels are separate closures from the server itself: the server only needs
  # jupyterlab, while each kernel carries its own language runtime and libraries.
  pythonKernelEnv = pkgs.python3.withPackages (ps:
    (with ps; [
      ipykernel
      numpy
      scipy
      pandas
      statsmodels
      scikit-learn
      matplotlib
      seaborn
      polars
      pyarrow
      sympy
    ]) ++ (cfg.extraPythonPackages ps));

  rKernelEnv = pkgs.rWrapper.override {
    packages = (with pkgs.rPackages; [
      IRkernel
      tidyverse
      data_table
      broom
    ]) ++ cfg.extraRPackages;
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
      passwordHash = mkOption
        {
          type = lib.types.str;
          description = ''
            Argon2 hash of the notebook password, as produced by
            `python -c 'from jupyter_server.auth import passwd; print(passwd())'`.

            Left empty, Jupyter falls back to token auth and prints a one-time
            login URL to the journal - `journalctl -u jupyter -e | grep token`.

            Note this value is written into a world-readable file in the nix
            store, so it is a hash sitting in the store and in git, not a
            secret. sops cannot help here: the upstream module bakes the value
            into its generated config rather than reading it from a file.
          '';
          default = "";
          example = "argon2:$argon2id$v=19$m=10240,t=10,p=8$...";
        };
      extraPythonPackages = mkOption
        {
          type = lib.types.functionTo (lib.types.listOf lib.types.package);
          description = "Extra packages for the Python kernel, as a python-packages function.";
          default = ps: [ ];
          defaultText = literalExpression "ps: [ ]";
          example = literalExpression "ps: with ps; [ pymc arviz ]";
        };
      extraRPackages = mkOption
        {
          type = with lib.types; listOf package;
          description = "Extra packages for the R kernel.";
          default = [ ];
          example = literalExpression "with pkgs.rPackages; [ lme4 survival ]";
        };
    };

  config = mkIf cfg.enable {

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; inherit user; inherit group; mode = "2775"; }];
    };

    # Host port registry (nixos/modules/nixos/ports.nix).
    mySystem.ports.claims = {
      "${app}-http" = { port = port; address = "127.0.0.1"; claimedBy = "${app} notebook server"; };
    };

    # Shared notebook root, setgid so anything written here stays readable to
    # the `users` group rather than only to the jupyter account.
    systemd.tmpfiles.rules = [
      "d ${appFolder} 2775 ${user} ${group} -"
    ];

    services.jupyter = {
      enable = true;
      inherit user group port;
      ip = "127.0.0.1";
      # `jupyter lab` is not in the `notebook` package the module defaults to.
      package = pkgs.python3Packages.jupyterlab;
      command = "jupyter lab";
      notebookDir = appFolder;
      password = cfg.passwordHash;
      # jupytext keeps notebooks diffable as plain .py/.qmd alongside the .ipynb.
      extraPackages = [ pkgs.python3Packages.jupytext ];

      kernels = {
        python3 = {
          displayName = "Python 3 (stats)";
          argv = [
            "${pythonKernelEnv.interpreter}"
            "-m"
            "ipykernel_launcher"
            "-f"
            "{connection_file}"
          ];
          language = "python";
        };

        ir = {
          displayName = "R";
          # --no-echo is the post-R-4.0 spelling of the old --slave flag.
          argv = [
            "${rKernelEnv}/bin/R"
            "--no-echo"
            "-e"
            "IRkernel::main()"
            "--args"
            "{connection_file}"
          ];
          language = "R";
        };
      };
    };

    # homepage integration
    mySystem.services.homepage.infrastructure = mkIf cfg.addToHomepage [
      {
        ${app} = {
          icon = "jupyter.svg";
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
        # Lab's first paint is well past the repo's usual 50ms budget.
        conditions = [ "[CONNECTED] == true" "[STATUS] == 200" "[RESPONSE_TIME] < 500" ];
      }
    ];

    ### Ingress
    services.nginx.virtualHosts.${url} = {
      forceSSL = true;
      useACMEHost = config.networking.domain;
      locations."^~ /" = {
        proxyPass = "http://127.0.0.1:${builtins.toString port}";
        # Kernel comms are websockets, and a long-running cell must not be cut
        # off by the default 60s proxy read timeout.
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          client_max_body_size 0;
        '';
      };
    };

    ### backups
    warnings = [
      (mkIf (!cfg.backup && config.mySystem.purpose != "Development")
        "WARNING: Backups for ${app} are disabled!")
      (mkIf (cfg.passwordHash == "")
        "${app}: no passwordHash set - falling back to token auth. Run `journalctl -u jupyter -e | grep token` for the login URL.")
    ];

    services.restic.backups = mkIf cfg.backup (config.lib.mySystem.mkRestic
      {
        inherit app user;
        paths = [ appFolder ];
        inherit appFolder;
      });

  };
}
