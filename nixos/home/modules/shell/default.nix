{ config, lib, ... }: {
  imports = [
    ./fish
    ./starship
    ./wezterm
    ./git
    ./zsh
  ];

  config = {
    myHome.shell.zsh.enable = true;
  };
}
