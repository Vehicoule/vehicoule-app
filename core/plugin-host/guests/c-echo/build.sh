#!/usr/bin/env bash
# Regenerates tests/fixtures/c-echo.wasm from echo.c. Not run by `cargo test`: the
# fixture is committed so the test suite needs no C toolchain (see README.md).
#
# Requires, on PATH or via env vars below:
#   - wit-bindgen (cli, v0.63.x):  cargo install wit-bindgen-cli --version 0.63.0 --locked
#   - clang targeting wasm32, with wasi-libc's sysroot (WASI_CLANG / WASI_SYSROOT)
#   - wasm-component-ld:           cargo install wasm-component-ld --locked
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

WIT_BINDGEN=${WIT_BINDGEN:-wit-bindgen}
CLANG=${WASI_CLANG:-/opt/homebrew/opt/llvm/bin/clang}
SYSROOT=${WASI_SYSROOT:-/opt/homebrew/opt/wasi-libc/share/wasi-sysroot}
WASM_COMPONENT_LD=${WASM_COMPONENT_LD:-$(command -v wasm-component-ld)}
OUT=../../tests/fixtures/c-echo.wasm

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# wit-bindgen takes a single WIT path: assemble a throwaway dir with the test
# world and copies of the two contract packages as its deps.
mkdir -p "$tmp/wit/deps/host" "$tmp/wit/deps/music"
cp ../wit/world.wit "$tmp/wit/world.wit"
cp ../../../contract/wit/host/host.wit "$tmp/wit/deps/host/host.wit"
cp ../../../contract/wit/music/music.wit "$tmp/wit/deps/music/music.wit"

"$WIT_BINDGEN" c --world test-search --out-dir "$tmp/gen" "$tmp/wit"

"$CLANG" --target=wasm32-wasip2 --sysroot="$SYSROOT" -I "$tmp/gen" \
  -Os -ffunction-sections -fdata-sections -c echo.c -o "$tmp/echo.o"
"$CLANG" --target=wasm32-wasip2 --sysroot="$SYSROOT" -I "$tmp/gen" \
  -Os -ffunction-sections -fdata-sections -c "$tmp/gen/test_search.c" -o "$tmp/test_search.o"

"$CLANG" --target=wasm32-wasip2 --sysroot="$SYSROOT" -fuse-ld="$WASM_COMPONENT_LD" \
  -Os -Wl,--gc-sections -Wl,--strip-all \
  "$tmp/echo.o" "$tmp/test_search.o" "$tmp/gen/test_search_component_type.o" -o "$OUT"

echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
