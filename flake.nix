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
    inputs@{ flake-parts
    , nixpkgs
    , nixpkgs-unstable
    , self
    , treefmt-nix
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];
      systems = [ "x86_64-linux" ];

      perSystem =
        { pkgs, system, inputs', ... }: {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;

            overlays = [
              (_final: _prev: { unstable = inputs'.nixpkgs-unstable.legacyPackages; })
            ];
          };

          treefmt = {
            # Used to find the project root
            projectRootFile = "flake.nix";
            settings.global.excludes = [
              ".direnv/**"
              ".jj/**"
              ".env"
              ".envrc"
              ".env.local"
            ];


            # Format nix files
            programs.nixpkgs-fmt.enable = true;
            # programs.deadnix.enable = true;

            # Format go files
            programs.goimports.enable = true;
          };

          packages.default = pkgs.buildGoModule rec {
            pname = "envr";
            version = "0.1.0";
            src = ./.;
            # If the build complains, uncomment this line
            # vendorHash = "sha256:0000000000000000000000000000000000000000000000000000";
            vendorHash = "sha256-aC82an6vYifewx4amfXLzk639jz9fF5bD5cF6krY0Ks=";
            
            nativeBuildInputs = [ pkgs.installShellFiles ];

            ldflags = [
              "-X github.com/sbrow/envr/cmd.version=v${version}"
              # "-X github.com/sbrow/envr/cmd.commit=$(git rev-parse HEAD)"
              # "-X github.com/sbrow/envr/cmd.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            ];
            
            postBuild = ''
              # Generate man pages
              $GOPATH/bin/docgen -out ./man -format man
            '';
            
            postInstall = ''
              # Install man pages
              installManPage ./man/*.1
            '';
          };

          devShells.default = pkgs.mkShell
            {
              buildInputs = with pkgs; [
                fd
                nushell
                go
                gopls

                gotools
                cobra-cli

                # IDE
                unstable.helix
                typescript-language-server
                vscode-langservers-extracted
              ];
            };
        };
    };
}
