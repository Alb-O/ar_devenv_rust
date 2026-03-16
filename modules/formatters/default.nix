{
  pkgs,
  config,
  lib,
  ...
}:

let
  managedCargoCfg = config.rustEnv.managedCargo;
  rustfmtConfigPath = ../../cargo/rustfmt.toml;
  resolveFromRoot =
    path:
    let
      pathString = toString path;
    in
    if lib.hasPrefix "/" pathString then pathString else "${config.devenv.root}/${pathString}";
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
  typosBin = lib.getExe pkgs.typos;
  typosToml = pkgs.formats.toml { };
  typosLocalConfigPath = resolveFromRoot config.rustEnv.typos.localConfigPath;
  typosLocalConfig =
    if builtins.pathExists typosLocalConfigPath then
      builtins.fromTOML (builtins.readFile typosLocalConfigPath)
    else
      { };
  typosConfigPath = typosToml.generate "typos-config.toml" (
    lib.recursiveUpdate config.rustEnv.typos.managedConfig typosLocalConfig
  );
  prepareCargoSortWorkspace = ./prepare-cargo-sort-workspace.nu;
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
        # Cargo.toml. For managed spec files like Cargo.poly.toml, build a
        # short-lived scratch workspace with only the manifests cargo-sort needs:
        # the root spec plus any workspace member Cargo.toml files.
        temp_workspace="$(mktemp -d "$dir/cargo-sort-wrapper.XXXXXX")"

        cleanup_temp_workspace() {
          rm -rf "$temp_workspace"
        }

        trap cleanup_temp_workspace EXIT

        ${pkgs.lib.getExe pkgs.nushell} ${prepareCargoSortWorkspace} "$f" "$temp_workspace"
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
  options.rustEnv.typos = {
    localConfigPath = lib.mkOption {
      type = lib.types.oneOf [
        lib.types.str
        lib.types.path
      ];
      default = "typos.toml";
      description = "Repo-local typos config merged over rustEnv.typos.managedConfig.";
    };

    managedConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Managed typos config merged first, before the repo-local typos.toml override.";
    };
  };

  config = {
    treefmt = {
      enable = lib.mkDefault true;
      config = {
        programs.rustfmt.enable = lib.mkDefault true;
        # Keep treefmt on the same rustfmt binary as `cargo fmt`, otherwise
        # nightly-only rustfmt options like import grouping silently diverge.
        programs.rustfmt.package = config.languages.rust.toolchainPackage;
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
      hooks = {
        treefmt.enable = lib.mkDefault true;
        typos = {
          enable = lib.mkDefault true;
          entry = lib.mkForce "${typosBin} --config ${typosConfigPath} --force-exclude";
        };
      };
    };

    packages = [ pkgs.typos ];

    scripts = {
      fmt.exec = treefmtBin;
      fmt-check.exec = "${treefmtBin} --fail-on-change";
      spellcheck.exec = "${typosBin} --config ${typosConfigPath}";
      spellcheck-fix.exec = "${typosBin} --config ${typosConfigPath} -w";
    };

    outputs.typos_config = typosConfigPath;
  };
}
