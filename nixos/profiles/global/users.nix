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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZS9J1ydflZ4iJdJgO8+vnN8nNSlEwyn9tbWU9OcysW truxnell@home"
    ]; # TODO do i move to ingest github creds?

    # packages = [ pkgs.home-manager ];
  };
  users.users.cassie = {
    isNormalUser = true;
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

}
