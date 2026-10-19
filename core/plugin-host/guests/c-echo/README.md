# c-echo

A C implementation of the `echo` test guest (see `../echo/src/lib.rs`): GET the
URL in `search-request.query`, return the HTTP status as the title of the one
track found. It exists to prove the WIT contract binds from a language other
than Rust, not to add a capability.

## Why the artefact is committed

`../../tests/fixtures/c-echo.wasm` is checked in so `cargo test` needs no C
toolchain. `build.sh` regenerates it from `echo.c` whenever the WIT contract or
the test world changes.

## Toolchain route (this machine)

No wasm-capable C toolchain was installed. The ruling was to prefer Homebrew
over wasi-sdk; that route worked, so wasi-sdk was never needed:

- `cargo install wit-bindgen-cli --version 0.63.0 --locked` — generates the C
  bindings (`<world>.c`, `<world>.h`, `<world>_component_type.o`) from the WIT
  world with `wit-bindgen c --world test-search <wit-dir>`.
- `brew install llvm` (already present) — `clang` with the `wasm32` backend
  built in; Homebrew's `clang`, not Apple's, since Apple's lacks `wasm-ld`/the
  matching resource dir.
- `brew install wasi-libc wasi-runtimes` — the wasi-libc sysroot
  (`crt1-command.o`, `libc.a`, headers) for `wasm32-wasip2`, under the stable
  `brew --prefix wasi-libc`/`share/wasi-sysroot` symlink (not the versioned
  Cellar path, which breaks on `brew upgrade`). `wasi-runtimes` was pulled in
  for its `libc++`/compiler-rt bits but isn't actually needed for this C-only,
  no-float component.
- `brew install lld` — `wasm-ld`, not bundled with the `llvm` formula since
  Homebrew 23.
- `cargo install wasm-component-ld --locked` — the linker that turns the
  linked core module into an actual component (embeds the
  `test_search_component_type.o` custom section), passed to `clang` as
  `-fuse-ld=<absolute path>` (a bare name is rejected by `clang`'s
  `-fuse-ld=` validation).

`build.sh` assembles a throwaway WIT dir (the test world plus copies of the
`host` and `music` contract packages under `deps/`, since `wit-bindgen` takes
a single path), generates bindings into it, compiles `echo.c` and the
generated `test_search.c`, and links them into the fixture with
`wasm-component-ld`. Override `WIT_BINDGEN`, `WASI_CLANG`, `WASI_SYSROOT`, or
`WASM_COMPONENT_LD` if those tools live elsewhere.

## Memory ownership note

Host-side `cabi_post_*` frees every string/list in the result whose `len > 0`,
unconditionally. Any non-empty string placed in `ret`/`err` must therefore be
heap-allocated (`test_search_string_dup`), never a string literal
(`test_search_string_set` does not copy — fine only for the empty string).
