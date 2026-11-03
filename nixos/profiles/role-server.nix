{ config, lib, pkgs, imports, boot, self, ... }:
# Role for headless servers
# covers raspi's, sbc, NUC etc, anything
# that is headless and minimal for running services

with lib;
{

  config = {

    mySystem = {
      services.monitoring.enable = true;
      services.rebootRequiredCheck.enable = true;
      security.wheelNeedsSudoPassword = false;
    };

    services = {
      logrotate.enable = mkDefault true;
      smartd.enable = mkDefault true;
      pulseaudio.enable = false;
      udisks2.enable = mkDefault false;
    };
    programs.command-not-found.enable = mkDefault false;

    environment.systemPackages = with pkgs; [
      tmux
      btop
    ];
  };
}
