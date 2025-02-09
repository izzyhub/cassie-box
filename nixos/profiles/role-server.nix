{ config, lib, pkgs, imports, boot, self, ... }:
# Role for headless servers
# covers raspi's, sbc, NUC etc, anything
# that is headless and minimal for running services

with lib;
{

  config = {

    mySystem.services.monitoring.enable = true;
    mySystem.services.rebootRequiredCheck.enable = true;
    mySystem.security.wheelNeedsSudoPassword = false;

    services.logrotate.enable = mkDefault true;
    services.smartd.enable = mkDefault true;
    programs.command-not-found.enable = mkDefault false;

    hardware.pulseaudio.enable = false;
    environment.systemPackages = with pkgs; [
      tmux
      btop
    ];
    services.udisks2.enable = mkDefault false;
  };
}
