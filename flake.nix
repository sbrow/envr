{
  description = "Manage your .env files.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      nixpkgs-unstable,
      self,
      treefmt-nix,
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"

        "aarch64-darwin"
      ];

      perSystem =
        {
          pkgs,
          system,
          inputs',
          ...
        }:
      let
        mysqlite = pkgs.sqlite.overrideAttrs (old: {
                configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-deserialize" ];
              });
      in
        {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;

            overlays = [
              (_final: _prev: { unstable = inputs'.nixpkgs-unstable.legacyPackages; })
            ];
          };

          treefmt = {
            projectRootFile = "flake.nix";
            settings.global.excludes = [
              ".direnv/**"
              ".jj/**"
              ".env"
              ".envrc"
              ".env.local"
            ];

            programs.nixpkgs-fmt.enable = true;
          };

          packages.default = pkgs.stdenv.mkDerivation rec {
            pname = "envr";
            version = "0.2.0";
            src = ./.;

            nativeBuildInputs = [
              pkgs.unstable.odin
              pkgs.pkg-config
            ];

            buildInputs = [
              pkgs.libsodium
              mysqlite
            ];

            buildPhase = ''
              runHook preBuild
              echo '${version}' > version.txt
              odin build . -o:speed -out:${pname}
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 ${pname} $out/bin/${pname}
              runHook postInstall
            '';
          };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              fd
              nushell

              libsodium
              mysqlite
              unstable.odin
              unstable.ols

              # Build tools
              zip

              # IDE
              unstable.helix
              typescript-language-server
              vscode-langservers-extracted
            ];
          };
        };
    };
}
