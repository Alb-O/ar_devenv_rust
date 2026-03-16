# Rust (nightly)

Global Rust build artifacts (CARGO_BUILD_BUILD_DIR): be patient with cargo lock, other projects inflight
Search in $CARGO_HOME to lookup dependency APIs

## Style

No trivial tests. Avoid happy-path, instead test against the cruel outside world
Simplify & avoid over-handling. Lean on implicit/concise behavior as the go-to
Prefer functional style
Use where clause:

```rs
impl<T> Model for MyModel<T>
where
    T: /*...*/
```

## Managed Cargo deps

Root Cargo.toml is nix-generated to sync dep versions across repos
Repo-local manifest intent in Cargo.poly.toml (no crates.io ver numbers)
Polyrepo-shared crates.io versions in Cargo.catalog.toml
Regen Cargo.toml (devenv shell); if it fails on a dep missing from Cargo.catalog.toml, add it there
See the generated Cargo.toml for location of the catalog to edit
Pin latest ver from checking `cargo info`
