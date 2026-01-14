{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # This pins requirements.txt provided by zephyr-nix.pythonEnv.
    zephyr.url = "github:zmkfirmware/zephyr/v4.1.0+zmk-fixes";
    zephyr.flake = false;

    # Zephyr sdk and toolchain.
    zephyr-nix.url = "github:nix-community/zephyr-nix";
    zephyr-nix.inputs.zephyr.follows = "zephyr";
    zephyr-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ { nixpkgs, ... }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        zephyr = inputs.zephyr-nix.packages.${system};
        keymap-drawer = pkgs.python3Packages.callPackage ./nix/keymap-drawer.nix {};
        # Extra Python packages for nanopb/ZMK Studio protobuf support
        pythonProto = pkgs.python3.withPackages (ps: with ps; [
          protobuf
          grpcio-tools
        ]);
        dts-format = pkgs.callPackage ./nix/dts-format.nix {
          dts-linter = pkgs.callPackage ./nix/dts-linter.nix {
            # Uncomment to build against the pinned dts-lsp instead of the
            # server bundled with dts-linter.
            # dts-lsp-server = pkgs.callPackage ./nix/dts-lsp-server.nix {};
          };
        };
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

              dts-format
              keymap-drawer
            ];

          env = {
            # CMake 4.x rejects Zephyr 4.1's FindZephyr-sdk check when this is unset.
            ZEPHYR_TOOLCHAIN_VARIANT = "zephyr";
            # Put pythonProto FIRST so its protobuf overrides zephyr's older version
            PYTHONPATH = "${pythonProto}/${pythonProto.sitePackages}:${zephyr.pythonEnv}/${zephyr.pythonEnv.sitePackages}";
          };

          shellHook = ''
            export ZMK_BUILD_DIR=$(pwd)/.build;
            export ZMK_SRC_DIR=$(pwd)/zmk/app;
          ''
          # Expose libatomic to non-Nix binaries, required by the dts-linter
          # pre-commit hook. This is linux-only, in Darwin atomics live in
          # the compiler runtime and LD_LIBRARY_PATH is linux-only anyhow.
          + (if pkgs.stdenv.isLinux then
            let libatomic = pkgs.runCommand "libatomic" {} ''
              mkdir -p $out/lib
              cp -d ${pkgs.stdenv.cc.cc.lib}/lib/libatomic.so* $out/lib/
            ''; in ''
            export LD_LIBRARY_PATH="${libatomic}/lib";
          '' else "");
        };
      }
    );
  };
}
