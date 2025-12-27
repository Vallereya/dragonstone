#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <source.ds> [output_binary]" >&2
    exit 1
fi

SOURCE="$1"
OUTPUT="${2:-dev/build/core/llvm/dragonstone_llvm.out}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v clang >/dev/null 2>&1; then
    echo "clang is required to link LLVM artifacts; please install it and rerun." >&2
    exit 1
fi

CRYSTAL_CACHE_DIR="$ROOT/.cache"
TMPDIR="$ROOT/.tmp"
TMP="$TMPDIR"
TEMP="$TMPDIR"

mkdir -p "$CRYSTAL_CACHE_DIR" "$TMPDIR"

CRYSTAL_CACHE_DIR="$CRYSTAL_CACHE_DIR" TMPDIR="$TMPDIR" TMP="$TMP" TEMP="$TEMP" \
    crystal run bin/dragonstone -- build --target llvm "$SOURCE"

LLVM_FILE="dev/build/core/llvm/dragonstone_llvm.ll"
if [[ ! -f "$LLVM_FILE" ]]; then
    echo "LLVM IR not found at $LLVM_FILE" >&2
    exit 1
fi

RUNTIME_STUB="src/dragonstone/core/compiler/targets/llvm/llvm_runtime.c"
RUNTIME_OBJ="dev/build/core/llvm/runtime_stub.o"

mkdir -p "$(dirname "$RUNTIME_OBJ")"
clang -std=c11 -c "$RUNTIME_STUB" -o "$RUNTIME_OBJ"

clang "$LLVM_FILE" "$RUNTIME_OBJ" -o "$OUTPUT"
echo "Linked LLVM artifact -> $OUTPUT"
if [[ -x "$OUTPUT" ]]; then
    "$OUTPUT"
fi
