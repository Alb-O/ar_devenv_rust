{
  pkgs,
  config,
  lib,
  options,
  ...
}:

let
  cfg = config."rust-env";
  managedCargoCfg = cfg.managedCargo;
  xdgCacheHome =
    let
      fromXdg = builtins.getEnv "XDG_CACHE_HOME";
      fromHome = builtins.getEnv "HOME";
    in
    if fromXdg != "" then
      fromXdg
    else if fromHome != "" then
      "${fromHome}/.cache"
    else
      "/tmp";
  repoDir = baseNameOf config.git.root;
  cargoBuildDir =
    "${xdgCacheHome}/cargo/targets" + lib.optionalString cfg.separateCargoBuildDirByRepo "/${repoDir}";
  hasLocalCargoManifest =
    builtins.pathExists "${config.devenv.root}/Cargo.toml"
    || (managedCargoCfg.enable && managedCargoCfg.outputPath != null);
in
{
  imports = [
    ./modules/formatters
    ./modules/managed-cargo
  ];

  options."rust-env" = {
    separateCargoBuildDirByRepo = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Store Cargo build artifacts under a repo-specific subdirectory inside
        ${xdgCacheHome}/cargo/targets.
      '';
    };

  };

  config = lib.mkMerge [
    {
      env.CARGO_BUILD_BUILD_DIR = cargoBuildDir;

      files = {
        ".cargo/config.toml".source = ./cargo/config.toml;
        "rust-toolchain.toml".source = ./cargo/rust-toolchain.toml;
        "rustfmt.toml".source = ./cargo/rustfmt.toml;
      };

      languages.rust = {
        enable = true;
        toolchainFile = ./cargo/rust-toolchain.toml;
        lsp.enable = true;
      };

      packages = [
        pkgs.just
        pkgs.openssl
        pkgs.pkg-config
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        pkgs.lld
        pkgs.mold
      ];

      scripts = lib.mkMerge [
        {
          ci.exec = ''
            set -euo pipefail
            fmt-check
            ${lib.optionalString hasLocalCargoManifest ''
              lint
              check
              run-tests
              check-targets
            ''}
          '';
        }
        (lib.mkIf hasLocalCargoManifest {
          lint.exec = "cargo clippy --workspace --all-targets --all-features -- -D warnings";
          run-tests.exec = "cargo test --workspace --all-targets --all-features";
          check.exec = "cargo check --workspace --all-targets --all-features";
          check-targets.exec = ''
            set -euo pipefail
            cargo check --workspace --target wasm32-unknown-unknown
            cargo check --workspace --target x86_64-unknown-linux-musl
            cargo check --workspace --target aarch64-unknown-linux-gnu
          '';
        })
      ];

      outputs = lib.mkMerge [
        {
          rust-toolchain = config.languages.rust.toolchainPackage;
        }
      ];

      enterTest = ''
        set -euo pipefail

        rustc --version | grep -E "nightly|dev"
        cargo --version
        rustfmt --version
        clippy-driver --version

        fmt-check
        ${lib.optionalString hasLocalCargoManifest ''
          lint
          run-tests
          check-targets
        ''}
      '';
    }
    (lib.mkIf (options ? instructions && options.instructions ? instructions) {
      # `instructions.instructions` is declared by composer/agent-style modules,
      # not by devenv itself. Guard this assignment so plain Rust-env consumers
      # that do not import those modules still evaluate successfully.
      instructions.instructions = lib.mkAfter [ (builtins.readFile ./AGENTS.md) ];
    })
  ];
}
