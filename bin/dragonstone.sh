#!/usr/bin/env bash
set -Eeuo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

SELF="$0"
if have readlink; then
  SELF="$(readlink -f "$SELF" 2>/dev/null || true)"
fi
[[ -n "$SELF" ]] || SELF="$0"

SCRIPT_ROOT="$(cd -- "$(dirname -- "$SELF")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_ROOT/.." && pwd)"

BUILD_DIR="$SCRIPT_ROOT/build"
EXE_PATH="$BUILD_DIR/dragonstone"
SOURCE_ENTRY="$PROJECT_ROOT/bin/dragonstone"

VERSION_H="$PROJECT_ROOT/src/dragonstone/core/runtime/include/dragonstone/core/version.h"
RESOURCE_OBJ="$SCRIPT_ROOT/resources/dragonstone.o"
ABI_SRC_DIR="$PROJECT_ROOT/src/dragonstone/shared/runtime/abi"
ABI_SOURCES=(
  "$ABI_SRC_DIR/abi.c"
  "$ABI_SRC_DIR/std/std.c"
  "$ABI_SRC_DIR/std/io/io.c"
  "$ABI_SRC_DIR/std/file/file.c"
  "$ABI_SRC_DIR/std/path/path.c"
  "$ABI_SRC_DIR/std/value/value.c"
  "$ABI_SRC_DIR/std/gc/gc.c"
  "$ABI_SRC_DIR/platform/platform.c"
  "$ABI_SRC_DIR/platform/lib_c/lib_c.c"
)

mkdir -p "$BUILD_DIR"

export DRAGONSTONE_HOME="${DRAGONSTONE_HOME:-$PROJECT_ROOT}"
export DRAGONSTONE_BIN="${DRAGONSTONE_BIN:-$SCRIPT_ROOT}"
export SHARDS_BIN_PATH="${SHARDS_BIN_PATH:-$SCRIPT_ROOT/build}"

show_env() {
  local keys=("$@")
  if [[ ${#keys[@]} -eq 0 ]]; then keys=(DRAGONSTONE_HOME DRAGONSTONE_BIN); fi
  for k in "${keys[@]}"; do
    [[ -n "${!k-}" ]] && echo "$k=${!k}"
  done
}

clean_artifacts() {
  echo "Cleaning build..........."
  local cleaned=0

  if [[ -d "$BUILD_DIR" ]]; then
    rm -rf -- "$BUILD_DIR"
    echo "  Removed: build directory"
    cleaned=$((cleaned+1))
  fi

  if [[ -f "$RESOURCE_OBJ" ]]; then
    rm -f -- "$RESOURCE_OBJ"
    echo "  Removed: dragonstone.o"
    cleaned=$((cleaned+1))
  fi

  if [[ -f "$VERSION_H" ]]; then
    rm -f -- "$VERSION_H"
    echo "  Removed: version.h"
    cleaned=$((cleaned+1))
  fi

  # Clean GC vendor artifacts
  local gc_vendor_lib="$PROJECT_ROOT/src/dragonstone/shared/runtime/abi/std/gc/vendor/lib"
  if [[ -e "$gc_vendor_lib/cord" ]]; then
    rm -f -- "$gc_vendor_lib/cord"
    echo "  Removed: GC vendor/cord symlink"
    cleaned=$((cleaned+1))
  fi

  if [[ -e "$gc_vendor_lib/extra" ]]; then
    rm -f -- "$gc_vendor_lib/extra"
    echo "  Removed: GC vendor/extra symlink"
    cleaned=$((cleaned+1))
  fi

  if [[ -e "$gc_vendor_lib/include" ]]; then
    rm -f -- "$gc_vendor_lib/include"
    echo "  Removed: GC vendor/include symlink"
    cleaned=$((cleaned+1))
  fi

  if [[ -d "$gc_vendor_lib/libatomic_ops" ]]; then
    rm -rf -- "$gc_vendor_lib/libatomic_ops"
    echo "  Removed: GC vendor/libatomic_ops stub"
    cleaned=$((cleaned+1))
  fi

  if [[ $cleaned -eq 0 ]]; then
    echo "  No build files found to clean."
  else
    echo "Cleaned $cleaned files(s)."
  fi
}

needs_rebuild() {
  [[ ! -x "$EXE_PATH" ]] && return 0
  [[ "$SOURCE_ENTRY" -nt "$EXE_PATH" ]] && return 0
  [[ -f "$PROJECT_ROOT/shard.yml"  && "$PROJECT_ROOT/shard.yml"  -nt "$EXE_PATH" ]] && return 0
  [[ -f "$PROJECT_ROOT/shard.lock" && "$PROJECT_ROOT/shard.lock" -nt "$EXE_PATH" ]] && return 0
  if [[ -d "$PROJECT_ROOT/src" ]] && find "$PROJECT_ROOT/src" -type f -newer "$EXE_PATH" -print -quit | grep -q .; then
    return 0
  fi
  if [[ -d "$ABI_SRC_DIR" ]] && find "$ABI_SRC_DIR" -type f \( -name '*.c' -o -name '*.h' \) -newer "$EXE_PATH" -print -quit | grep -q .; then
    return 0
  fi
  return 1
}

pick_cc() {
  local candidate
  for candidate in clang gcc cc; do
    if have "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

gc_platform_id() {
  local uname_s uname_m os_id arch_id
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"
  case "$uname_s" in
    Darwin) os_id="macos" ;;
    Linux) os_id="linux" ;;
    *) os_id="unknown" ;;
  esac
  case "$uname_m" in
    x86_64|amd64) arch_id="x64" ;;
    arm64|aarch64) arch_id="arm64" ;;
    *) arch_id="$uname_m" ;;
  esac
  printf '%s-%s\n' "$os_id" "$arch_id"
}

