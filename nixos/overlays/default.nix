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

  # r-V8 fails its load test with undefined `icu_78::...` symbols. nodejs 22's
  # static libv8.a is now built against system ICU (its v8.pc lists
  # `-licui18n -licuuc`), but V8's configure only links `-lv8`. Supply the
  # full link line via the V8_PKG_LIBS hook configure already honours, using
  # the same ICU node was built with. Pulled in by rPackages.gt (via
  # juicyjuice) in the rstudio-server module. Drop once nixpkgs fixes it.
  r-v8-icu = _final: prev: {
    rPackages = prev.rPackages.override {
      overrides = {
        V8 = prev.rPackages.V8.overrideAttrs (old:
          let
            libv8 = prev.nodejs-slim_22.libv8;
            # Must be node's ICU exactly (78 here); pkgs.icu lags behind.
            icu = prev.lib.findFirst (p: prev.lib.hasPrefix "icu4c-" (p.name or ""))
              (throw "r-v8-icu: nodejs-slim_22 no longer has icu4c in buildInputs")
              prev.nodejs-slim_22.buildInputs;
          in
          {
            buildInputs = (old.buildInputs or [ ]) ++ [ icu ];
            env = (old.env or { }) // {
              V8_PKG_LIBS = "-L${libv8}/lib -lv8 -pthread -L${icu}/lib -licui18n -licuuc";
            };
          });
      };
    };
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
