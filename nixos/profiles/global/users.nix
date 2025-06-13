{ pkgs
, config
, ...
}:
let
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
in
{

  sops.secrets = {
    cassie-password = {
      sopsFile = ./secrets.sops.yaml;
      neededForUsers = true;
    };
    izzy-password = {
      sopsFile = ./secrets.sops.yaml;
      neededForUsers = true;
    };

  };

  users.users.izzy = {
    isNormalUser = true;
    uid = 1000;
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets.izzy-password.path;
    extraGroups =
      [
        "wheel"
      ]
      ++ ifTheyExist [
        "network"
        "samba-users"
        "docker"
        "podman"
        "audio" # pulseaudio
        "libvirtd"
      ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGlH7ndB1lbWNBlOFvuPLVFOKbbJDJE4M+oNtEGw0kqi m2-14-mac"
    ]; # TODO do i move to ingest github creds?

     packages = [ pkgs.home-manager ];
  };
  users.users.cassie = {
    isNormalUser = true;
    uid = 1001;
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets.cassie-password.path;
    extraGroups =
      [
        "wheel"
      ]
      ++ ifTheyExist [
        "network"
        "samba-users"
        "docker"
        "podman"
        "audio" # pulseaudio
        "libvirtd"
      ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZS9J1ydflZ4iJdJgO8+vnN8nNSlEwyn9tbWU9OcysW truxnell@home"
    ]; # TODO do i move to ingest github creds?

    # packages = [ pkgs.home-manager ];
  };

  # Service users/groups with fixed IDs for impermanence
  users.users = {
    acme = { uid = 2001; group = "acme"; isSystemUser = true; };
    calibre-web = { uid = 2002; group = "calibre-web"; isSystemUser = true; };
    navidrome = { uid = 2003; group = "navidrome"; isSystemUser = true; };
    redis-paperless = { uid = 2004; group = "redis-paperless"; isSystemUser = true; };
    searx = { uid = 2005; group = "searx"; isSystemUser = true; };
    silverbullet = { uid = 2006; group = "silverbullet"; isSystemUser = true; };
    thelounge = { uid = 2007; group = "thelounge"; isSystemUser = true; };
    vikunja = { uid = 2008; group = "vikunja"; isSystemUser = true; };
  };

  users.groups = {
    acme = { gid = 2001; };
    calibre-web = { gid = 2002; };
    code-server = { gid = 2003; };
    grafana = { gid = 2004; };
    navidrome = { gid = 2005; };
    podman = { gid = 2006; };
    redis-paperless = { gid = 2007; };
    searx = { gid = 2008; };
    silverbullet = { gid = 2009; };
    tandoor-recipes = { gid = 2010; };
    thelounge = { gid = 2011; };
    vikunja = { gid = 2012; };
  };

}
