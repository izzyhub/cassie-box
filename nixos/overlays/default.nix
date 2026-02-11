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
  # Must override on paperless-ngx directly because it creates its own
  # isolated Python environment, so a global python312 overlay has no effect.
  psycopg-skip-tests = final: prev: {
    paperless-ngx = prev.paperless-ngx.overridePythonAttrs (old: {
      python = old.python.override {
        packageOverrides = pySelf: pySuper: {
          psycopg = pySuper.psycopg.overridePythonAttrs (oldPsycopg: {
            doCheck = false;
          });
        };
      };
    });
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