gc_lib_present() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  [[ -f "$dir/libgc.a" || -f "$dir/libgc.so" || -f "$dir/libgc.dylib" || -f "$dir/gc.lib" ]] || return 1
  return 0
}

gc_include_dir() {
  local platform
  platform="$(gc_platform_id)"
  local build_include="$SCRIPT_ROOT/build/gc/$platform/include"
  if [[ -f "$build_include/gc.h" && -d "$SCRIPT_ROOT/build/gc/$platform/lib" ]] && gc_lib_present "$SCRIPT_ROOT/build/gc/$platform/lib"; then
    echo "$build_include"
    return 0
  fi

  local vendor_root="$PROJECT_ROOT/src/dragonstone/shared/runtime/abi/std/gc/vendor"
  local vendor_lib_candidates=("$vendor_root/lib" "$vendor_root/lib/$platform")
  for candidate in "$vendor_root" "$vendor_root/include"; do
    local has_lib="false"
    local lib_candidate
    for lib_candidate in "${vendor_lib_candidates[@]}"; do
      if gc_lib_present "$lib_candidate"; then
        has_lib="true"
        break
      fi
    done
    if [[ "$has_lib" == "true" && -f "$candidate/gc.h" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  if [[ -n "${DRAGONSTONE_GC_INCLUDE:-}" && -f "$DRAGONSTONE_GC_INCLUDE/gc.h" ]]; then
    echo "$DRAGONSTONE_GC_INCLUDE"
    return 0
  fi

  if [[ -n "${GC_INCLUDE:-}" && -f "$GC_INCLUDE/gc.h" ]]; then
    echo "$GC_INCLUDE"
    return 0
  fi

  if have crystal; then
    local crystal_bin crystal_root
    crystal_bin="$(command -v crystal)"
    crystal_root="$(cd -- "$(dirname -- "$crystal_bin")/.." && pwd)"
    for candidate in \
      "$crystal_root/include" \
      "$crystal_root/lib/gc/include" \
      "$crystal_root/lib/gc/include/gc" \
      "$crystal_root/lib/gc"; do
      if [[ -f "$candidate/gc.h" ]]; then
        echo "$candidate"
        return 0
      fi
    done
  fi

  return 1
}

gc_lib_dir() {
  local platform
  platform="$(gc_platform_id)"
  local build_lib="$SCRIPT_ROOT/build/gc/$platform/lib"
  if gc_lib_present "$build_lib"; then
    echo "$build_lib"
    return 0
  fi

  local vendor_root="$PROJECT_ROOT/src/dragonstone/shared/runtime/abi/std/gc/vendor"
  for candidate in "$vendor_root/lib" "$vendor_root/lib/$platform"; do
    if gc_lib_present "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  if [[ -n "${DRAGONSTONE_GC_LIB:-}" && -d "$DRAGONSTONE_GC_LIB" ]] && gc_lib_present "$DRAGONSTONE_GC_LIB"; then
    echo "$DRAGONSTONE_GC_LIB"
    return 0
  fi

  if [[ -n "${GC_LIB:-}" && -d "$GC_LIB" ]] && gc_lib_present "$GC_LIB"; then
    echo "$GC_LIB"
    return 0
  fi

  return 1
}

build_abi_objects() {
  local cc
  cc="$(pick_cc)" || die "C compiler not found (needed to build ABI)."
  local gc_include=""
  if gc_include="$(gc_include_dir)"; then
    :
  else
    gc_include=""
  fi
  local ar_tool
  if have ar; then
    ar_tool="ar"
  elif have llvm-ar; then
    ar_tool="llvm-ar"
  else
    die "Archive tool not found (needed to build ABI library)."
  fi
  local obj_dir="$BUILD_DIR/abi"
  mkdir -p "$obj_dir"
  local objs=()
  local src rel obj
  for src in "${ABI_SOURCES[@]}"; do
    [[ -f "$src" ]] || continue
    rel="${src#$ABI_SRC_DIR/}"
    obj="$obj_dir/${rel//\//_}"
    obj="${obj%.c}.o"
    if [[ ! -f "$obj" || "$src" -nt "$obj" ]]; then
      if [[ "$src" == *"/std/gc/gc.c" ]]; then
        [[ -n "$gc_include" ]] || die "Boehm GC headers not found. Set DRAGONSTONE_GC_INCLUDE or GC_INCLUDE."
        "$cc" -std=c11 -O2 -I"$gc_include" -c "$src" -o "$obj"
      elif [[ -n "$gc_include" ]]; then
        "$cc" -std=c11 -O2 -I"$gc_include" -c "$src" -o "$obj"
      else
        "$cc" -std=c11 -O2 -c "$src" -o "$obj"
      fi
    fi
    objs+=("$obj")
  done
  local lib_path="$BUILD_DIR/libdragonstone_abi.a"
  local rebuild_lib="false"
  if [[ ! -f "$lib_path" ]]; then
    rebuild_lib="true"
  else
    local obj
    for obj in "${objs[@]}"; do
      if [[ "$obj" -nt "$lib_path" ]]; then
        rebuild_lib="true"
        break
      fi
    done
  fi
  if [[ "$rebuild_lib" == "true" ]]; then
    "$ar_tool" rcs "$lib_path" "${objs[@]}"
  fi
  printf '%s\n' "$lib_path"
}

build_dragonstone() {
  local force="${1:-false}"

  [[ -f "$SOURCE_ENTRY" ]] || die "Missing source entry: $SOURCE_ENTRY"
  have crystal || die "crystal not found on PATH (needed to build)."

  if [[ "$force" != "true" ]] && ! needs_rebuild; then
    return 0
  fi

  mkdir -p "$BUILD_DIR"
  echo "Building Dragonstone....."
  if [[ -x "$PROJECT_ROOT/scripts/build_gc.sh" ]]; then
    "$PROJECT_ROOT/scripts/build_gc.sh" --if-needed
  elif [[ -f "$PROJECT_ROOT/scripts/build_gc.sh" ]]; then
    bash "$PROJECT_ROOT/scripts/build_gc.sh" --if-needed
  fi
  local abi_lib
  abi_lib="$(build_abi_objects)"
  local link_flags=()
  if [[ -n "$abi_lib" ]]; then
    link_flags+=("-L$BUILD_DIR")
  fi
  local gc_lib_dir=""
  if gc_lib_dir="$(gc_lib_dir)"; then
    if [[ -f "$gc_lib_dir/libgc.a" || -f "$gc_lib_dir/libgc.so" || -f "$gc_lib_dir/libgc.dylib" ]]; then
      link_flags+=("-L$gc_lib_dir" "-lgc")
    fi
  fi
  if [[ -f "$RESOURCE_OBJ" ]]; then
    link_flags+=("$RESOURCE_OBJ")
  fi
  if [[ ${#link_flags[@]} -gt 0 ]]; then
    crystal build "$SOURCE_ENTRY" -o "$EXE_PATH" --release --link-flags "${link_flags[*]}"
  else
    crystal build "$SOURCE_ENTRY" -o "$EXE_PATH" --release
  fi
  echo "Dragonstone has successfully built!"
}

install_to_path() {
  local target_dir="$HOME/.local/bin"
  mkdir -p "$target_dir"
  ln -sf "$SELF" "$target_dir/dragonstone"
  echo "Installed: $target_dir/dragonstone -> $SELF"

  case ":$PATH:" in
    *":$target_dir:"*) ;;
    *)
      echo
      echo "Add this to ~/.bashrc or ~/.zshrc, then restart your shell:"
      echo "  export PATH=\"$target_dir:\$PATH\""
      ;;
  esac
}

force_rebuild="false"

if [[ $# -gt 0 ]]; then
  case "${1,,}" in
    --clean) clean_artifacts; exit 0 ;;
    --clean-rebuild) clean_artifacts; force_rebuild="true"; shift ;;
    --rebuild) force_rebuild="true"; shift ;;
    install|--install) install_to_path; exit 0 ;;
  esac
fi

if [[ $# -gt 0 && "${1,,}" == "env" ]]; then
  shift
  show_env "$@"
  exit 0
fi

build_dragonstone "$force_rebuild"
exec "$EXE_PATH" "$@"
