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
  };
}
