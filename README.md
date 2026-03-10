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
- Instructions: exports `AGENTS.md` through `instructions.instructions` for composer consumers
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
  "rust-env".separateCargoBuildDirByRepo = false;
}
```

Set the option below to isolate artifacts per repo in `targets/<repoDir>`:

```nix
{
  "rust-env".separateCargoBuildDirByRepo = true;
}
```

## Managed Cargo

Enable this when you want each Rust repo to own manifest intent in
`Cargo.dvnv.toml` while versions come from a shared catalog in this repo.

```nix
{
  "rust-env".managedCargo.enable = true;
}
```

Available options:

- `"rust-env".managedCargo.enable`
- `"rust-env".managedCargo.catalogPath`
- `"rust-env".managedCargo.specPath`
- `"rust-env".managedCargo.outputPath`
- `"rust-env".managedCargo.sourcePath`

When enabled:

- `Cargo.toml` is generated with a clear "do not edit" header
- `outputs.cargo_manifest` is exposed for packaging and cross-repo consumers
- `outputs.cargo_source_tree` exposes a build-ready source tree with the generated `Cargo.toml` injected
- `outputs.rust_deps_catalog` exposes the resolved shared catalog
- virtual workspace roots are supported, including `[workspace.dependencies]`
- treefmt `cargo-sort` also formats the configured `rust-env.managedCargo.specPath` when it is inside the repo root

When `specPath` points outside the current repo root, managed Cargo now skips
local `Cargo.toml` materialization automatically while still exposing the
generated manifest and source-tree outputs for downstream packaging.

For a virtual-workspace layout, keep the root workspace manifest content in
`Cargo.dvnv.toml` and keep member crate `Cargo.toml` files checked in normally.
