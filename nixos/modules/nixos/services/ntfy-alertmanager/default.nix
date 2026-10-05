# ntfy-alertmanager — the bridge that turns Alertmanager webhooks into ntfy pushes.
# Ported from izzy-nix-config. nixpkgs ships the binary but no module, so this is ours.
#
# Why a bridge at all: Alertmanager's webhook payload is its own JSON shape, and ntfy
# would publish it verbatim as an unreadable blob. This renders a real notification —
# title, priority from the `severity` label, tags, and resolved handling.
#
# Difference from the source: there is no ntfy on cassie-box. The bridge runs here
# (Alertmanager reaches it over loopback) and publishes to huci's ntfy over the
# tailnet (mySystem.notifications.ntfyUrl), the same place notify-ntfy@ posts to.
# MagicDNS resolves that name even when LAN DNS at Cassie's does not.
{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "ntfy-alertmanager";
  category = "services";
  port = 8090; #int
in
{
  options.mySystem.${category}.${app} =
    {
      enable = mkEnableOption "${app} (Alertmanager -> ntfy bridge)";

      topic = mkOption
        {
          type = lib.types.str;
          description = ''
            ntfy topic alerts are published to. Defaults to the same topic the
            notify-ntfy@ systemd hook uses, so a phone already subscribed
            picks these up with no action — and so the ACLs on the existing publish
            token already cover it.
          '';
          default = config.mySystem.notifications.topic;
        };

      alertMode = mkOption
        {
          type = lib.types.enum [ "single" "multi" ];
          description = ''
            "single" sends one notification per alert (deduplicated by the cache
            below); "multi" keeps an Alertmanager group together in one message.
            Single is the right default here: the groups are small and a per-alert
            notification is what you can act on from a lock screen.
          '';
          default = "single";
        };

      listenPort = mkOption
        {
          type = lib.types.port;
          description = "Loopback port the Alertmanager webhook posts to.";
          default = port;
        };
    };

  config = mkIf cfg.enable {

    ## Secrets
    # The config file carries the ntfy publish token, so it is rendered by sops
    # rather than written to the nix store. Reuses the global hooks token — the same
    # identity notify-ntfy@ already publishes as, so no new ntfy user or ACL.
    sops.templates."${app}.scfg" = {
      owner = app;
      group = app;
      mode = "0400";
      restartUnits = [ "${app}.service" ];
      content = ''
        log-level info
        log-format text
        alert-mode ${cfg.alertMode}
        http-address 127.0.0.1:${toString cfg.listenPort}

        ntfy {
            server ${config.mySystem.notifications.ntfyUrl}
            topic ${cfg.topic}
            access-token ${config.sops.placeholder."services/ntfy/hooks-token"}
            markdown true
        }

        labels {
            order "severity"

            severity "critical" {
                priority 5
                tags "rotating_light"
            }

            severity "warning" {
                priority 4
                tags "warning"
            }

            severity "info" {
                priority 2
                tags "information_source"
            }
        }

        resolved {
            tags "white_check_mark"
            priority 2
        }

        cache {
            type memory
            duration 24h
            cleanup-interval 1h
        }
      '';
    };

    users.users.${app} = {
      isSystemUser = true;
      group = app;
    };
    users.groups.${app} = { };

    systemd.services.${app} = {
      description = "Alertmanager -> ntfy bridge";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.ntfy-alertmanager} -config ${config.sops.templates."${app}.scfg".path}";
        User = app;
        Group = app;
        Restart = "always";
        RestartSec = "10s";

        # Hardening — it reads one config file, listens on loopback and posts to huci.
        CapabilityBoundingSet = [ "" ];
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

  };
}
