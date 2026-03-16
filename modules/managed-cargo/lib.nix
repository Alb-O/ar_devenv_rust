{
  pkgs,
  lib,
}:

let
  managedCargoMergeScriptPath = builtins.path {
    path = ./merge-managed-cargo.py;
    name = "merge-managed-cargo.py";
  };
  managedCargoTomlFormat = pkgs.formats.toml { };
in
{
  mkManagedCargoOutputs =
    {
      catalogPath,
      specPath,
      sourcePath ? dirOf specPath,
      header ? "",
      derivationNamePrefix ? "cargo",
      mergeScriptPath ? managedCargoMergeScriptPath,
    }:
    let
      resolvedMergeScriptPath = builtins.path {
        path = mergeScriptPath;
        name = "merge-managed-cargo.py";
      };
      cargoManifestJsonText = builtins.readFile (
        pkgs.runCommand "${derivationNamePrefix}-manifest.json"
          {
            nativeBuildInputs = [ pkgs.python3 ];
            passAsFile = [
              "catalogToml"
              "specToml"
            ];
            catalogToml = builtins.readFile catalogPath;
            specToml = builtins.readFile specPath;
          }
          ''
            python3 ${resolvedMergeScriptPath} "$catalogTomlPath" "$specTomlPath" > "$out"
          ''
      );
      cargoManifestValue = builtins.fromJSON cargoManifestJsonText;
      cargoManifest = pkgs.writeText "Cargo.toml" (
        header
        + builtins.readFile (
          managedCargoTomlFormat.generate "${derivationNamePrefix}-Cargo.toml.body" cargoManifestValue
        )
      );
      cargoSourceTree = pkgs.runCommand "${derivationNamePrefix}-source" { } ''
        mkdir -p "$out"
        cp -R ${
          builtins.path {
            path = sourcePath;
            name = "${derivationNamePrefix}-source-input";
          }
        }/. "$out"/
        chmod -R u+w "$out"
        rm -f "$out/Cargo.toml"
        cp ${cargoManifest} "$out/Cargo.toml"
      '';
      rustDepsCatalog = pkgs.writeText "rust-deps-catalog.toml" (builtins.readFile catalogPath);
    in
    {
      inherit cargoManifest cargoSourceTree rustDepsCatalog;
    };
}
