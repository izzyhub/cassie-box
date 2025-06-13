{ lib, config, ... }:
with lib;
{
  imports = [
    ./system
    ./programs
    ./services
    ./editor
    ./containers
    ./lib.nix
    ./security
  ];

  options.mySystem.persistentFolder = mkOption {
    type = types.str;
    description = "persistent folder for nixos mutable files";
    default = "/mnt/data/persist";
  };

  options.mySystem.domain = mkOption {
    type = types.str;
    description = "domain for hosted services";
    default = "";
  };
  options.mySystem.internalDomain = mkOption {
    type = types.str;
    description = "domain for local devices";
    default = "";
  };
  options.mySystem.purpose = mkOption {
    type = types.str;
    description = "System purpose";
    default = "Production";
  };

  options.mySystem.dataFolder = mkOption {
    type = types.str;
    description = "Data folder for shared storage";
    default = "/mnt/data";
  };

  options.mySystem.system.impermanence = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable impermanence";
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.mySystem.persistentFolder} 777 - - -" #The - disables automatic cleanup, so the file wont be removed after a period
    ];

  };
}
