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
      # nixpkgs compares HH:MM strictly (`now > lower && now < upper`) and the
      # hourly timer fires on the hour, so the bounds must not sit on :00. A
      # 04:00-05:00 window never matched: with allowReboot the upgrade runs
      # `nixos-rebuild boot` and only activates a new kernel by rebooting, so
      # kernel-changing upgrades sat unactivated indefinitely. This catches 04:00 and 05:00.
      default = { lower = "03:30"; upper = "05:30"; };
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
