{ lib
, config
, pkgs
, ...
}:

with lib;
let
  cfg = config.mySystem.services.podman;
in
{
  options.mySystem.services.podman.enable = mkEnableOption "Podman";

  config = mkIf cfg.enable
    {
      virtualisation.podman = {
        enable = true;

        dockerCompat = true;
        #extraPackages = [ pkgs.zfs ];

        # regular cleanup
        autoPrune.enable = true;
        autoPrune.dates = "weekly";

        # and add dns
        defaultNetwork.settings = {
          dns_enabled = true;
        };
      };
      virtualisation.oci-containers = {
        backend = "podman";
      };

      environment.systemPackages = with pkgs; [
        podman-tui # status of containers in the terminal
      ];

      networking.firewall.interfaces.podman0.allowedUDPPorts = [ 53 ];

      # extra user for containers
      users.users.kah = {
        uid = 568;
        group = "kah";
        # The shared media trees are group-owned by `media` so that the *arr
        # stack and boat-ray can both write them; `kah` is the user every *arr
        # runs as, so it needs that group to keep writing the library it owns.
        extraGroups = [ "media" ];
      };
      users.groups.kah = {
        gid = 568;
      };
      users.users.cassie.extraGroups = [ "kah" ];
      users.users.izzy.extraGroups = [ "kah" ];
    };

}
