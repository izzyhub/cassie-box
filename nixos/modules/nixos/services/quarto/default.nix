{ lib
, config
, pkgs
, ...
}:
with lib;
let
  cfg = config.mySystem.${category}.${app};
  app = "quarto";
  category = "services";
in
{
  # Not a daemon - no port, no ingress, no homepage tile. This is the authoring
  # toolchain that turns .qmd/.Rmd into PDF and HTML, installed system-wide so
  # RStudio, Jupyter and code-server all pick it up off PATH. It lives under
  # mySystem.services purely so it is toggled from the same block as everything
  # else in the host config.
  options.mySystem.${category}.${app} =
    {
      enable = mkEnableOption "${app} + TeX authoring toolchain";

      texlivePackage = mkOption
        {
          type = lib.types.package;
          description = ''
            TeX Live scheme used for PDF output. texliveMedium covers ordinary
            academic writing; texliveFull is several GB larger and is only worth
            it if a journal class pulls something exotic.
          '';
          default = pkgs.texliveMedium;
          defaultText = literalExpression "pkgs.texliveMedium";
          example = literalExpression "pkgs.texliveFull";
        };

      extraPackages = mkOption
        {
          type = with lib.types; listOf package;
          description = "Extra packages to put alongside the toolchain.";
          default = [ ];
          example = literalExpression "[ pkgs.librsvg ]";
        };
    };

  config = mkIf cfg.enable {

    mySystem.system.packages = [
      pkgs.quarto
      cfg.texlivePackage
      # Quarto ships its own pandoc, but knitr/rmarkdown rendering outside
      # quarto (plain .Rmd) looks for one on PATH.
      pkgs.pandoc
    ]
    ++ cfg.extraPackages;

  };
}
