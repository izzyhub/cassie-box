{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.system.resticBackup;
  restic = "${pkgs.restic}/bin/restic";
  resticEnv = config.sops.secrets."services/restic/env".path;
  resticPassword = config.sops.secrets."services/restic/password".path;
in
{
  # Backups on cassie-box (ported from izzy-nix-config's restic module + sophie's
  # backups.nix, without the ZFS-snapshot flow — there is no ZFS here):
  #   * *-local:  one repo per app under `local.location` (the NVMe, outside mergerfs).
  #   * *-remote: the sops env file's RESTIC_REPOSITORY overrides the per-app
  #     `repository` mkRestic computes (systemd applies EnvironmentFile= after
  #     Environment=), so every remote unit writes to ONE shared B2 repo. Those units
  #     therefore never prune; restic-prune-remote below does it once a night.
  #   * paths are backed up live. Postgres is covered by its dumps; sqlite-backed apps
  #     are copied while running, which restic can catch mid-write. Accepted risk.
  options.mySystem.system.resticBackup = {
    local = {
      enable = mkEnableOption "Local backups" // { default = true; };
      location = mkOption
        {
          type = types.str;
          description = "Directory holding the per-app local restic repos.";
          default = "";
        };
    };
    remote = {
      enable = mkEnableOption "Remote backups" // { default = true; };
      location = mkOption
        {
          type = types.str;
          description = ''
            Prefix for the per-app remote `repository`. NOT the repository the units
            use: RESTIC_REPOSITORY in the sops env file overrides it (see above).
          '';
          default = "";
        };
    };

    # One cache for every repo, rather than upstream's one per backup unit. All the
    # *-remote units share one repo, so per-unit caches would each hold a full copy
    # of the same index. restic's cache is keyed by repo ID and safe to share.
    cacheDir = mkOption {
      type = types.str;
      description = "Shared restic cache directory for every backup unit on this host.";
      default = "/var/cache/restic";
    };

    # Retention for the per-app repos, applied by the *-local units and by
    # restic-prune-remote for the shared repo.
    keep = mkOption {
      type = types.listOf types.str;
      default = [ "--keep-daily 7" "--keep-weekly 5" "--keep-monthly 12" ];
    };
  };

  config = {

    # Warn if backups are disable and machine isnt a dev box
    warnings = [
      (mkIf (!cfg.local.enable && config.mySystem.purpose != "Development") "WARNING: Local backups are disabled!")
      (mkIf (!cfg.remote.enable && config.mySystem.purpose != "Development") "WARNING: Remote backups are disabled!")
    ];

    assertions = [{
      assertion = (cfg.local.enable && config.services.restic.backups != { }) -> cfg.local.location != "";
      message = ''
        mySystem.system.resticBackup.local.location is empty, so every *-local repo
        would resolve to `/<app>` on the root filesystem.
      '';
    }];

    sops.secrets = mkIf (cfg.local.enable || cfg.remote.enable) {
      "services/restic/password" = {
        sopsFile = ./secrets.sops.yaml;
        owner = "kah";
        group = "kah";
      };

      "services/restic/env" = {
        sopsFile = ./secrets.sops.yaml;
        owner = "kah";
        group = "kah";
      };
    };

    # --- hand-run restic against these repos ----------------------------------
    #   sudo restic-remote snapshots          # the shared offsite repo
    #   sudo restic-local sonarr snapshots    # the per-app local repo
    #
    # Use these, NOT the `restic-<app>-remote` shims nixpkgs generates: those set
    # RESTIC_REPOSITORY over the env file, the opposite of the units, and so point at
    # `remote.location`, which is not a repository that exists.
    environment.systemPackages =
      let
        guard = name: ''
          if [ "$(id -u)" -ne 0 ]; then
            echo "${name}: must run as root -- the credentials are sops secrets" >&2
            exit 1
          fi
          export RESTIC_CACHE_DIR=${cfg.cacheDir}
        '';
      in
      mkIf (cfg.local.enable || cfg.remote.enable) ([ pkgs.restic ]
        ++ optional cfg.remote.enable (pkgs.writeShellScriptBin "restic-remote" ''
        set -euo pipefail
        ${guard "restic-remote"}
        set -a
        . ${resticEnv}
        set +a
        export RESTIC_PASSWORD_FILE=${resticPassword}
        exec ${restic} "$@"
      '')
        ++ optional cfg.local.enable (pkgs.writeShellScriptBin "restic-local" ''
        set -euo pipefail
        if [ "$#" -lt 1 ]; then
          echo "usage: restic-local <app> <restic args...>" >&2
          echo "  <app> is a repo directory under ${cfg.local.location}" >&2
          exit 2
        fi
        ${guard "restic-local"}
        repo=$1; shift
        export RESTIC_REPOSITORY=${cfg.local.location}/$repo
        export RESTIC_PASSWORD_FILE=${resticPassword}
        exec ${restic} "$@"
      ''));

    systemd = mkMerge [
      {
        # Every backup unit uses the shared cache, and waits for the local repo's
        # mount (/mnt/data2 is a separate disk; don't write into the empty mountpoint).
        services = lib.mapAttrs'
          (name: _: lib.nameValuePair "restic-backups-${name}" {
            environment.RESTIC_CACHE_DIR = mkForce cfg.cacheDir;
            serviceConfig.CacheDirectory = mkForce "";
            unitConfig.RequiresMountsFor = [ cfg.cacheDir ]
              ++ optional (cfg.local.enable && hasSuffix "-local" name) cfg.local.location;
          })
          config.services.restic.backups;
      }

      (mkIf cfg.local.enable {
        tmpfiles.rules = [ "d ${cfg.local.location} 0750 root root -" ];
      })

      # --- one prune for the shared offsite repo -----------------------------
      # Backups take a shared lock and can overlap; forget+prune needs the exclusive
      # lock and deletes every pack its snapshot set doesn't reference. izzy-nix-config
      # lost 377 freshly written packs to ~47 per-unit prunes racing each other on one
      # repo. So: prune once, after the backup window (02:05 + up to 3h) closes.
      # Retention is per (host,paths) group, restic's default, so filtering by each
      # unit's paths reproduces what that unit would have applied to itself.
      (mkIf cfg.remote.enable {
        services.restic-prune-remote = {
          description = "Forget + prune the shared offsite restic repo";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = resticEnv;
            Environment = [
              "RESTIC_PASSWORD_FILE=${resticPassword}"
              "RESTIC_CACHE_DIR=${cfg.cacheDir}"
            ];
          };
          script =
            let
              remotes = lib.filterAttrs
                (n: b: lib.hasSuffix "-remote" n && b.paths != null && b.paths != [ ])
                config.services.restic.backups;
              forgetFor = _: b:
                let
                  paths = lib.concatMapStringsSep " " (x: "--path ${lib.escapeShellArg x}") b.paths;
                in
                "${restic} forget ${paths} ${lib.concatStringsSep " " cfg.keep}";
            in
            ''
              set -euo pipefail
              # stale locks only -- a live lock means a backup is still running
              ${restic} unlock || true
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList forgetFor remotes)}
              ${restic} prune
            '';
        };

        timers.restic-prune-remote = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "06:00";
            Persistent = true;
            RandomizedDelaySec = "30m";
          };
        };
      })
    ];
  };
}
