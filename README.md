# Rust Base Devenv (Nightly)

Reusable Rust nightly base environment for polyrepo setups using `devenv` v2.

## Includes

- Nightly toolchain from `rust-toolchain.toml`
- Components: `cargo`, `clippy`, `rustfmt`, `rust-analyzer`, `rust-src`, `llvm-tools-preview`
- Targets: `wasm32-unknown-unknown`, `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-gnu`
- Treefmt: enabled with `rustfmt` program
- Git hooks: pre-commit `treefmt` hook enabled
- Scripts: `fmt`, `fmt-check`, `lint`, `check`, `run-tests`, `check-targets`, `ci`
- Outputs: `outputs.rust-toolchain`, `outputs.rust-agents`

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
