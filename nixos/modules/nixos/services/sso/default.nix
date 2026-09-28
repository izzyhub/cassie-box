# SSO forward-auth — the ingress seam that `config.lib.mySystem.mkVhost` reads.
#
# A vhost built with `mkVhost { ...; sso = true; }` gets an nginx `auth_request` in
# front of it, answered by oauth2-proxy (which talks OIDC to Kanidm; Kanidm has no
# auth_request endpoint of its own). Everything here is inert until `enable` is set:
# `sso = true` on a vhost is a no-op before that, so modules can be marked ahead of
# the IdP landing. See docs/security/sso-kanidm.md.
#
# Single host: Kanidm, oauth2-proxy and nginx all run on this box, so the verify
# endpoint is loopback and there is exactly one portal/cookie for `.<domain>`.
{ lib
, config
, ...
}:
with lib;
let
  cfg = config.mySystem.services.sso;
  inherit (config.networking) domain;
in
{
  options.mySystem.services.sso = {
    enable = mkEnableOption "forward-auth SSO (gates mkVhost `sso = true` vhosts)";

    idmUrl = mkOption {
      type = types.str;
      default = "https://idm.${domain}";
      description = "Base URL of Kanidm. OIDC issuers are <idmUrl>/oauth2/openid/<client>.";
    };

    portalUrl = mkOption {
      type = types.str;
      default = "https://auth.${domain}";
      description = "Base URL of the oauth2-proxy portal users are redirected to on a 401.";
    };

    verifyUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:4180/oauth2/auth";
      description = "oauth2-proxy's auth endpoint, hit by nginx's internal auth_request subrequest.";
    };

    signInUrl = mkOption {
      type = types.str;
      default = "${cfg.portalUrl}/oauth2/start?rd=";
      defaultText = literalExpression ''"''${portalUrl}/oauth2/start?rd="'';
      description = "401 redirect base; mkVhost appends the original request URL.";
    };

    groupSpn = mkOption {
      type = types.functionTo types.str;
      readOnly = true;
      default = group: "${group}@${removePrefix "https://" cfg.idmUrl}";
      description = ''
        Kanidm group name -> the full SPN that appears in the `groups` claim
        (`admins` -> `admins@idm.<domain>`). Used by mkVhost's `ssoGroup`.
      '';
    };

    claims = mkOption {
      type = types.attrsOf types.str;
      default = {
        "X-Auth-Request-User" = "$upstream_http_x_auth_request_user";
        "X-Auth-Request-Email" = "$upstream_http_x_auth_request_email";
        "X-Auth-Request-Groups" = "$upstream_http_x_auth_request_groups";
        "X-Auth-Request-Preferred-Username" = "$upstream_http_x_auth_request_preferred_username";
      };
      description = ''
        Identity headers forwarded to the upstream app: upstream request header name ->
        the nginx variable holding oauth2-proxy's response header. mkVhost turns each
        into an `auth_request_set` + `proxy_set_header` pair.
      '';
    };
  };

  # Enabling this without a responder would 500 every guarded vhost, so make that loud.
  config = mkIf cfg.enable {
    assertions = [{
      assertion = config.mySystem.services.oauth2-proxy.enable or false;
      message = ''
        mySystem.services.sso.enable = true, but mySystem.services.oauth2-proxy is not
        enabled — the forward-auth subrequest would fail every `sso = true` vhost.
      '';
    }];
  };
}
