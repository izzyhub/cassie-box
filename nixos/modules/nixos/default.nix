{ lib, config, ... }:
with lib;
{
  imports = [
    ./system
    ./programs
    ./services
    ./editor
    ./containers
    ./lib.nix
    ./ports.nix
    ./security
  ];

  options = {
    mySystem = {
      persistentFolder = mkOption {
        type = types.str;
        description = "persistent folder for nixos mutable files";
        default = "/mnt/data/persist";
      };

      domain = mkOption {
        type = types.str;
        description = "domain for hosted services";
        default = "";
      };
      internalDomain = mkOption {
        type = types.str;
        description = "domain for local devices";
        default = "";
      };
      # --- where hosts send notifications -------------------------------------------
      # Shared by the notify-ntfy@ systemd hook (system/ntfy-alerts) and the
      # Alertmanager bridge (services/ntfy-alertmanager). There is no ntfy on this box:
      # both publish to huci's ntfy (izzy-nix-config) over the tailnet, set in the
      # global profile. Failure-path code, so it must not depend on public DNS.
      notifications.ntfyUrl = mkOption {
        type = types.str;
        description = "Base URL hosts publish notifications to (no trailing slash).";
        example = "http://huci.tail6b6f7.ts.net:2586";
      };
      notifications.topic = mkOption {
        type = types.str;
        description = "ntfy topic for host/service notifications.";
        default = "homelab";
      };

      purpose = mkOption {
        type = types.str;
        description = "System purpose";
        default = "Production";
      };

      dataFolder = mkOption {
        type = types.str;
        description = "Data folder for shared storage";
        default = "/mnt/data";
      };

      system.impermanence = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable impermanence";
        };
      };
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.mySystem.persistentFolder} 777 - - -" #The - disables automatic cleanup, so the file wont be removed after a period
    ];
  };
}
