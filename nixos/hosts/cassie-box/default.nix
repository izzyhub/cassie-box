{ config
, lib
, pkgs
, ...
}: {
  mySystem.purpose = "Cassie Services";
  mySystem.system.impermanence.enable = true;
  mySystem.system.autoUpgrade.enable = true; # bold move cotton
  mySystem.services = {
    openssh.enable = true;
    podman.enable = true;

    # databases
    postgresql.enable = true;
    mariadb.enable = true;
    nginx.enable = true;

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
    cross-seed.enable = true;
    prowlarr.enable = true;
    autobrr.enable = true;
    plex.enable = true;
    maintainerr.enable = true;
    immich.enable = true;
    filebrowser.enable = true;
    atuin.enable = true;
    syncthing = {
      enable = true;
      syncPath = "/zfs/syncthing/";
    };
    navidrome.enable = true;
    paperless.enable = true;
    redbot.enable=true;
    silverbullet.enable=true;
    tandoor.enable=true;
    open-webui.enable=true;


    invidious.enable = true;
    thelounge.enable = true;
    changedetection.enable = true;
    linkding.enable = true;
    vikunja.enable = true;

    # monitoring
    victoriametrics.enable = true;
    grafana.enable = true;
    nextdns-exporter.enable = true;
    unpoller.enable = true;

    hs110-exporter.enable = true;

  };
  mySystem.security.acme.enable = true;
  mySystem.containers = {
    calibre.enable = true;
  };

  mySystem.persistentFolder = "/persist";
  mySystem.system.motd.networkInterfaces = [ "enp1s0" ];

  # Intel qsv
  boot.kernelParams = [
    "i915.enable_guc=2"
  ];
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-compute-runtime
    ];
  };

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

    fileSystems."/boot" =
      {
        device = "/dev/disk/by-label/EFI";
        fsType = "vfat";
      };


  fileSystems."/" =
  {
      device = "/dev/disk/by-id/ata-CT2000BX500SSD1_2425E8B9A602"
      fsType = "ext4";
  };

  fileSystems."/nix" =
  {

  };

  fileSystems."/persist" =
    {
      device = "rpool/safe/persist";
      fsType = "zfs";
      neededForBoot = true; # for impermanence
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/76FA-78DF";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
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
        "backup" = {
          "path" = "/zfs/backup";
          "read only" = "no";
        };
        "documents" = {
          "path" = "/zfs/documents";
          "read only" = "no";
        };
        "natflix" = {
          "path" = "/tank/natflix";
          "read only" = "no";
        };
        "scans" = {
          "path" = "/zfs/documents/scans";
          "read only" = "no";
        };
        "paperless" = {
          "path" = "/zfs/documents/paperless/inbound";
          "read only" = "no";
        };
      };

    };
    services.samba-wsdd.enable = true; # make shares visible for windows 10 clients

    environment.systemPackages = with pkgs; [
      btrfs-progs
      p7zip
      unrar
    ];



    environment.persistence."${config.mySystem.system.impermanence.persistPath}" = lib.mkIf config.mySystem.system.impermanence.enable {
      directories = [ "/var/lib/samba/" ];
    };

}
