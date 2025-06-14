{ lib
, config
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
      default = "Sun 03:00";
    };


  };
  config.system.autoUpgrade = mkIf cfg.enable {
    enable = true;
    flake = "github:izzyhub/cassie-box";
    flags = [
      "-L" # print build logs
      "--no-write-lock-file" # don't try to write lock file when updating from remote flake
    ];
    inherit (cfg) dates;
  };

}
