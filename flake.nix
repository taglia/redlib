{
  description = "Redlib: Private front-end for Reddit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane.url = "github:ipetkov/crane";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, crane, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        inherit (pkgs) lib;

        cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);

        staticToolchain = pkgs.pkgsStatic.stdenv.cc;

        rustTarget = if system == "aarch64-linux" then "aarch64-unknown-linux-musl" else "x86_64-unknown-linux-musl";
        rustToolchain = pkgs.rust-bin.stable."1.99.1".default.override {
          targets = [ rustTarget ];
          extensions = [ "rustfmt" "clippy" ];
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;


        src = lib.cleanSourceWith {
          src = craneLib.path ./.;
          filter = path: type:
            (lib.hasInfix "/templates/" path) ||
            (lib.hasInfix "/static/" path) ||
            (craneLib.filterCargoSources path type);
        };

        redlib = craneLib.buildPackage {
          inherit src;
          strictDeps = true;
          doCheck = false;

          nativeBuildInputs = with pkgs; [
            cmake
            git
            perl
            pkg-config
            rustPlatform.bindgenHook
            staticToolchain
          ];

          CARGO_BUILD_TARGET = rustTarget;
          CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";
          "CARGO_TARGET_${lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] rustTarget)}_LINKER" = "${staticToolchain}/bin/${staticToolchain.targetPrefix}cc";
          "CC_${builtins.replaceStrings [ "-" ] [ "_" ] rustTarget}" = "${staticToolchain}/bin/${staticToolchain.targetPrefix}cc";
          "CXX_${builtins.replaceStrings [ "-" ] [ "_" ] rustTarget}" = "${staticToolchain}/bin/${staticToolchain.targetPrefix}c++";
        };
      in
      {
        checks = {
          my-crate = redlib;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            rustToolchain cargo-audit cargo-edit actionlint skopeo
            cmake perl pkg-config clang git
          ];
          LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
        };

        packages.default = redlib;
        packages.docker = pkgs.dockerTools.buildImage {
          name = "tagliasteel/redlib";
          tag = "latest";
          created = "1970-01-01T00:00:01Z";
          copyToRoot = with pkgs.dockerTools; [
            caCertificates
            fakeNss
            pkgs.busybox
            pkgs.wget
          ];
          config = {
            User = "10001:10001";
            Env = [
              "PATH=${redlib}/bin:${pkgs.wget}/bin:${pkgs.busybox}/bin:${pkgs.busybox}/sbin"
            ];
            Cmd = [ "redlib" ];
            ExposedPorts = {
              "8080/tcp" = { };
            };
            Healthcheck = {
              Test = [
                "CMD-SHELL"
                "wget --spider -q http://localhost:8080/settings || exit 1"
              ];
              Interval = 60000000000;
              Timeout = 3000000000;
            };
            Labels = {
              "org.opencontainers.image.title" = "Redlib";
              "org.opencontainers.image.description" = "Private front-end for Reddit";
              "org.opencontainers.image.source" = "https://github.com/taglia/redlib";
              "org.opencontainers.image.url" = "https://github.com/redlib-org/redlib";
              "org.opencontainers.image.version" = cargoToml.package.version;
              "org.opencontainers.image.licenses" = "AGPL-3.0-only";
            };
          };
        };
      });
}
