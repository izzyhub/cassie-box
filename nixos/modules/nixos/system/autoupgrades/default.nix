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
  };
  config.system.autoUpgrade = mkIf cfg.enable {
    enable = true;
    flake = "github:izzyhub/cassie-box";
    flags = [
      "-L" # print build logs
      "-accept-flake-config"
    ];
    inherit (cfg) dates;
  };
}
