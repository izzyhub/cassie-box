{ config
, pkgs
, lib
, ...
}:
with lib; let
  cfg = config.myHome.shell.zsh;
in
{
  options.myHome.shell.zsh = {
    enable = lib.mkEnableOption "zsh shell";
  };

  config = mkIf cfg.enable {
    programs.zsh = {
      enable = true;

      shellAliases = {
        m = "less";
        ls = "${pkgs.eza}/bin/eza --group";
        ll = "${pkgs.eza}/bin/eza --long --all --group --header";
        tm = "tmux attach -t (basename $PWD) || tmux new -s (basename $PWD)";
        x = "exit";
        dup = "git add . ; darwin-rebuild --flake . switch";
        dupb = "git add . ; darwin-rebuild --flake . build --show-trace ; nvd diff /run/current-system result";
        nup = "git add . ; sudo nixos-rebuild --flake . switch";
        nhup = "nh os switch . --dry";
        nvdiff = "nvd diff /run/current-system result";
        ap = "ansible-playbook";
        apb = "ansible-playbook --ask-become";
        gfp = "git fetch -p && git pull";
        gitp = "git push";
        gitpf = "git push -f";
        tf = "terraform";
      };
    };

    programs.nix-index.enable = true;
    programs.zoxide.enable = true;
  };
}
