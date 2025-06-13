{ lib, pkgs, self, config, ... }:
with config;
{

  imports = [
    ../modules
  ];

  config = {
    myHome.username = "izzy";
    myHome.homeDirectory = "/home/izzy/";

    myHome.shell.git = {
      enable = true;
      username = "izzy";
      email = "19149206+izzyhub@users.noreply.github.com";
      # signingKey = ""; # TODO setup signing keys n shit
    };


    # services.gpg-agent.pinentryPackage = pkgs.pinentry-qt;
    systemd.user.sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      ZDOTDIR = "/home/izzy/.config/zsh";
    };

    home = {
      # Install these packages for my user
      packages = with pkgs; [
        eza
        htop
        bottom
        unzip
        fd
        ripgrep
      ];

      sessionVariables = {
        # Workaround for alacritty (breaks wezterm and other apps!)
        # LIBGL_ALWAYS_SOFTWARE = "1";
        EDITOR = "nvim";
        VISUAL = "nvim";
        ZDOTDIR = "/home/izzy/.config/zsh";
      };

    };

  };
}
