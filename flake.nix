{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # impermanence
    # https://github.com/nix-community/impermanence
    impermanence.url = "github:nix-community/impermanence";

    # nur
    nur.url = "github:nix-community/NUR";

    # nix-community hardware quirks
    # https://github.com/nix-community
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # home-manager - home user+dotfile manager
    # https://github.com/nix-community/home-manager
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix - secrets with mozilla sops
    # https://github.com/Mic92/sops-nix
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-index database
    # https://github.com/nix-community/nix-index-database
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-inspect = {
      url = "github:bluskript/nix-inspect";
    };


  };

  outputs =
    { self
    , nixpkgs
    , sops-nix
    , home-manager
    , impermanence
    , ...
    } @ inputs:
    let
      inherit (self) outputs;
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux"
        "x86_64-linux"
      ];

    in
    rec {

      # Use nixpkgs-fmt for 'nix fmt'
      formatter = forAllSystems (system: nixpkgs.legacyPackages."${system}".nixpkgs-fmt);

      # extend lib with custom functions
      lib = nixpkgs.lib.extend (
        final: prev: {
          inherit inputs;
          myLib = import ./nixos/lib { inherit inputs; lib = final; };
        }
      );

      nixosConfigurations =
        with self.lib;
        let
          specialArgs = {
            inherit inputs outputs;
          };
          overlays = import ./nixos/overlays { inherit inputs; };
          mkNixosConfig =
            { hostname
            , system ? "x86_64-linux"
            , nixpkgs ? inputs.nixpkgs
            , hardwareModules ? [ ]
            # basemodules is the base of the entire machine building
            # here we import all the modules and setup home-manager
            , baseModules ? [
              sops-nix.nixosModules.sops
              sops-nix.nixosModules.sops
              ./nixos/profiles/global.nix # all machines get a global profile
              ./nixos/modules/nixos # all machines get nixos modules
              ./nixos/hosts/${hostname}   # load this host's config folder for machine-specific config
              {
                home-manager = {
                  useUserPackages = true;
                  useGlobalPkgs = true;
                  extraSpecialArgs = {
                    inherit inputs hostname system;
                  };
                };
              }
            ]
            , profileModules ? [ ]
            }:
            nixpkgs.lib.nixosSystem {
              inherit system lib;
              modules = baseModules ++ hardwareModules ++ profileModules;
              specialArgs = { inherit self inputs nixpkgs; };

              pkgs = import nixpkgs {
                inherit system;
                overlays = builtins.attrValues overlays;
                config = {
                  allowUnfree = true;
                  allowUnfreePredicate = _: true;
                  # TODO remove when sonarr and friends update
                  permittedInsecurePackages = [
                    "aspnetcore-runtime-6.0.36"
                    "aspnetcore-runtime-wrapped-6.0.36"
                    "dotnet-sdk-6.0.428"
                    "dotnet-sdk-wrapped-6.0.428"
                  ];

                };
              };

            };
      in
      rec {
        "cassie-box" = mkNixosConfig {
          hostname = "cassie-box";
          system = "x86_64-linux";
          hardwareModules = [
            ./nixos/profiles/hw-generic-x86.nix
          ];
          profileModules = [
              ./nixos/profiles/role-server.nix
              {
                home-manager.users.izzy = ./nixos/home/izzy/server.nix;
                home-manager.users.cassie = ./nixos/home/cassie/server.nix;
              }
          ];
        };
      };
      top =
        let
          nixtop = nixpkgs.lib.genAttrs
            (builtins.attrNames inputs.self.nixosConfigurations)
            (attr: inputs.self.nixosConfigurations.${attr}.config.system.build.toplevel);
        in
          nixtop;
    };
}
