{ inputs
, ...
}:
{

  nur = inputs.nur.overlays.default;

  # Lix, taken from nixpkgs' `lixPackageSets` rather than the upstream
  # lix-project/nixos-module flake.
  #
  # The old `lix-module` flake input was removed for two reasons:
  #  1. Its tarballs are pinned by rev against git.lix.systems' on-demand
  #     Forgejo archive endpoint, which hangs indefinitely for revs the server
  #     hasn't already cached. That was the `nix eval` timeout.
  #  2. It never actually did anything here. Its only effect is setting
  #     `nixpkgs.overlays`, which nixpkgs silently ignores when `pkgs` is
  #     imported externally and passed to `nixosSystem` (see flake.nix) --
  #     so the system was quietly running upstream CppNix.
  #
  # Upstream's release-branch module is `lixFromNixpkgs` anyway, so this
  # overlay is the same thing without the network dependency. Pin an explicit
  # version set rather than `pkgs.lix`, which trails the release branch.
  # 26.05 dropped 2.93 (`lixPackageSets.stable` is 2.94.2).
  lix = _final: prev:
    let
      lixSet = prev.lixPackageSets.lix_2_94;
    in
    {
      inherit (lixSet) lix nix-eval-jobs nix-direnv;

      nixVersions = prev.nixVersions // {
        stable = lixSet.lix;
        # Escape hatch for anything that genuinely needs to link CppNix.
        stable_upstream = prev.nixVersions.stable;
      };
    };

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
