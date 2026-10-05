{ lib
, config
, pkgs
, self
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "victoriametrics";
  category = "services";
  description = "Metric storage";
  # image = "";
  user = app; #string
  group = app; #string
  port = 8428; #int
  portAM = 9093; #int
  portVAM = 8880; #int

  appFolder = "/var/lib/private/${app}";
  persistentFolder = "${config.mySystem.persistentFolder}/var/lib/${appFolder}";
  host = "${app}" + (if cfg.dev then "-dev" else "");
  url = "${host}.${config.networking.domain}";
  hostAM = "alertmanager" + (if cfg.dev then "-dev" else "");
  urlAM = "${hostAM}.${config.networking.domain}";
  hostVAM = "vmalert" + (if cfg.dev then "-dev" else "");
  urlVAM = "${hostVAM}.${config.networking.domain}";


in
{
  options.mySystem.${category}.${app} =
    {
      enable = mkEnableOption "${app}";
      addToHomepage = mkEnableOption "Add ${app} to homepage" // { default = true; };
      monitor = mkOption
        {
          type = lib.types.bool;
          description = "Enable gatus monitoring";
          default = true;
        };
      prometheus = mkOption
        {
          type = lib.types.bool;
          description = "Enable prometheus scraping";
          default = true;
        };
      addToDNS = mkOption
        {
          type = lib.types.bool;
          description = "Add to DNS list";
          default = true;
        };
      dev = mkOption
        {
          type = lib.types.bool;
          description = "Development instance";
          default = false;
        };
      backup = mkOption
        {
          type = lib.types.bool;
          description = "Enable backups";
          default = true;
        };



    };

  config = mkIf cfg.enable {

    # Alerts go Alertmanager -> ntfy-alertmanager (loopback) -> huci's ntfy over the
    # tailnet. The bridge holds the ntfy token, so Alertmanager needs no secrets.
    assertions = [
      {
        assertion = config.mySystem.services.ntfy-alertmanager.enable;
        message = ''
          victoriametrics routes Alertmanager to the ntfy-alertmanager bridge on
          loopback. Enable mySystem.services.ntfy-alertmanager on this host, or
          alerts will be posted to a port nothing is listening on.
        '';
      }
    ];

    users.users.izzy.extraGroups = [ group ];
    users.users.cassie.extraGroups = [ group ];


    # Folder perms - only for containers
    # systemd.tmpfiles.rules = [
    # "d ${appFolder}/ 0750 ${user} ${group} -"
    # ];

    environment.persistence."${config.mySystem.persistentFolder}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [{ directory = appFolder; }];
    };


    ## service
    services.victoriametrics = {
      enable = true;
      retentionPeriod = "12";
    };

    services.vmalert = {
      enable = true;
      settings = {
        "datasource.url" = "http://localhost:${builtins.toString port}";
        "notifier.url" = [ "http://localhost:${builtins.toString portAM}" ];
      };
      rules = {
        groups = [{
          name = "alerting-rules";
          rules = import ./alert-rules.nix { inherit lib; };
        }];
      };
    };

    services.prometheus.alertmanager = {
      enable = true;
      webExternalUrl = "https://alertmanager.${config.networking.domain}";
      configuration = {
        route = {
          receiver = "ntfy";
          # One notification per (kind of problem, box), and long enough waits
          # that a deploy's restart churn settles into one message.
          group_by = [ "alertname" "instance" ];
          group_wait = "5m";
          group_interval = "5m";
          # Unfixed problems re-notify daily: a failed unit nobody fixed is still
          # broken tomorrow.
          repeat_interval = "24h";
        };
        receivers = [
          {
            name = "ntfy";
            # The bridge renders the notification (title, priority from `severity`,
            # resolved handling); raw webhook JSON at ntfy would be an unreadable blob.
            webhook_configs = [{
              url = "http://127.0.0.1:${toString config.mySystem.services.ntfy-alertmanager.listenPort}/";
              send_resolved = true;
            }];
          }
        ];
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
        url = "https://${url}";
        interval = "1m";
        conditions = [ "[CONNECTED] == true" "[STATUS] == 200" "[RESPONSE_TIME] < 50" ];
      }
    ];

    ### Ingress
    # victoriametrics
    services.nginx.virtualHosts =
      config.lib.mySystem.mkVhost { inherit app port; host = url; }
      // config.lib.mySystem.mkVhost { app = "alertmanager"; host = urlAM; port = portAM; }
      // config.lib.mySystem.mkVhost { app = "vmalert"; host = urlVAM; port = portVAM; websockets = true; }
      ;




    ### firewall config

    networking.firewall = {
      allowedTCPPorts = [ port ];
      # allowedUDPPorts = [ port ];
    };

    ### backups
    warnings = [
      (mkIf (!cfg.backup && config.mySystem.purpose != "Development")
        "WARNING: Backups for ${app} are disabled!")
    ];

    services.restic.backups = mkIf cfg.backup (config.lib.mySystem.mkRestic
      {
        inherit app user;
        paths = [ appFolder ];
        inherit appFolder;
      });


    # services.postgresqlBackup = {
    #   databases = [ app ];
    # };



  };
}
