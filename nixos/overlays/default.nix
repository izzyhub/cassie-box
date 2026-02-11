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

  # Skip flaky psycopg tests that fail in the Nix sandbox.
  # pythonPackagesExtensions composes properly across all Python interpreters
  # and doesn't break passthru attributes (unlike overridePythonAttrs).
  psycopg-skip-tests = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (_pySelf: pySuper: {
        psycopg = pySuper.psycopg.overridePythonAttrs (_old: {
          doCheck = false;
          # psycopg_pool is a separate package; remove it from the import check
          pythonImportsCheck = [ "psycopg" "psycopg_c" ];
        });
      })
    ];
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
