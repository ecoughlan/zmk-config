{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pin to ZMK's zephyr fork (v4.1.0+zmk-fixes branch)
    zephyr.url = "github:zmkfirmware/zephyr/ec36516990d40355238db3049bc1709191f99b4e";
    zephyr.flake = false;

    # Zephyr sdk and toolchain.
    zephyr-nix.url = "github:urob/zephyr-nix";
    zephyr-nix.inputs.zephyr.follows = "zephyr";
    zephyr-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, zephyr-nix, ... }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        zephyr = zephyr-nix.packages.${system};
        keymap_drawer = pkgs.python3Packages.callPackage ./nix/keymap-drawer.nix {};
        # Extra Python packages for nanopb/ZMK Studio protobuf support
        pythonProto = pkgs.python3.withPackages (ps: with ps; [
          protobuf
          grpcio-tools
        ]);
      in {
        default = pkgs.mkShellNoCC {
          packages =
            [
              zephyr.pythonEnv
              pythonProto
              (zephyr.sdk-0_16.override {targets = ["arm-zephyr-eabi"];})

              pkgs.cmake
              pkgs.dtc
              pkgs.gcc
              pkgs.ninja

              pkgs.just
              pkgs.yq # Make sure yq resolves to python-yq.

              keymap_drawer
            ];

          env = {
            # Put pythonProto FIRST so its protobuf 6.x overrides zephyr's older version
            PYTHONPATH = "${pythonProto}/${pythonProto.sitePackages}:${zephyr.pythonEnv}/${zephyr.pythonEnv.sitePackages}";
          };

          shellHook = ''
            export ZMK_BUILD_DIR=$(pwd)/.build;
            export ZMK_SRC_DIR=$(pwd)/zmk/app;
          '';
        };
      }
    );
  };
}
