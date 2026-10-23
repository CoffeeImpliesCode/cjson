# Flake interface for the cJSON SDK.
#
# SPDX-License-Identifier: MIT

{
  description = "cJSON 1.7.19, an ultra-lightweight JSON parser in ANSI C, packaged for Zig 0.17";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";
  };

  outputs = { self, nixpkgs }:
    let
      # Both package variants use the shared derivation in package.nix.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "x86_64-freebsd"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          mk = linkage: pkgs.callPackage ./package.nix {
            inherit linkage;
            zig = pkgs.zig_0_17;
          };
        in
        {
          static = mk "static";

          # Expose Zig's dynamic-linkage variant as `shared`.
          shared = mk "dynamic";

          default = mk "static";
        });

      # The development shell provides tools without building the SDK.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.zig_0_17 pkgs.gnumake pkgs.pkg-config ];
        };
      });
    };
}