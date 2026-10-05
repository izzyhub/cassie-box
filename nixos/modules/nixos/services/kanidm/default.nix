# Kanidm — the identity provider for the SSO project (docs/security/sso-kanidm.md).
#
# Ported from izzy-nix-config. Here everything is on one host: Kanidm, oauth2-proxy and
# nginx all run on cassie-box and talk over loopback, so the source's LDAP and
# tailnet listeners are gone.
#
# Served at https://idm.<domain>. Everything that can be
# declared is: admin passwords, persons, groups and OAuth2 clients (incl. their secrets)
# come from `provision`, so a rebuild from nothing gives the same IdP. The only manual
# steps left are the ones Kanidm refuses to let a config file do — enrolling a person's
# password/passkey and POSIX passwords (doc §2, phase 2).
#
# TLS: kanidmd refuses plaintext, so it terminates its own TLS on 127.0.0.1:8443 using
# the host's ACME wildcard, and nginx proxies https:// to it (mkVhost `scheme`).
#
# Consumers add clients from their own modules:
#   mySystem.services.kanidm.oauth2.<app> = { displayName; originUrl; basicSecretFile; scopeMaps; ... }
# (same shape as services.kanidm.provision.systems.oauth2 — it is passed straight through).
{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "kanidm";
  category = "services";
  description = "Identity provider (SSO)";
  user = app;
  group = app;
  port = 8443; # kanidmd's own https listener (loopback only; nginx fronts it)
  appFolder = "/var/lib/${app}";
  backupFolder = "${appFolder}/backups";
  inherit (config.networking) domain;
  url = "${cfg.subdomain}.${domain}";
  certDir = "/var/lib/acme/${domain}";
in
{
  options.mySystem.${category}.${app} = {
    enable = mkEnableOption "${app}";
    subdomain = mkOption {
      type = types.str;
      default = "idm";
      description = "Subdomain the IdP is served on (also its Kanidm `domain`/`origin`). Changing this after first start renames the domain — webauthn credentials are bound to it.";
    };
    persons = mkOption {
      type = types.attrs;
      default = { };
      description = "Passed through to services.kanidm.provision.persons (displayName, mailAddresses, groups, ...).";
    };
    groups = mkOption {
      type = types.attrs;
      default = { };
      description = "Passed through to services.kanidm.provision.groups.";
    };
    oauth2 = mkOption {
      type = types.attrs;
      default = { };
      description = "Passed through to services.kanidm.provision.systems.oauth2 — one entry per client app.";
    };
    addToHomepage = mkEnableOption "Add ${app} to homepage" // { default = true; };
    monitor = mkOption {
      type = types.bool;
      default = true;
      description = "Enable gatus monitoring";
    };
    backups = mkOption {
      type = types.bool;
      default = true;
      description = "Enable local backups (kanidm's own nightly online backup dir goes into restic)";
    };
  };

  config = mkIf cfg.enable {

    assertions = [{
      assertion = config.mySystem.security.acme.enable;
      message = "mySystem.services.kanidm needs mySystem.security.acme (kanidmd terminates its own TLS with the wildcard cert).";
    }];

    ## Secrets — both admin passwords are *set* by provisioning on every start, so they
    ## never need recovering by hand. Generated with `openssl rand -hex 32`.
    sops.secrets = {
      "${category}/${app}/admin-password" = {
        sopsFile = ./secrets.sops.yaml;
        owner = user;
        inherit group;
        restartUnits = [ "${app}.service" ];
      };
      "${category}/${app}/idm-admin-password" = {
        sopsFile = ./secrets.sops.yaml;
        owner = user;
        inherit group;
        restartUnits = [ "${app}.service" ];
      };
    };

    # The `kanidm` CLI on this box: the nixpkgs module only puts it on PATH (and writes
    # /etc/kanidm/config) when the client is enabled. Point it at the public origin and
    # short-circuit that name to loopback here, so the CLI — and later oauth2-proxy's
    # OIDC discovery — never depend on LAN DNS for idm.<domain> (a router doing DNS
    # rebind protection at Cassie's would otherwise break every server-side hop).
    # nginx serves the vhost on 127.0.0.1 with the real wildcard cert, so
    # verification still passes.
    networking.hosts."127.0.0.1" = [ url ];

    # read the ACME wildcard cert; restart on renewal (kanidmd doesn't reload certs)
    users.users.${user}.extraGroups = [ "acme" ];
    security.acme.certs.${domain}.reloadServices = [ "${app}.service" ];

    environment.persistence."${config.mySystem.persistentFolder}" = mkIf config.mySystem.system.impermanence.enable {
      directories = [ appFolder ];
    };

    ## service
    services.kanidm = {
      # withSecretProvisioning = patched build that lets provisioning SET oauth2 basic
      # secrets + admin passwords (upstream only lets you read them back). Version must
      # be explicit per the nixpkgs module.
      package = pkgs.kanidm_1_11.withSecretProvisioning;

      client = {
        enable = true;
        settings.uri = "https://${url}";
      };

      server = {
        enable = true;
        settings = {
          domain = url;
          origin = "https://${url}";
          bindaddress = "127.0.0.1:${toString port}";
          # Trust X-Forwarded-For from nginx (loopback only). kanidm >= 1.4 config v2
          # replaced the old `trust_x_forward_for = true` boolean with this table.
          http_client_address_info."x-forward-for" = [ "127.0.0.1" ];
          tls_chain = "${certDir}/fullchain.pem";
          tls_key = "${certDir}/key.pem";
          # nightly consistent dump of the db (the live sqlite must not be copied raw);
          # restic (below) picks the directory up.
          online_backup = {
            path = backupFolder;
            schedule = "00 22 * * *";
            versions = 7;
          };
        };
      };

      # Provisioning talks to https://localhost:8443 (module default) with cert checks
      # relaxed — loopback only, so that's fine. It is authoritative for everything it
      # declares; `autoRemove` (default true) also deletes things it created earlier that
      # vanished from config.
      provision = {
        enable = true;
        adminPasswordFile = config.sops.secrets."${category}/${app}/admin-password".path;
        idmAdminPasswordFile = config.sops.secrets."${category}/${app}/idm-admin-password".path;
        inherit (cfg) persons groups;
        systems.oauth2 = cfg.oauth2;
      };
    };

    # homepage integration
    mySystem.services.homepage.infrastructure = mkIf cfg.addToHomepage [
      {
        ${app} = {
          icon = "${app}.svg";
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
        url = "https://${url}/status";
        interval = "1m";
        conditions = [ "[CONNECTED] == true" "[STATUS] == 200" "[RESPONSE_TIME] < 1500" ];
      }
    ];

    ### Ingress — https upstream (kanidmd's own TLS, real wildcard cert so no verify-off needed)
    services.nginx.virtualHosts = config.lib.mySystem.mkVhost {
      inherit app port;
      inherit (cfg) subdomain;
      scheme = "https";
      websockets = true;
    };

    ### backups
    warnings = [
      (mkIf (!cfg.backups && config.mySystem.purpose != "Development")
        "WARNING: Backups for ${app} are disabled!")
    ];

    services.restic.backups = mkIf cfg.backups (config.lib.mySystem.mkRestic {
      inherit app user appFolder;
      paths = [ backupFolder ];
    });
  };
}
