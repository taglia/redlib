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
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        inherit (pkgs) lib;

        cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);

        staticToolchain = pkgs.pkgsStatic.stdenv.cc;

        rustToolchain = pkgs.rust-bin.stable."1.88.0".default.override {
          targets = [ "x86_64-unknown-linux-musl" ];
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

          CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
          CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";
          CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER = "${staticToolchain}/bin/${staticToolchain.targetPrefix}cc";
          CC_x86_64_unknown_linux_musl = "${staticToolchain}/bin/${staticToolchain.targetPrefix}cc";
          CXX_x86_64_unknown_linux_musl = "${staticToolchain}/bin/${staticToolchain.targetPrefix}c++";
        };
      in
      {
        checks = {
          my-crate = redlib;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            rustToolchain
          ];
        };

        packages.default = redlib;
        packages.docker = pkgs.dockerTools.buildImage {
          name = "quay.io/redlib/redlib";
          tag = "latest";
          created = "now";
          copyToRoot = with pkgs.dockerTools; [
            caCertificates
            fakeNss
            pkgs.wget
          ];
          config = {
            Cmd = [ "${redlib}/bin/redlib" ];
            ExposedPorts = {
              "8080/tcp" = { };
            };
            Healthcheck = {
              Test = [
                "CMD"
                "${pkgs.wget}/bin/wget"
                "--spider"
                "-q"
                "http://localhost:8080/settings"
              ];
              Interval = 60000000000;
              Timeout = 3000000000;
            };
            Labels = {
              "org.opencontainers.image.title" = "Redlib";
              "org.opencontainers.image.description" = "Private front-end for Reddit";
              "org.opencontainers.image.source" = "https://github.com/taglia/redlib/tree/redlib-0.36.0-dockerhub-source";
              "org.opencontainers.image.url" = "https://github.com/redlib-org/redlib";
              "org.opencontainers.image.version" = cargoToml.package.version;
              "org.opencontainers.image.licenses" = "AGPL-3.0-only";
            };
          };
        };
      });
}
