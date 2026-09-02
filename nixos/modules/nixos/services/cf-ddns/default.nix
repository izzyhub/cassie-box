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

  # Prints the source address the kernel would actually use to leave this box,
  # which is whichever interface currently holds the default route. Combined
  # with net.ipv4.conf.*.ignore_routes_with_linkdown on the host, an unplugged
  # ethernet port is skipped and this returns the WiFi address instead - so the
  # record published to Cloudflare stays reachable across the fallback.
  #
  # `ip` is called by absolute path deliberately: the upstream ddclient module
  # only adds iproute2 to the unit's PATH when the method starts with `if,`.
  #
  # Caveat: this follows the default route, so if tailscale is ever configured
  # to use an exit node it would publish the 100.x tailnet address. Pin
  # `interface` if that ever becomes the case.
  egressAddress = pkgs.writeShellScript "${app}-egress-address" ''
    exec ${pkgs.iproute2}/bin/ip -4 route get 1.1.1.1 \
      | ${pkgs.gawk}/bin/awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }'
  '';
in
{
  options.mySystem.${category}.cfDdns = {
    enable = mkEnableOption "Cloudflare Dynamic DNS (local IP)";

    interface = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "eno2";
      description = ''
        Network interface to read the local IP from.

        When null (the default) the address is taken from whichever interface
        currently carries the default route, so the box keeps publishing a
        reachable address if it falls back from ethernet to WiFi. Pin an
        interface name only when a specific link must always be published.
      '';
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
      # Legacy `use` rather than `usev4` on purpose: setting usev4 would let the
      # module's usev6 default (ipify) kick in and start publishing AAAA
      # records, which is not what this service is for.
      use =
        if cfg.interface == null
        then "cmd, cmd=${egressAddress}"
        else "if, if=${cfg.interface}";
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

    systemd.services.ddclient = {
      # Upstream orders this after network.target only, which is satisfied long
      # before an address exists. The egress-address method then runs
      # `ip route get` against an empty routing table, gets "Network is
      # unreachable", and ddclient reports "unable to determine IP address".
      # It recovers on the next timer tick, but there is no reason to fail the
      # first one.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        DynamicUser = mkForce false;
        User = "ddclient";
        Group = "ddclient";
      };
    };
  };
}
