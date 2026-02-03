{ inputs
, ...
}:
{

  nur = inputs.nur.overlays.default;

  # The unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final) system;
      config.allowUnfree = true;
    };
  };

  # Skip flaky psycopg tests that fail in the Nix sandbox
  psycopg-skip-tests = final: prev: {
    python312 = prev.python312.override {
      packageOverrides = pySelf: pySuper: {
        psycopg = pySuper.psycopg.overridePythonAttrs (old: {
          doCheck = false;
        });
      };
    };
    python312Packages = final.python312.pkgs;
  };

  # nixpkgs-overlays = final: prev: {
  #   tandoor-recipes = prev.tandoor-recipes.overridePythonAttrs (old: {
  #     doCheck = false;
  #     propagatedBuildInputs = (old.propagatedBuildInputs or []);
  #     python = old.python.override {
  #       packageOverrides = self: super: {
  #         pytubefix = super.pytubefix.overridePythonAttrs (oldPytube: {
  #           doCheck = false;
  #         });
  #       };
  #     };
  #   });
  # };
}
