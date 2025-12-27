#!/usr/bin/env bash
set -Eeuo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VENDOR_ROOT="$REPO_ROOT/src/dragonstone/shared/runtime/abi/std/gc/vendor"
SOURCE_ROOT="$VENDOR_ROOT/lib"

[[ -f "$SOURCE_ROOT/CMakeLists.txt" ]] || die "Boehm GC source not found in $SOURCE_ROOT"

clean="false"
verbose="false"
if_needed="false"
for arg in "$@"; do
  case "$arg" in
    --clean) clean="true" ;;
    --verbose) verbose="true" ;;
    --if-needed) if_needed="true" ;;
  esac
done

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Darwin) os_id="macos" ;;
  Linux) os_id="linux" ;;
  *) die "Unsupported OS: $uname_s" ;;
esac

case "$uname_m" in
  x86_64|amd64) arch_id="x64" ;;
  arm64|aarch64) arch_id="arm64" ;;
  *) die "Unsupported architecture: $uname_m" ;;
esac

platform="${os_id}-${arch_id}"
output_root="$REPO_ROOT/bin/build/gc/$platform"
build_dir="$output_root/build"
install_dir="$output_root"

if [[ "$if_needed" == "true" ]]; then
  if [[ -f "$install_dir/include/gc.h" && ( -f "$install_dir/lib/libgc.a" || -f "$install_dir/lib/libgc.so" || -f "$install_dir/lib/libgc.dylib" ) ]]; then
    exit 0
  fi
fi

if [[ "$clean" == "true" ]]; then
  rm -rf "$build_dir" "$install_dir/lib" "$install_dir/include"
fi

mkdir -p "$build_dir"

cmake_args=(
  -S "$SOURCE_ROOT"
  -B "$build_dir"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -Denable_threads=ON
  -Denable_cplusplus=OFF
  -DCMAKE_INSTALL_PREFIX="$install_dir"
)

if [[ "$verbose" == "true" ]]; then
  echo "Configuring Boehm GC: cmake ${cmake_args[*]}"
fi
cmake "${cmake_args[@]}"

if [[ "$verbose" == "true" ]]; then
  echo "Building Boehm GC in $build_dir"
fi
cmake --build "$build_dir" --target install

mkdir -p "$install_dir/include" "$install_dir/lib"

if [[ ! -f "$install_dir/include/gc.h" && -d "$VENDOR_ROOT/include" ]]; then
  cp -R "$VENDOR_ROOT/include/." "$install_dir/include/"
fi

if [[ ! -f "$install_dir/lib/libgc.a" ]]; then
  lib_candidate="$(find "$build_dir" -name 'libgc.a' -o -name 'libgc.so' -o -name 'libgc.dylib' | head -n 1 || true)"
  if [[ -n "$lib_candidate" ]]; then
    cp -f "$lib_candidate" "$install_dir/lib/$(basename "$lib_candidate")"
  fi
fi

echo "Boehm GC installed to $install_dir"
