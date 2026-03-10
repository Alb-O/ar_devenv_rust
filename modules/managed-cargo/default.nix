{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config."rust-env".managedCargo;
  managedCargoEnabled = cfg.enable;
  managedCargoMergeScript = ./merge-managed-cargo.py;
  managedCargoTomlFormat = pkgs.formats.toml { };
  managedCargoHeader = ''
    # ---------------------------------------------------------------------------
    # GENERATED FILE: DO NOT EDIT DIRECTLY
    #
    # This Cargo.toml is materialized by devenv from:
    # - the shared crate catalog configured by `rust-env.managedCargo.catalogPath`
    # - this repo's dependency spec at `rust-env.managedCargo.specPath`
    #
    # To change crates.io dependency versions:
    # - edit the shared catalog, not this file
    #
    # To change this repo's dependency/features/package metadata:
    # - edit Cargo.dvnv.toml, then re-enter `devenv shell` or run `devenv test`
    # ---------------------------------------------------------------------------
    #
  '';
  resolveFromRoot = path: if lib.hasPrefix "/" path then path else "${config.devenv.root}/${path}";
  pathIsInsideRoot =
    path:
    let
      root = toString config.devenv.root;
      rootPrefix = "${root}/";
    in
    path == root || lib.hasPrefix rootPrefix path;
  managedCargoCatalogPath = resolveFromRoot cfg.catalogPath;
  managedCargoSpecPath = resolveFromRoot cfg.specPath;
  managedCargoSourcePath = resolveFromRoot (
    if cfg.sourcePath != null then cfg.sourcePath else builtins.dirOf cfg.specPath
  );
  managedCargoShouldMaterialize =
    managedCargoEnabled && cfg.outputPath != null && pathIsInsideRoot managedCargoSpecPath;
  managedCargoManifestJsonText =
    if managedCargoEnabled then
      builtins.readFile (
        pkgs.runCommand "cargo-manifest.json"
          {
            nativeBuildInputs = [ pkgs.python3 ];
            passAsFile = [
              "catalogToml"
              "specToml"
            ];
            catalogToml = builtins.readFile managedCargoCatalogPath;
            specToml = builtins.readFile managedCargoSpecPath;
          }
          ''
            python3 ${managedCargoMergeScript} "$catalogTomlPath" "$specTomlPath" > "$out"
          ''
      )
    else
      "";
  managedCargoManifestValue =
    if managedCargoManifestJsonText != "" then builtins.fromJSON managedCargoManifestJsonText else null;
  managedCargoManifestFile =
    if managedCargoManifestValue != null then
      pkgs.writeText "Cargo.toml" (
        managedCargoHeader
        + builtins.readFile (managedCargoTomlFormat.generate "Cargo.toml.body" managedCargoManifestValue)
      )
    else
      null;
  managedCargoCatalogFile =
    if managedCargoEnabled then
      pkgs.writeText "rust-deps-catalog.toml" (builtins.readFile managedCargoCatalogPath)
    else
      null;
  managedCargoSourceTree =
    if managedCargoEnabled then
      pkgs.runCommand "${baseNameOf managedCargoSourcePath}-cargo-source" { } ''
        mkdir -p "$out"
        cp -R ${
          builtins.path {
            path = managedCargoSourcePath;
            name = "${baseNameOf managedCargoSourcePath}-source";
          }
        }/. "$out"/
        chmod -R u+w "$out"
        rm -f "$out/Cargo.toml"
        cp ${managedCargoManifestFile} "$out/Cargo.toml"
      ''
    else
      null;
in
{
  options."rust-env".managedCargo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Generate Cargo.toml from a repo-owned Cargo.dvnv.toml and a shared crate version catalog.";
    };

    catalogPath = lib.mkOption {
      type = lib.types.str;
      default = toString ./Cargo.catalog.toml;
      description = "Path to the shared crate version catalog TOML.";
    };

    specPath = lib.mkOption {
      type = lib.types.str;
      default = "Cargo.dvnv.toml";
      description = "Repo-owned Cargo manifest spec TOML without crates.io versions.";
    };

    outputPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "Cargo.toml";
      description = "Output path for the generated Cargo manifest. Set to null to disable workspace materialization and expose only outputs.cargo_manifest.";
    };

    sourcePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Repo source root used for outputs.cargo_source_tree. Defaults to the directory containing specPath.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = lib.optionals managedCargoEnabled [
        {
          assertion = builtins.pathExists managedCargoSpecPath;
          message = "rust-env.managedCargo.enable is true but specPath does not exist: ${managedCargoSpecPath}";
        }
        {
          assertion = builtins.pathExists managedCargoSourcePath;
          message = "rust-env.managedCargo.enable is true but sourcePath does not exist: ${managedCargoSourcePath}";
        }
      ];

      outputs = lib.mkIf managedCargoEnabled {
        cargo_manifest = managedCargoManifestFile;
        cargo_source_tree = managedCargoSourceTree;
        rust_deps_catalog = managedCargoCatalogFile;
      };
    }
    (lib.mkIf managedCargoShouldMaterialize {
      files."${cfg.outputPath}".source = managedCargoManifestFile;
    })
  ];
}
