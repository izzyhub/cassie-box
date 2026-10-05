{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.system.systemd.ntfy-alerts;
in
{

  options.mySystem.system.systemd.ntfy-alerts.enable = mkEnableOption "ntfy alerts for systemd failures" // { default = true; };
  options.systemd.services = mkOption {
    type = with types; attrsOf (
      submodule {
        config.onFailure = mkIf cfg.enable [ "notify-ntfy@%n.service" ];
      }
    );
  };

  config = {
    # Warn if failure alerts are disabled and machine isnt a dev box
    warnings = [
      (mkIf (!cfg.enable && config.mySystem.purpose != "Development") "WARNING: ntfy SystemD failure notifications are disabled!")
    ];

    systemd.services."notify-ntfy@" = mkIf cfg.enable {
      enable = true;
      onFailure = lib.mkForce [ ]; # cant refer to itself on failure
      description = "Notify on failed unit %i";
      path = [ pkgs.systemd ];
      serviceConfig.Type = "oneshot";
      # huci is only reachable over the tailnet; failures during boot fire before
      # MagicDNS is up, so wait for tailscaled and keep retrying for a few minutes.
      after = [ "network-online.target" ] ++ optional config.services.tailscale.enable "tailscaled.service";
      wants = [ "network-online.target" ];
      # huci's ntfy is deny-all: bearer token from the global profile secret (see
      # profiles/global/sops.nix). Soft (-) so hosts without sops still start the unit.
      serviceConfig.EnvironmentFile = "-/run/secrets/services/ntfy/hooks-env";

      # Post the failed unit + a journal tail to the homelab ntfy topic on huci,
      # over the tailnet (mySystem.notifications.ntfyUrl). Ported from
      # izzy-nix-config. This is the out-of-band path: it still works when this
      # box's own vmalert/Alertmanager is the thing that broke, so retry through a
      # slow boot rather than becoming a failed unit itself.
      scriptArgs = "%i %H";
      script = ''
        ${pkgs.curl}/bin/curl -m 20 --retry 30 --retry-delay 10 --retry-max-time 300 --retry-connrefused \
          -H "Authorization: Bearer $NTFY_TOKEN" \
          -H "Title: $1 failed on $2" \
          -H "Tags: warning,skull" \
          -d "Journal tail:<br><br>$(journalctl -u "$1" -n 10 -o cat)" \
          ${config.mySystem.notifications.ntfyUrl}/${config.mySystem.notifications.topic}
      '';
    };

  };
}
