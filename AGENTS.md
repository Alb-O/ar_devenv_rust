# Rust (Nightly) Style

* Global Rust build artifacts (CARGO_BUILD_BUILD_DIR): be patient with cargo lock, other projects inflight.
* No trivial tests. Avoid happy-path, instead test against the cruel outside world.
* Simplify & avoid over-handling. Lean on implicit/concise behavior as the go-to.
* Prefer functional style.
* Use where clause:

```rs
impl<T> Model for MyModel<T>
where
    T: /*...*/
```
