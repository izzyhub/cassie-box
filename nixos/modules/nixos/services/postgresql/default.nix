{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "postgresql";
  category = "services";
  description = "Postgres RDMS";
  appFolder = config.services.postgresql.dataDir;
in
{
  options.mySystem.${category}.${app} =
    {
      enable = mkEnableOption "${app}";
      addToHomepage = mkEnableOption "Add ${app} to homepage" // { default = true; };
      prometheus = mkOption
        {
          type = lib.types.bool;
          description = "Enable prometheus scraping";
          default = true;
        };
      backup = mkOption
        {
          type = lib.types.bool;
          description = "Enable backups";
          default = true;
        };
      upgradeTo = mkOption
        {
          type = lib.types.nullOr lib.types.package;
          default = null;
          example = literalExpression "pkgs.postgresql_17";
          description = ''
            Major-version upgrade helper. When set, puts an
            `upgrade-pg-cluster` script on PATH that pg_upgrades the
            running cluster into this package's data directory.

            Postgres majors need an imperative migration, so this is a
            two-step dance:

              1. Set this to the target package, leaving `package`
                 alone, and deploy.
              2. As root, stop everything that talks to postgres and run
                 `upgrade-pg-cluster`.
              3. Point `services.postgresql.package` at the target,
                 unset this, and deploy again.
              4. Run the `vacuumdb` command the script prints.

            Do not set this and bump `package` in the same deploy -- the
            new cluster would be initialised empty before pg_upgrade
            ever runs.
          '';
        };

    };

  config = mkIf cfg.enable {

    ## Secrets
    # sops.secrets."${category}/${app}/env" = {
    #   sopsFile = ./secrets.sops.yaml;
    #   owner = user;
    #   group = group;
    #   restartUnits = [ "${app}.service" ];
    # };

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; user = "postgres"; group = "postgres"; mode = "750"; }];
    };

    # See mySystem.services.postgresql.upgradeTo above. Straight out of the
    # NixOS manual's "Upgrading" section, with the old cluster taken from the
    # currently-configured package.
    environment.systemPackages = lib.optional (cfg.upgradeTo != null) (
      let
        newPostgres = cfg.upgradeTo;
        pgCfg = config.services.postgresql;
      in
      pkgs.writeShellScriptBin "upgrade-pg-cluster" ''
        set -eux

        systemctl stop postgresql

        NEWDATA="/var/lib/postgresql/${newPostgres.psqlSchema}"
        NEWBIN="${newPostgres}/bin"

        OLDDATA="${pgCfg.dataDir}"
        OLDBIN="${pgCfg.finalPackage}/bin"

        install -d -m 0700 -o postgres -g postgres "$NEWDATA"
        cd "$NEWDATA"
        sudo -u postgres "$NEWBIN/initdb" -D "$NEWDATA" ${lib.escapeShellArgs pgCfg.initdbArgs}

        sudo -u postgres "$NEWBIN/pg_upgrade" \
          --old-datadir "$OLDDATA" --new-datadir "$NEWDATA" \
          --old-bindir "$OLDBIN" --new-bindir "$NEWBIN" \
          "$@"
      ''
    );


    services.postgresql = {
      enable = true;
      # Pinned explicitly rather than left to the stateVersion default,
      # which would still be 15 (stateVersion is 23.11 and must not move).
      # Migrated from 15 with `upgrade-pg-cluster`; 17 is also what 25.11+
      # picks for fresh installs.
      package = pkgs.postgresql_17;
      identMap = ''
        # ArbitraryMapName systemUser DBUser
        superuser_map      root      postgres
        superuser_map      postgres  postgres
        # Let other names login as themselves
        superuser_map      /^(.*)$   \1
        superuser_map      root      rxresume
      '';
      authentication = ''
        #type database  DBuser  auth-method optional_ident_map
        local sameuser  all     peer        map=superuser_map
        local rxresume  root    peer
      '';
      settings = {
        max_connections = 2000;
        random_page_cost = 1.1;
        shared_buffers = "6GB";
      };
    };

    # enable backups
    services.postgresqlBackup = mkIf cfg.backup {
      enable = lib.mkForce true;
      location = "${config.mySystem.dataFolder}/backup/nixos/postgresql";
    };

    systemd.services.postgresqlBackup = {
      requires = [ "postgresql.service" ];
    };

    services.prometheus.exporters.postgres = {
      enable = true;
    };


    ### firewall config

    # networking.firewall = mkIf cfg.openFirewall {
    #   allowedTCPPorts = [ port ];
    #   allowedUDPPorts = [ port ];
    # };




  };
}
