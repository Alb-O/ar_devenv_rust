# Rust Base Devenv (Nightly)

Reusable Rust nightly base environment for polyrepo setups using `devenv` v2.

## Includes

- Nightly toolchain from `cargo/rust-toolchain.toml`
- Components: `cargo`, `clippy`, `rustfmt`, `rust-analyzer`, `rust-src`, `llvm-tools-preview`
- Targets: `wasm32-unknown-unknown`, `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-gnu`
- Treefmt: enabled with `rustfmt` program using `cargo/rustfmt.toml`
- Git hooks: pre-commit `treefmt` hook enabled
- Scripts: `fmt`, `fmt-check`, `lint`, `check`, `run-tests`, `check-targets`, `ci`
- Outputs: `outputs.rust-toolchain`
- Derived package metadata: `rustEnv.package.name`, `rustEnv.package.version`, `outputs.cargo_package_name`, and `outputs.cargo_package_version`
- Instructions: exports `AGENTS.md` through `instructions.instructions` for composer consumers
- Optional Bevy runtime/build wiring from `modules/bevy/`
- Optional managed Cargo manifest generation from `modules/managed-cargo/`

## Use

```yaml
inputs:
  dvnv-rust-env:
    url: github:Alb-O/dvnv-rust-env
    flake: false
imports:
  - dvnv-rust-env
```

## Consumer treefmt overrides

Consumers can extend the shared Rust formatting by adding extra programs under `treefmt.config`.
This composes with `dvnv-rust-env` defaults (for example, `rustfmt` stays enabled):

```nix
{
  treefmt.config.programs.mdformat.enable = true;
}
```

## Cargo build dir layout

By default, Cargo build artifacts go to `targets` under `XDG_CACHE_HOME`:

```nix
{
  rustEnv.separateCargoBuildDirByRepo = false;
}
```

Set the option below to isolate artifacts per repo in `targets/<repoDir>`:

```nix
{
  rustEnv.separateCargoBuildDirByRepo = true;
}
```

## Package Name

For package builds, use the derived package name instead of repeating `pname`
by hand:

```nix
{
  pname = config.rustEnv.package.name;
  version = config.rustEnv.package.version;
}
```

By default this reads:

- `rustEnv.managedCargo.specPath` when managed Cargo is enabled and the spec has `[package].name`
- otherwise `Cargo.toml` at the repo root

For virtual workspaces or other non-root package manifests, set:

```nix
{
  rustEnv.package.manifestPath = ./apps/my-crate/Cargo.toml;
}
```

## Managed Cargo

Enable this when you want each Rust repo to own manifest intent in
`Cargo.dvnv.toml` while versions come from a shared catalog in this repo.

```nix
{
  rustEnv.managedCargo.enable = true;
}
```

Available options:

- `rustEnv.managedCargo.enable`
- `rustEnv.managedCargo.catalogPath`
- `rustEnv.managedCargo.specPath`
- `rustEnv.managedCargo.outputPath`
- `rustEnv.managedCargo.sourcePath`

When enabled:

- `Cargo.toml` is generated with a clear "do not edit" header
- `outputs.cargo_manifest` is exposed for packaging and cross-repo consumers
- `outputs.cargo_source_tree` exposes a build-ready source tree with the generated `Cargo.toml` injected
- `outputs.rust_deps_catalog` exposes the resolved shared catalog
- virtual workspace roots are supported, including `[workspace.dependencies]`
- treefmt `cargo-sort` also formats the configured `rustEnv.managedCargo.specPath` when it is inside the repo root

Preferred `Cargo.dvnv.toml` style uses regular dependency tables with inline
tables or `true`, rather than one `[dependencies.<crate>]` block per crate:

```toml
[dependencies]
serde = { features = ["derive"] }
serde_json = true
```

For virtual workspaces, the same shorthand works under `[workspace.dependencies]`.

When `specPath` points outside the current repo root, managed Cargo now skips
local `Cargo.toml` materialization automatically while still exposing the
generated manifest and source-tree outputs for downstream packaging.

For a virtual-workspace layout, keep the root workspace manifest content in
`Cargo.dvnv.toml` and keep member crate `Cargo.toml` files checked in normally.

## Bevy

Enable this when a Rust repo needs the standard Linux Bevy shell/runtime setup:

```nix
{
  rustEnv.bevy.enable = true;
}
```

When enabled:

- `LD_LIBRARY_PATH` includes the shared Bevy runtime libraries plus `/run/opengl-driver/lib`
- the shell gets the shared Bevy runtime libraries, `pkg-config`, and `udev`
- consumers can reuse the same package-build inputs through:
  - `rustEnv.bevy.runtimeLibs`
  - `rustEnv.bevy.nativeBuildInputs`
