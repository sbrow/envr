{
  description = "Manage your .env files.";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ self
    , flake-parts
    , nixpkgs
    , nixpkgs-unstable
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
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

          devShells.default = pkgs.mkShell
            {
              buildInputs = with pkgs; [
                age
                fd
                nushell
                sqlite

                # IDE
                unstable.helix
                typescript-language-server
                vscode-langservers-extracted
              ];
            };
        };
    };
}
