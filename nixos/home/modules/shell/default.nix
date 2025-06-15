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
    myHome.shell.fish.enable = true;
    myHome.shell.zsh.enable = false;
    myHome.shell.starship.enable = true;
  };
}
