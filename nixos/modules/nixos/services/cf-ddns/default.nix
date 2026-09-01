{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.services.cfDdns;
  app = "cf-ddns";
  category = "services";
in
{
  options.mySystem.${category}.cfDdns = {
    enable = mkEnableOption "Cloudflare Dynamic DNS (local IP)";

    interface = mkOption {
      type = types.str;
      default = "eno2";
      description = "Network interface to get local IP from";
    };

    zone = mkOption {
      type = types.str;
      default = config.networking.domain;
      description = "Cloudflare zone (domain)";
    };

    records = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "example.com" "*.example.com" ];
      description = "DNS records to update with local IP";
    };

    interval = mkOption {
      type = types.str;
      default = "5min";
      description = "How often to check and update DNS records";
    };
  };

  config = mkIf cfg.enable {
    # Secret for Cloudflare API token
    sops.secrets."${category}/${app}/token" = {
      sopsFile = ./secrets.sops.yaml;
      restartUnits = [ "ddclient.service" ];
    };

    services.ddclient = {
      enable = true;
      interval = cfg.interval;
      protocol = "cloudflare";
      zone = cfg.zone;
      username = "token";  # Literal "token" for API token auth
      passwordFile = config.sops.secrets."${category}/${app}/token".path;
      domains = cfg.records;
      use = "if, if=${cfg.interface}";
      extraConfig = ''
        ttl=300
      '';
    };

    # The upstream ddclient module runs the unit with DynamicUser = true, so
    # no `ddclient` account exists on the system. Its ExecStartPre then does
    #
    #     install --mode=600 --owner=$USER ... /run/ddclient/ddclient.conf
    #
    # and that lookup has to resolve the name for real. When it does not, the
    # prestart dies with `install: invalid user 'ddclient'` and every run of
    # the timer fails before ddclient is ever reached - which is exactly the
    # failure seen here.
    #
    # Giving the unit a genuine system account removes the dependency on
    # resolving a transient user. systemd still chowns RuntimeDirectory and
    # StateDirectory to it, and ExecStartPre keeps its `!` privileged prefix,
    # so it can still read the root-owned sops secret below.
    users.groups.ddclient = { };
    users.users.ddclient = {
      isSystemUser = true;
      group = "ddclient";
      description = "Cloudflare dynamic DNS client";
    };

    systemd.services.ddclient.serviceConfig = {
      DynamicUser = mkForce false;
      User = "ddclient";
      Group = "ddclient";
    };
  };
}
