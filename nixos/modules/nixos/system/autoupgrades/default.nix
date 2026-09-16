{ lib
, config
, pkgs
, ...
}:
let
  cfg = config.mySystem.system.autoUpgrade;
in
with lib;
{
  options.mySystem.system.autoUpgrade = {
    enable = mkEnableOption "system autoUpgrade";
    dates = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
    };
    allowReboot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Reboot after an upgrade that changed the kernel, initrd or modules,
        but only inside `rebootWindow`. Without this a headless box never
        picks up kernel updates.
      '';
    };
    rebootWindow = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { lower = "04:00"; upper = "05:00"; };
      description = "Local-time window in which an upgrade may reboot the machine.";
    };
  };
  config.system.autoUpgrade = mkIf cfg.enable {
    enable = true;
    flake = "github:izzyhub/cassie-box";
    flags = [
      "-L" # print build logs
      # Two dashes. With one, nixos-rebuild-ng rejects the argument and the
      # upgrade unit fails before doing anything - which is how this box sat
      # on a stale generation for weeks.
      "--accept-flake-config"
    ];
    inherit (cfg) dates allowReboot rebootWindow;
  };
}
