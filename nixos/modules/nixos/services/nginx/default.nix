{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.services.nginx;

  # Service mapping for automatic virtual host generation
  # Only include services that don't have manual nginx configs
  serviceMap = {
    # Most services already have manual nginx configs, so this is disabled for now
    # to avoid conflicts. Individual services handle their own nginx configuration.
  };

  # Generate virtual hosts for enabled services (as defaults - can be overridden)
  autoVirtualHosts = mapAttrs' (serviceName: serviceConfig: {
    name = "${serviceName}.${config.networking.domain}";
    value = mkDefault {
      forceSSL = true;
      useACMEHost = config.networking.domain;
      locations."^~ /" = mkDefault {
        proxyPass = "http://${serviceConfig.host}:${toString serviceConfig.port}";
        proxyWebsockets = true;
        extraConfig = mkIf (serviceConfig.host != "127.0.0.1") "resolver 10.88.0.1;";
      };
    };
  }) (filterAttrs (name: _: config.mySystem.services.${name}.enable or false) serviceMap);
in
{
  options.mySystem.services.nginx.enable = mkEnableOption "nginx";

  config = mkIf cfg.enable {

    services.nginx = {
      enable = true;

      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedBrotliSettings = true;

      proxyResolveWhileRunning = true; # needed to ensure nginx loads even if it cant resolve vhosts

      statusPage = true;
      enableReload = true;

      # Only allow PFS-enabled ciphers with AES256
      sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

      # appendHttpConfig = ''
      #   # Minimize information leaked to other domains
      #   add_header 'Referrer-Policy' 'origin-when-cross-origin';

      #   # Disable embedding as a frame
      #   add_header X-Frame-Options SAMEORIGIN always;

      #   # Prevent injection of code in other mime types (XSS Attacks)
      #   add_header X-Content-Type-Options nosniff;


      # '';
      # # TODO add cloudflre IP's when/if I ingest internally.
      # commonHttpConfig = ''
      #   add_header X-Clacks-Overhead "GNU Terry Pratchett";
      # '';
      # provide default host with returning error
      # else nginx returns the first server
      # in the config file... >:S
      virtualHosts = autoVirtualHosts // {
        "_" = {
          default = true;
          forceSSL = true;
          useACMEHost = config.networking.domain;
          extraConfig = "return 444;";
        };
      };

    };


    networking.firewall = {

      allowedTCPPorts = [ 80 443 ];
      allowedUDPPorts = [ 80 443 ];
    };

    # required for using acme certs
    users.users.nginx.extraGroups = [ "acme" ];

  };
}
