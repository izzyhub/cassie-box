{ config
, lib
, pkgs
, ...
}: {
  # Import disko configuration
  imports = [
    ./disko.nix
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
  networking.useDHCP = lib.mkDefault true;
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
