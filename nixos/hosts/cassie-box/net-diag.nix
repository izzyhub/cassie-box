# Temporary network debugging aid.
#
# Dumps full network state to /var/log/net-diag.log at boot and every 10s
# afterwards, so a box that falls off the network can be diagnosed after the
# fact from the console (or once it is reachable again) rather than by trying
# to win a race with SSH.
#
# Remove this file (and its import) once the network is stable again.
{ lib, pkgs, ... }:
let
  netDiag = pkgs.writeShellScript "net-diag" ''
    export PATH=${lib.makeBinPath [
      pkgs.iproute2
      pkgs.networkmanager
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
      pkgs.nftables
      pkgs.iptables
      pkgs.iw
    ]}:$PATH

    log=/var/log/net-diag.log

    # This reached 20MB in two hours at the original cadence. Keep the tail
    # rather than let a debug aid fill the root filesystem.
    if [ -f "$log" ] && [ "$(stat -c %s "$log")" -gt 5242880 ]; then
      tail -c 1048576 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
    fi

    {
      echo "======== $(date -Is) uptime=$(cut -d' ' -f1 /proc/uptime)s ========"
      echo "--- links (look for LOWER_UP = carrier) ---"
      ip -br link
      echo "--- addresses ---"
      ip -br addr
      echo "--- ipv4 routes ---"
      ip -4 route
      echo "--- arp/neighbours ---"
      ip -4 neigh
      echo "--- NetworkManager devices ---"
      nmcli -t device status 2>&1 || true
      echo "--- NetworkManager connections ---"
      nmcli -t connection show 2>&1 || true
      echo "--- rp_filter (2 = strict, drops asymmetric traffic) ---"
      grep . /proc/sys/net/ipv4/conf/*/rp_filter
      echo "--- resolv.conf ---"
      cat /etc/resolv.conf 2>&1 || true
      echo "--- listening sockets ---"
      ss -lntu
      echo "--- firewall ruleset ---"
      nft list ruleset 2>&1 | head -120 || true
      iptables-save 2>&1 | head -80 || true
      echo "--- wifi association ---"
      iw dev 2>&1 || true
      iw dev wlo1 link 2>&1 || true
      echo "--- ddclient unit ---"
      systemctl status ddclient.service --no-pager --lines=0 2>&1 || true
      echo "--- ddclient log (this boot) ---"
      journalctl -u ddclient.service -b --no-pager --lines=30 2>&1 || true
      echo
    } >> "$log" 2>&1
  '';
in
{
  systemd.services.net-diag = {
    description = "Dump network state for debugging";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = netDiag;
    };
  };

  systemd.timers.net-diag = {
    description = "Periodically dump network state for debugging";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Start early enough to catch the drop-off, which happens seconds in.
      OnBootSec = "2s";
      OnUnitActiveSec = "30s";
      AccuracySec = "1s";
    };
  };

  # Keep the debug log from growing without bound.
  systemd.tmpfiles.rules = [
    "f /var/log/net-diag.log 0644 root root 7d"
  ];
}
