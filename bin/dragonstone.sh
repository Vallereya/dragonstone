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
  return 1
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
  crystal build "$SOURCE_ENTRY" -o "$EXE_PATH" --release
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
