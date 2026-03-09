{ pkgs, config, lib, ... }:

let
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
  treefmtBin = lib.getExe config.treefmt.config.build.wrapper;
  treefmtPreCommit = pkgs.writeShellApplication {
    name = "treefmt-pre-commit";
    runtimeInputs = [ pkgs.git ];
    text = ''
      set -euo pipefail

      if (($# == 0)); then
        exit 0
      fi

      # Stage formatter edits so the current commit can succeed in one pass.
      ${treefmtBin} --no-cache "$@"
      git add -- "$@"
    '';
  };
  cargoSortWrapper = pkgs.writeShellScriptBin "cargo-sort-wrapper" ''
    set -euo pipefail

    opts=()
    files=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --*) opts+=("$1"); shift ;;
        *) files+=("$1"); shift ;;
      esac
    done

    for f in "''${files[@]}"; do
      ${pkgs.lib.getExe pkgs.cargo-sort} "''${opts[@]}" "$(dirname "$f")"
    done
  '';
in
{
  env.CARGO_BUILD_BUILD_DIR = "${xdgCacheHome}/cargo/targets";

  languages.rust = {
    enable = true;
    toolchainFile = ./rust-toolchain.toml;
    lsp.enable = true;
  };

  treefmt = {
    enable = lib.mkDefault true;
    config = {
      programs.rustfmt.enable = lib.mkDefault true;
      settings.formatter.cargo-sort = {
        command = "${cargoSortWrapper}/bin/cargo-sort-wrapper";
        options = [ "--workspace" ];
        includes = [
          "Cargo.toml"
          "**/Cargo.toml"
        ];
      };
    };
  };

  git-hooks = lib.mkIf config.treefmt.enable {
    hooks.treefmt = {
      enable = lib.mkDefault true;
      entry = lib.getExe treefmtPreCommit;
      packageOverrides.treefmt = config.treefmt.config.build.wrapper;
      settings = {
        # We apply and stage fixes in-hook instead of failing on first change.
        fail-on-change = false;
        formatters = builtins.attrValues config.treefmt.config.build.programs;
      };
    };
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
    fmt.exec = treefmtBin;
    fmt-check.exec = "${treefmtBin} --fail-on-change";
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

  instructions.instructions = lib.mkAfter [ (builtins.readFile ./AGENTS.md) ];

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
