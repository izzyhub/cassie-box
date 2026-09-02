{ config
, lib
, pkgs
, ...
}: {
  # Import disko configuration
  imports = [
    ./disko.nix
    # Temporary: dumps network state to /var/log/net-diag.log. Remove once
    # the wired link is stable.
    ./net-diag.nix
  ];

  # Create directories for mergerfs
  systemd.tmpfiles.rules = [
    "d /mnt/data1 0755 root root -"
    "d /mnt/data2 0755 root root -"
    "d /mnt/data 0755 root root -"
  ];

  #fileSystems."/" = {
  #device = "6dc22d81-e932-42f3-9b38-7f5d7e14a1fe";
  #fsType = "ext4";
  #};
  #fileSystems."/boot" = {
  #device = "/dev/disk/by-uuid/53A5-AD6F";
  #fsType = "vfat";
  #options = ["fmaks=022" "dmask=0022" ];
  #};

  # Add mergerfs configuration
  fileSystems."/mnt/data" = {
    device = "/mnt/data1:/mnt/data2";
    fsType = "fuse.mergerfs";
    options = [
      "rw"
      "use_ino"
      "allow_other"
      "func.getattr=newest"
      "category.create=ff"
      "category.action=ff"
      "category.search=ff"
    ];
  };

  mySystem.purpose = "Cassie Services";
  mySystem.system.impermanence.enable = false;
  mySystem.system.autoUpgrade.enable = true; # bold move cotton
  mySystem.dataFolder = "/mnt/data";
  mySystem.services = {
    openssh.enable = true;
    podman.enable = true;

    # databases
    postgresql.enable = true;
    # STEP 1 of the 15 -> 17 upgrade: deploy this, then run
    # `upgrade-pg-cluster` as root. Remove once step 3 has landed.
    postgresql.upgradeTo = pkgs.postgresql_17;
    mariadb.enable = true;
    nginx.enable = true;

    # Dynamic DNS - updates Cloudflare with local IP.
    # `interface` is deliberately unset: the address is read from whichever
    # link currently holds the default route, so the record follows the box
    # when it falls back from eno2 to WiFi.
    cfDdns = {
      enable = true;
      records = [ "cassies.app" "*.cassies.app" ];
    };

    # cloudflare-tunnel = {
    #   enable = false;  # Disabled - using internal-only setup with Tailscale
    # };

    vaultwarden.enable = true;
    homepage.enable = true;

    overseerr.enable = true;
    tautulli.enable = true;

    searxng.enable = true;
    whoogle.enable = true;
    redlib.enable = true;

    code-server.enable = true;

    calibre-web.enable = true;

    sonarr.enable = true;
    radarr.enable = true;
    recyclarr.enable = true;
    lidarr.enable = true;
    readarr.enable = true;
    sabnzbd.enable = true;
    qbittorrent.enable = true;
    qbittorrent-lts.enable = true;
    prowlarr.enable = true;
    plex.enable = true;
    maintainerr.enable = true;
    immich.enable = true;
    #romm.enable = true;
    filebrowser.enable = true;
    syncthing = {
      enable = true;
      syncPath = "/mnt/data/syncthing/";
    };
    navidrome.enable = true;
    paperless.enable = true;
    redbot.enable=true;
    silverbullet.enable=true;
    tandoor.enable=true;
    boat-ray = {
      enable = true;
      # Peer reached over the tailnet by its MagicDNS name.
      peerAddress = "sophie-001-1.tail6b6f7.ts.net:50051";
    };

    jellyfin = {
      enable = true;
    };

    invidious.enable = true;
    changedetection.enable = true;
    linkding.enable = true;
    vikunja.enable = true;

    # monitoring
    victoriametrics.enable = true;
    grafana.enable = true;
    #cockpit.enable = true;
  };
  mySystem.security.acme.enable = true;
  mySystem.containers = {
    calibre.enable = true;
  };

  mySystem.persistentFolder = "/persist";
  # Both links, so the login banner shows the WiFi address when eno2 is unplugged.
  mySystem.system.motd.networkInterfaces = [ "eno2" "wlo1" ];
  mySystem.system.motd.enable = true;

  # Intel qsv
  boot.kernelParams = [
    "i915.enable_guc=2"
  ];
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
      intel-compute-runtime
      vpl-gpu-rt
      intel-media-sdk
      intel-ocl
    ];
  };

  # Enable firmware for Intel GPU
  hardware.enableAllFirmware = true;

  boot = {

    initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
    initrd.kernelModules = [ ];
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];

    # for managing/mounting ntfs
    supportedFilesystems = [ "ntfs" ];

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      # why not ensure we can memtest workstatons easily?
      # TODO check whether this is actually working, cant see it in grub?
      grub.memtest86.enable = true;
    };
  };

  networking.hostName = "cassie-box"; # Define your hostname.
  networking.hostId = "0a90730f";

  # eno2 is the wired NIC and wlo1 the WiFi radio (confirmed from net-diag.log;
  # there is no eno1 on this box).
  #
  # Nothing here is tied to a particular LAN. This box is meant to be handed
  # over, plugged into ethernet and power on someone else's network, and come
  # up unattended - so no static address, gateway or resolver is set, because
  # every one of those would be wrong somewhere else. NetworkManager runs DHCP
  # on both links and autoconnects the wired one, which wins on route metric
  # whenever a cable is present; WiFi is the fallback.
  #
  # (A static 10.0.0.249 lived here briefly. It was never needed: the address
  # that appeared to "move" was a DHCP lease on wlo1 while eno2 had no
  # carrier. Check `ip -br link` for NO-CARRIER before suspecting addressing.)
  networking.networkmanager.enable = true;

  # Without this the kernel keeps routes belonging to a link that has no
  # carrier, so an unplugged eno2 black-holes LAN traffic instead of falling
  # back to WiFi. With it set, those routes show as `dead linkdown` and are
  # skipped during lookup.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.ignore_routes_with_linkdown" = 1;
    "net.ipv4.conf.default.ignore_routes_with_linkdown" = 1;
  };

  # This box sits directly on whatever LAN it is plugged into, so it must not
  # accept a tailnet subnet route covering that LAN. sophie-001 advertises
  # 10.0.0.0/24; a node accepting it gets that prefix in tailscale's table 52,
  # which the ip rule at priority 5270 consults BEFORE `main` - so every local
  # address is pulled into the tunnel and the local network becomes
  # unreachable, including hosts on the same switch. That is doubly important
  # once this is handed over, since 10.0.0.0/24 is a very common home range
  # and the collision would be silent.
  services.tailscale.extraSetFlags = [ "--accept-routes=false" ];

  # MagicDNS needs real split DNS, which /etc/resolv.conf cannot express.
  #
  # Without this, NetworkManager owns resolv.conf (main.dns=default, via
  # openresolv) and tailscaled can only append 100.100.100.100 to the same
  # flat nameserver list. Resolution then depends on ordering: if the LAN
  # resolver from DHCP is consulted first it answers NXDOMAIN for a
  # `*.ts.net` name, and glibc treats that as authoritative and stops - it
  # only falls through to the next nameserver on SERVFAIL or timeout. The
  # result is `Name does not resolve` for a peer that is up and reachable,
  # reappearing on any DHCP renewal or eno2<->wlo1 failover that rewrites
  # the list.
  #
  # With resolved, NetworkManager hands per-link DHCP servers to it and
  # tailscaled installs `~tail6b6f7.ts.net` as a routing domain pointed at
  # 100.100.100.100, so tailnet names are resolved by tailscale alone and
  # everything else is unaffected - regardless of which link is up.
  services.resolved.enable = true;
  networking.networkmanager.dns = "systemd-resolved";

  networking.firewall = {
    enable = true;
    allowPing = true;
    # A host with both a wired and a WiFi interface up can legitimately
    # receive a packet on an interface that is not the one its return route
    # would pick. Strict reverse-path filtering drops those silently, which
    # looks exactly like the box being unreachable while it can still reach
    # out. Loose mode only requires that a route back exists at all.
    checkReversePath = "loose";
  };
  # mDNS, so the box is findable as `cassie-box.local` without anyone knowing
  # its address. This is the piece that makes "plug in ethernet and power" work
  # on a network nobody has configured: DHCP hands out an arbitrary address,
  # and this is how you find it again.
  #
  # nssmdns4 also lets the box itself resolve other .local names.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # Disabled for now: the `hosts allow` line below is a stale 10.8.10. subnet
  # that matches neither the current LAN nor wherever this box ends up, so the
  # shares deny everyone anyway. Settings are kept rather than deleted - to
  # bring it back, set enable = true and replace `hosts allow` with something
  # that matches the target network (or drop the IP allow-list and rely on the
  # firewall plus Samba user auth).
  services.samba = {
    enable = false;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "cassie-box";
        "netbios name" = "cassie-box";
        "security" = "user";
        "hosts allow" = "10.8.10. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      "documents" = {
        "path" = "/mnt/data/documents";
        "read only" = "no";
      };
      "paperless" = {
        "path" = "/mnt/data/paperless/inbound";
        "read only" = "no";
      };
    };
  };
  # Follows services.samba above; advertising shares that are not served is
  # just noise on the network.
  services.samba-wsdd.enable = false; # make shares visible for windows 10 clients

  environment.systemPackages = with pkgs; [
    btrfs-progs
    p7zip
    unrar
    mergerfs
  ];
}
