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

build_abi_objects() {
  local cc
  cc="$(pick_cc)" || die "C compiler not found (needed to build ABI)."
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
      "$cc" -std=c11 -O2 -c "$src" -o "$obj"
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
  local abi_lib
  abi_lib="$(build_abi_objects)"
  local link_flags=()
  if [[ -n "$abi_lib" ]]; then
    link_flags+=("-L$BUILD_DIR")
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
