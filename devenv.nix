{
  pkgs,
  config,
  lib,
  options,
  ...
}:

let
  cfg = config.rustEnv;
  managedCargoCfg = cfg.managedCargo;
  resolveFromRoot =
    path:
    let
      pathString = toString path;
    in
    if lib.hasPrefix "/" pathString then pathString else "${config.devenv.root}/${pathString}";
  managedCargoSpecPath = resolveFromRoot managedCargoCfg.specPath;
  localCargoManifestPath = "${config.devenv.root}/Cargo.toml";
  localCargoManifestValue =
    if builtins.pathExists localCargoManifestPath then
      builtins.fromTOML (builtins.readFile localCargoManifestPath)
    else
      { };
  managedCargoSpecValue =
    if managedCargoCfg.enable && builtins.pathExists managedCargoSpecPath then
      builtins.fromTOML (builtins.readFile managedCargoSpecPath)
    else
      { };
  packageManifestPath =
    if cfg.package.manifestPath != null then
      resolveFromRoot cfg.package.manifestPath
    else if managedCargoCfg.enable && builtins.pathExists managedCargoSpecPath then
      managedCargoSpecPath
    else if builtins.pathExists localCargoManifestPath then
      localCargoManifestPath
    else
      null;
  packageManifestValue =
    if packageManifestPath != null && builtins.pathExists packageManifestPath then
      builtins.fromTOML (builtins.readFile packageManifestPath)
    else
      { };
  packageName =
    if packageManifestValue ? package && packageManifestValue.package ? name then
      packageManifestValue.package.name
    else
      null;
  workspacePackageVersionFrom =
    manifestValue:
    if
      manifestValue ? workspace
      && manifestValue.workspace ? package
      && manifestValue.workspace.package ? version
      && builtins.isString manifestValue.workspace.package.version
    then
      manifestValue.workspace.package.version
    else
      null;
  packageVersion =
    if packageManifestValue ? package && packageManifestValue.package ? version then
      if builtins.isString packageManifestValue.package.version then
        packageManifestValue.package.version
      else if
        packageManifestValue.package.version ? workspace && packageManifestValue.package.version.workspace
      then
        let
          versionFromManagedSpec = workspacePackageVersionFrom managedCargoSpecValue;
          versionFromRootCargo = workspacePackageVersionFrom localCargoManifestValue;
        in
        if versionFromManagedSpec != null then versionFromManagedSpec else versionFromRootCargo
      else
        null
    else
      null;
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
    ./modules/bevy
    ./modules/formatters
    ./modules/managed-cargo
  ];

  options.rustEnv = {
    separateCargoBuildDirByRepo = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Store Cargo build artifacts under a repo-specific subdirectory inside
        ${xdgCacheHome}/cargo/targets.
      '';
    };

    package = {
      manifestPath = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            lib.types.str
            lib.types.path
          ]
        );
        default = null;
        description = ''
          Manifest path used to derive rustEnv.package.name. Defaults to
          rustEnv.managedCargo.specPath when that file has a [package] table,
          otherwise falls back to Cargo.toml at the repo root.
        '';
      };

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        readOnly = true;
        description = "Package name derived from rustEnv.package.manifestPath.";
      };

      version = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        readOnly = true;
        description = "Package version derived from rustEnv.package.manifestPath.";
      };
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
        pkgs.nix-unit
        pkgs.openssl
        pkgs.pkg-config
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        pkgs.clang
        pkgs.mold
      ];

      scripts = lib.mkMerge [
        {
          ci.exec = ''
            set -euo pipefail
            fmt-check
            run-nix-tests
            ${lib.optionalString hasLocalCargoManifest ''
              lint
              check
              run-tests
              check-targets
            ''}
          '';
        }
        {
          run-nix-tests.exec = ''
            nix-unit --expr 'import ${config.devenv.root}/tests { lib = import ${pkgs.path}/lib; pkgs = import ${pkgs.path} {}; repoRoot = ${config.devenv.root}; }'
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
          cargo_package_name = packageName;
          cargo_package_version = packageVersion;
          rust-toolchain = config.languages.rust.toolchainPackage;
        }
      ];

      rustEnv.package.name = packageName;
      rustEnv.package.version = packageVersion;

      enterTest = ''
        set -euo pipefail

        rustc --version | grep -E "nightly|dev"
        cargo --version
        rustfmt --version
        clippy-driver --version

        fmt-check
        run-nix-tests
        ${lib.optionalString hasLocalCargoManifest ''
          lint
          run-tests
          check-targets
        ''}
      '';
    }
    (lib.mkIf (cfg.package.manifestPath != null) {
      assertions = [
        {
          assertion = builtins.pathExists packageManifestPath;
          message = "rustEnv.package.manifestPath does not exist: ${packageManifestPath}";
        }
        {
          assertion = packageName != null;
          message = "rustEnv.package.manifestPath does not contain [package].name: ${packageManifestPath}";
        }
        {
          assertion = packageVersion != null;
          message = "rustEnv.package.manifestPath does not contain a resolvable package version: ${packageManifestPath}";
        }
      ];
    })
    (lib.optionalAttrs (options ? instructions && options.instructions ? instructions) {
      # `instructions.instructions` is declared by composer/agent-style modules,
      # not by devenv itself. Guard this assignment so plain Rust-env consumers
      # that do not import those modules still evaluate successfully.
      instructions.instructions = lib.mkAfter [ (builtins.readFile ./AGENTS.md) ];
    })
  ];
}
