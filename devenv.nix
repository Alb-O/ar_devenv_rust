{ pkgs, config, lib, ... }:

{
  languages.rust = {
    enable = true;
    toolchainFile = ./rust-toolchain.toml;
    lsp.enable = true;
  };

  packages =
    [
      pkgs.just
      pkgs.openssl
      pkgs.pkg-config
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      pkgs.lld
      pkgs.mold
    ];

  scripts = {
    fmt.exec = "cargo fmt --all";
    fmt-check.exec = "cargo fmt --all --check";
    lint.exec = "cargo clippy --workspace --all-targets --all-features -- -D warnings";
    run-tests.exec = "cargo test --workspace --all-targets --all-features";
    check.exec = "cargo check --workspace --all-targets --all-features";
    check-targets.exec = ''
      set -euo pipefail
      cargo check --workspace --target wasm32-unknown-unknown
      cargo check --workspace --target x86_64-unknown-linux-musl
      cargo check --workspace --target aarch64-unknown-linux-gnu
    '';
    ci.exec = ''
      set -euo pipefail
      fmt-check
      lint
      check
      run-tests
      check-targets
    '';
  };

  outputs.rust-toolchain = config.languages.rust.toolchainPackage;

  enterTest = ''
    set -euo pipefail

    rustc --version | grep -E "nightly|dev"
    cargo --version
    rustfmt --version
    clippy-driver --version

    fmt-check
    lint
    run-tests
    check-targets
  '';
}
