{
  lib,
  pkgs,
  repoRoot,
}:
let
  fixturesRoot = builtins.path {
    path = "${toString repoRoot}/tests/fixtures/formatters";
    name = "poly-rust-env-formatter-fixtures";
  };
  fixturesDir = toString fixturesRoot;
  fixturePath = name: "${fixturesDir}/${name}";
  prepareCargoSortWorkspace = builtins.path {
    path = "${toString repoRoot}/modules/formatters/prepare-cargo-sort-workspace.nu";
    name = "prepare-cargo-sort-workspace.nu";
  };

  preparedWorkspace =
    derivationNamePrefix: specPath:
    pkgs.runCommand derivationNamePrefix
      {
        nativeBuildInputs = [ pkgs.nushell ];
      }
      ''
        mkdir -p "$out"
        ${lib.getExe pkgs.nushell} ${prepareCargoSortWorkspace} ${specPath} "$out"
      '';
in
{
  formatters."test prepareCargoSortWorkspace copies root spec and workspace member manifests" = {
    expr =
      let
        output = preparedWorkspace "prepare-cargo-sort-workspace-basic" (
          fixturePath "cargo-sort-workspace/Cargo.poly.toml"
        );
      in
      builtins.readFile "${output}/Cargo.toml"
      == builtins.readFile (fixturePath "cargo-sort-workspace/Cargo.poly.toml")
      &&
        builtins.readFile "${output}/crates/one/Cargo.toml"
        == builtins.readFile (fixturePath "cargo-sort-workspace/crates/one/Cargo.toml")
      &&
        builtins.readFile "${output}/tools/two/Cargo.toml"
        == builtins.readFile (fixturePath "cargo-sort-workspace/tools/two/Cargo.toml");
    expected = true;
  };

  formatters."test prepareCargoSortWorkspace skips excluded and manifest-less members" = {
    expr =
      let
        output = preparedWorkspace "prepare-cargo-sort-workspace-edge-cases" (
          fixturePath "cargo-sort-workspace/Cargo.poly.toml"
        );
      in
      !(builtins.pathExists "${output}/crates/excluded/Cargo.toml")
      && !(builtins.pathExists "${output}/tools/no-manifest/Cargo.toml");
    expected = true;
  };
}
