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
  rm -rf "$SOURCE_ROOT/libatomic_ops"
  rm -f "$SOURCE_ROOT/cord" "$SOURCE_ROOT/extra" "$SOURCE_ROOT/include"
fi

# Create symlinks for cord, extra, and include directories
for dir in cord extra include; do
  if [[ ! -e "$SOURCE_ROOT/$dir" && -d "$VENDOR_ROOT/$dir" ]]; then
    ln -sf "$VENDOR_ROOT/$dir" "$SOURCE_ROOT/$dir"
  fi
done

# Create libatomic_ops stub for Windows compatibility
if [[ ! -d "$SOURCE_ROOT/libatomic_ops/src" ]]; then
  mkdir -p "$SOURCE_ROOT/libatomic_ops/src"
  cat > "$SOURCE_ROOT/libatomic_ops/src/atomic_ops.h" << 'EOF'
#ifndef AO_ATOMIC_OPS_H
#define AO_ATOMIC_OPS_H

#if defined(__GNUC__) || defined(__clang__)
  typedef volatile long AO_t;
  typedef unsigned char AO_TS_t;

  #define AO_INLINE static inline

  AO_INLINE AO_t AO_load(const volatile AO_t *addr) {
    return __atomic_load_n(addr, __ATOMIC_SEQ_CST);
  }

  AO_INLINE void AO_store(volatile AO_t *addr, AO_t val) {
    __atomic_store_n(addr, val, __ATOMIC_SEQ_CST);
  }

  AO_INLINE AO_t AO_fetch_and_add(volatile AO_t *addr, AO_t incr) {
    return __atomic_fetch_add(addr, incr, __ATOMIC_SEQ_CST);
  }

  AO_INLINE int AO_compare_and_swap(volatile AO_t *addr, AO_t old_val, AO_t new_val) {
    return __atomic_compare_exchange_n(addr, &old_val, new_val, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
  }

  AO_INLINE AO_TS_t AO_test_and_set(volatile AO_TS_t *addr) {
    return __atomic_test_and_set(addr, __ATOMIC_SEQ_CST);
  }
#endif

#endif
EOF
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

if [[ "$verbose" == "true" ]]; then
  echo "Boehm GC installed to $install_dir"
fi
