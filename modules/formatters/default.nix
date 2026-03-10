{
  pkgs,
  config,
  lib,
  ...
}:

let
  managedCargoCfg = config."rust-env".managedCargo;
  rustfmtConfigPath = ../../cargo/rustfmt.toml;
  resolveFromRoot = path: if lib.hasPrefix "/" path then path else "${config.devenv.root}/${path}";
  # treefmt can only match files under the current repo root. Reduce the managed
  # spec path to a repo-relative include pattern when possible, and ignore it
  # entirely when the user points at something outside the repo.
  relativizeToRoot =
    path:
    let
      root = toString config.devenv.root;
      resolved = resolveFromRoot path;
      rootPrefix = "${root}/";
    in
    if resolved == root then
      "."
    else if lib.hasPrefix rootPrefix resolved then
      lib.removePrefix rootPrefix resolved
    else
      null;
  managedCargoSpecInclude =
    let
      relativePath = relativizeToRoot managedCargoCfg.specPath;
    in
    if relativePath == null || relativePath == "." || relativePath == "Cargo.toml" then
      null
    else
      relativePath;
  cargoSortIncludes = [
    "Cargo.toml"
    "**/Cargo.toml"
  ]
  ++ lib.optionals (managedCargoSpecInclude != null) [ managedCargoSpecInclude ];
  treefmtBin = lib.getExe config.treefmt.config.build.wrapper;
  prepareCargoSortWorkspace = ./prepare-cargo-sort-workspace.py;
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
      dir="$(dirname "$f")"
      base="$(basename "$f")"

      if [[ "$base" == "Cargo.toml" ]]; then
        ${pkgs.lib.getExe pkgs.cargo-sort} "''${opts[@]}" "$dir"
        continue
      fi

      (
        set -euo pipefail

        # cargo-sort only knows how to operate on a file literally named
        # Cargo.toml. For managed spec files like Cargo.dvnv.toml, build a
        # short-lived scratch workspace with only the manifests cargo-sort needs:
        # the root spec plus any workspace member Cargo.toml files.
        temp_workspace="$(mktemp -d "$dir/cargo-sort-wrapper.XXXXXX")"

        cleanup_temp_workspace() {
          rm -rf "$temp_workspace"
        }

        trap cleanup_temp_workspace EXIT

        ${pkgs.lib.getExe pkgs.python3} ${prepareCargoSortWorkspace} "$f" "$temp_workspace"
        (
          cd "$temp_workspace"
          ${pkgs.lib.getExe pkgs.cargo-sort} "''${opts[@]}" .
        )
        # pre-commit treats any formatter write as a modification, even when
        # the content stays identical. Only replace the managed spec when the
        # sorted scratch manifest actually differs.
        if ! cmp -s "$temp_workspace/Cargo.toml" "$f"; then
          cp "$temp_workspace/Cargo.toml" "$f"
        fi
        cleanup_temp_workspace
        trap - EXIT
      )
    done
  '';
in
{
  config = {
    treefmt = {
      enable = lib.mkDefault true;
      config = {
        programs.rustfmt.enable = lib.mkDefault true;
        settings.formatter.rustfmt.options = [
          # treefmt already supplies rustfmt's edition/skip-children flags.
          # Only point it at the shared config file here, or the wrapper ends
          # up passing duplicate options during `devenv shell`.
          "--config-path"
          (toString rustfmtConfigPath)
        ];
        settings.formatter.cargo-sort = {
          command = "${cargoSortWrapper}/bin/cargo-sort-wrapper";
          options = [ "--workspace" ];
          includes = cargoSortIncludes;
        };
      };
    };

    git-hooks = lib.mkIf config.treefmt.enable {
      hooks.treefmt.enable = lib.mkDefault true;
    };

    scripts = {
      fmt.exec = treefmtBin;
      fmt-check.exec = "${treefmtBin} --fail-on-change";
    };
  };
}
