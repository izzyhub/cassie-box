{ inputs
, config
, lib
, ...
}: {
  imports = [
    ./shell
    ./programs
    ./security
  ];

  options.myHome = {
    username = lib.mkOption {
      type = lib.types.str;
      description = "users username";
      default = "cassie";
    };
    homeDirectory = lib.mkOption {
      type = lib.types.str;
      description = "users homedir";
      default = "cassie";
    };
  };

  # Home-manager defaults
  config = {
    home.stateVersion = "23.11";

    programs = {
      home-manager.enable = true;
      git.enable = true;
    };

    xdg.enable = true;

    nixpkgs.config = {
      allowUnfree = true;
    };
  };
}
