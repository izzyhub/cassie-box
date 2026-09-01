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
    mariadb.enable = true;
    nginx.enable = true;

    # Dynamic DNS - updates Cloudflare with local IP
    cfDdns = {
      enable = true;
      interface = "eno2";
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
    boat-ray.enable=true;

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
  mySystem.system.motd.networkInterfaces = [ "eno2" ];
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

  # eno2 is the wired NIC (see mySystem.services.cfDdns.interface and
  # mySystem.system.motd.networkInterfaces below, which both name it).
  #
  # It is pinned to a static address rather than left on DHCP: this box is the
  # target of Cloudflare DNS records and a stack of reverse-proxied services,
  # so an address that can move on its own is a liability. It moved once
  # already (10.0.0.249 -> 10.0.0.244) when NetworkManager was enabled.
  #
  # The mechanism: the NetworkManager module sets `networking.useDHCP = false`
  # at normal priority, which silently overrode the `mkDefault true` here and
  # in profiles/global.nix. That disabled dhcpcd outright and left NM as the
  # sole DHCP client - and NM sends a different DHCP client identifier, so the
  # router handed out a different lease.
  #
  # 10.0.0.249 must sit OUTSIDE the router's DHCP pool, or the router will
  # eventually lease it to something else. Check the pool before deploying.
  networking.useDHCP = false;
  networking.interfaces.eno2 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "10.0.0.249";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = {
    address = "10.0.0.1";
    interface = "eno2";
  };
  # Static addressing means no DHCP-supplied resolvers. Tailscale still
  # overlays MagicDNS on top of these when it is up.
  networking.nameservers = [ "10.0.0.1" "1.1.1.1" ];

  # NetworkManager is here for WiFi only. The `unmanaged` list is what keeps it
  # off the wired NICs, so it cannot re-address them behind the static config
  # above. eno1 is listed as well as eno2: NM claims every wired NIC it finds,
  # and a second interface coming up on the same subnet is what makes inbound
  # traffic and ARP replies stop lining up with the cabled port.
  networking.networkmanager = {
    enable = true;
    unmanaged = [
      "interface-name:eno1"
      "interface-name:eno2"
    ];
  };

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
  services.samba = {
    enable = true;
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
  services.samba-wsdd.enable = true; # make shares visible for windows 10 clients

  environment.systemPackages = with pkgs; [
    btrfs-progs
    p7zip
    unrar
    mergerfs
  ];
}
