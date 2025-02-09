{ lib, pkgs, self, config, ... }:
with config;
{

  imports = [
    ../modules
  ];

  config = {
    myHome.username = "cassie";
    myHome.homeDirectory = "/home/cassie/";

    myHome.shell.git = {
      enable = true;
      username = "izzy";
      email = "19149206+cassmor@users.noreply.github.com";
      # signingKey = ""; # TODO setup signing keys n shit
    };


    # services.gpg-agent.pinentryPackage = pkgs.pinentry-qt;
    systemd.user.sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      ZDOTDIR = "/home/pinpox/.config/zsh";
    };

    home = {
      # Install these packages for my user
      packages = with pkgs; [
        eza
        htop
        btop
        unzip
      ];

      sessionVariables = {
        # Workaround for alacritty (breaks wezterm and other apps!)
        # LIBGL_ALWAYS_SOFTWARE = "1";
        EDITOR = "nvim";
        VISUAL = "nvim";
        ZDOTDIR = "/home/pinpox/.config/zsh";
      };

    };

  };
}
