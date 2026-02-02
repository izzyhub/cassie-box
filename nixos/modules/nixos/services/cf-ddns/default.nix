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

  # Script to update Cloudflare DNS with local IP
  updateScript = pkgs.writeShellScript "cf-ddns-update" ''
    set -euo pipefail

    # Source the environment file for CF_API_TOKEN and CF_ZONE_ID
    set -a
    source "$CREDENTIALS_FILE"
    set +a

    # Get local IP from interface
    LOCAL_IP=$(${pkgs.iproute2}/bin/ip -4 addr show ${cfg.interface} | ${pkgs.gnugrep}/bin/grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

    if [ -z "$LOCAL_IP" ]; then
      echo "ERROR: Could not get IP from interface ${cfg.interface}"
      exit 1
    fi

    echo "Local IP: $LOCAL_IP"

    # Function to update a DNS record
    update_record() {
      local record_name="$1"
      local record_type="A"

      echo "Updating $record_name..."

      # Get existing record
      local response=$(${pkgs.curl}/bin/curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=$record_type&name=$record_name" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

      local record_id=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.result[0].id // empty')
      local current_ip=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.result[0].content // empty')

      if [ -z "$record_id" ]; then
        echo "  Record not found, creating..."
        ${pkgs.curl}/bin/curl -s -X POST \
          "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
          -H "Authorization: Bearer $CF_API_TOKEN" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$LOCAL_IP\",\"ttl\":300,\"proxied\":false}" \
          | ${pkgs.jq}/bin/jq -r 'if .success then "  Created successfully" else "  Error: \(.errors)" end'
      elif [ "$current_ip" = "$LOCAL_IP" ]; then
        echo "  Already up to date ($current_ip)"
      else
        echo "  Updating from $current_ip to $LOCAL_IP..."
        ${pkgs.curl}/bin/curl -s -X PUT \
          "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$record_id" \
          -H "Authorization: Bearer $CF_API_TOKEN" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$LOCAL_IP\",\"ttl\":300,\"proxied\":false}" \
          | ${pkgs.jq}/bin/jq -r 'if .success then "  Updated successfully" else "  Error: \(.errors)" end'
      fi
    }

    # Update each configured record
    ${concatMapStringsSep "\n" (record: "update_record \"${record}\"") cfg.records}

    echo "Done!"
  '';

in
{
  options.mySystem.${category}.cfDdns = {
    enable = mkEnableOption "Cloudflare Dynamic DNS (local IP)";

    interface = mkOption {
      type = types.str;
      default = "eno2";
      description = "Network interface to get local IP from";
    };

    records = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "example.com" "*.example.com" ];
      description = "DNS records to update with local IP";
    };

    interval = mkOption {
      type = types.str;
      default = "5m";
      description = "How often to check and update DNS records";
    };
  };

  config = mkIf cfg.enable {
    # Secrets - reuse ACME credentials structure but add zone ID
    sops.secrets."${category}/${app}/env" = {
      sopsFile = ./secrets.sops.yaml;
      restartUnits = [ "${app}.service" ];
    };

    systemd.services.${app} = {
      description = "Cloudflare Dynamic DNS Updater (Local IP)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        Environment = "CREDENTIALS_FILE=${config.sops.secrets."${category}/${app}/env".path}";
        ExecStart = updateScript;
        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.${app} = {
      description = "Cloudflare Dynamic DNS Update Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = cfg.interval;
        RandomizedDelaySec = "30s";
      };
    };
  };
}
