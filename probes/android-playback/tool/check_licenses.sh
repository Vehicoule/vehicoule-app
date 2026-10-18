#!/bin/sh
# Fails if the media_kit native libs of the last release build are GPL or nonfree builds.
# Usage: tool/check_licenses.sh [lib dir]
set -eu
dir=${1:-build/app/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib/arm64-v8a}
fail=0
found=0
for so in "$dir"/libmpv*.so "$dir"/libav*.so; do
  [ -f "$so" ] || continue
  found=1
  s=$(strings -n 6 "$so")
  echo "== $(basename "$so")"
  printf '%s\n' "$s" | grep -E 'license: |--enable-lgpl|-Dgpl=' | sed 's/^\(.\{140\}\).*/\1…/' | sort -u
  if printf '%s\n' "$s" | grep -qE -- '--enable-gpl|--enable-nonfree|license: GPL'; then
    echo "FAIL: GPL or nonfree build"; fail=1
  fi
  case $(basename "$so") in
    libmpv*) printf '%s\n' "$s" | grep -qE -- '--enable-lgpl|-Dgpl=false' || { echo "FAIL: mpv not built as LGPL"; fail=1; } ;;
  esac
done
[ "$found" = 1 ] || { echo "FAIL: no libmpv/libav in $dir"; exit 1; }
[ "$fail" = 0 ] && echo PASS
exit $fail
