{ config, lib, ... }: {
  imports = [
    ./fish
    ./starship
    ./wezterm
    ./git
    ./zsh
  ];

  config = {
    # Only enable fish by default
    myHome.shell = {
      fish.enable = true;
      zsh.enable = false;
      starship.enable = true;
    };
  };
}
