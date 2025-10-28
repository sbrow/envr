{
  description = "A dev environment";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self
    , flake-parts
    , nixpkgs
    , nixpkgs-unstable
    , process-compose-flake
    , treefmt-nix
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        # inputs.process-compose-flake.flakeModule
      ];
      systems = [ "x86_64-linux" ];

      perSystem =
        { pkgs, system, inputs', ... }: {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;

            overlays = [
              (final: prev: { unstable = inputs'.nixpkgs-unstable.legacyPackages; })
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
            programs.deadnix.enable = true;

            # Format js, json, and yaml files
            programs.prettier.enable = true;
            settings.formatter.prettier =
              {
                excludes = [
                  "public/**"
                  "resources/js/modernizr.js"
                  "storage/app/caniuse.json"
                  "*.md"
                ];
              };
          };

          devShells.default = pkgs.mkShell
            {
              buildInputs = with pkgs; [
                # TODO: Packages go here.
                unstable.nushell

                # IDE
                unstable.helix
                typescript-language-server
                vscode-langservers-extracted
              ];
            };
        };
    };
}
