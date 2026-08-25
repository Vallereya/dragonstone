#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <source.ds> [output_binary]" >&2
    exit 1
fi

SOURCE="$1"
OUTPUT="${2:-bin/build/core/llvm/dragonstone_llvm.out}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v clang >/dev/null 2>&1; then
    echo "clang is required to link LLVM artifacts; please install it and rerun." >&2
    exit 1
fi

CRYSTAL_CACHE_DIR="$ROOT/.cache"
mkdir -p "$CRYSTAL_CACHE_DIR"

CRYSTAL_CACHE_DIR="$CRYSTAL_CACHE_DIR" \
    crystal run bin/dragonstone -- build --target llvm "$SOURCE"

LLVM_FILE="bin/build/core/llvm/dragonstone_llvm.ll"
if [[ ! -f "$LLVM_FILE" ]]; then
    echo "LLVM IR not found at $LLVM_FILE" >&2
    exit 1
fi

RUNTIME_STUB="src/dragonstone/core/compiler/targets/llvm/llvm_runtime.c"
ABI_SOURCES=(
    "src/dragonstone/shared/runtime/abi/abi.c"
    "src/dragonstone/shared/runtime/abi/std/std.c"
    "src/dragonstone/shared/runtime/abi/std/io/io.c"
    "src/dragonstone/shared/runtime/abi/std/file/file.c"
    "src/dragonstone/shared/runtime/abi/std/path/path.c"
    "src/dragonstone/shared/runtime/abi/platform/platform.c"
    "src/dragonstone/shared/runtime/abi/platform/lib_c/lib_c.c"
)
UTF8PROC_SOURCE="src/dragonstone/stdlib/modules/shared/unicode/proc/vendor/utf8proc.c"

output_dir="$(dirname "$LLVM_FILE")"
mkdir -p "$output_dir"

runtime_objects=()
compile_source() {
    local source="$1"
    local obj="$2"
    local extra_args=()
    if [[ "$source" == "$UTF8PROC_SOURCE" ]]; then
        extra_args+=("-DUTF8PROC_STATIC")
    fi
    clang -std=c11 -c "$source" -o "$obj" "${extra_args[@]}"
    runtime_objects+=("$obj")
}

compile_source "$RUNTIME_STUB" "$output_dir/$(basename "$RUNTIME_STUB" .c).o"
for source in "${ABI_SOURCES[@]}"; do
    compile_source "$source" "$output_dir/$(basename "$source" .c).o"
done
compile_source "$UTF8PROC_SOURCE" "$output_dir/$(basename "$UTF8PROC_SOURCE" .c).o"

link_args=("$LLVM_FILE" "${runtime_objects[@]}" -o "$OUTPUT")
if [[ "$(uname -s)" == "Linux" ]]; then
    link_args+=("-lm")
fi
clang "${link_args[@]}"
echo "Linked LLVM artifact -> $OUTPUT"
if [[ -x "$OUTPUT" ]]; then
    "$OUTPUT"
fi
