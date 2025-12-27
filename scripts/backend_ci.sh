#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Backend-aware CI helper for Dragonstone.

Usage:
  backend_ci.sh [ci|build|spec|test] [--backend <auto|native|core>]

Examples:
  backend_ci.sh                      # shards build && crystal spec with current backend (default auto)
  backend_ci.sh spec --backend core  # run specs using the bytecode backend
  backend_ci.sh build                # build only, honoring DRAGONSTONE_BACKEND if set
EOF
}

task="ci"
backend="${DRAGONSTONE_BACKEND:-auto}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        build|spec|test|ci)
            task="$1"
            shift
            ;;
        --backend)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --backend" >&2
                exit 1
            fi
            backend="$2"
            shift 2
            ;;
        --backend=*)
            backend="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

backend="$(printf '%s' "$backend" | tr '[:upper:]' '[:lower:]')"
case "$backend" in
    auto|native|core)
        ;;
    *)
        echo "Invalid backend '$backend' (expected auto, native, or core)" >&2
        exit 1
        ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

export DRAGONSTONE_BACKEND="$backend"

ABI_SRC_DIR="$repo_root/src/dragonstone/shared/runtime/abi"
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

entrypoint_source="$repo_root/bin/dragonstone"

restore_entrypoint_source() {
    local magic
    if [[ -f "$entrypoint_source" ]]; then
        magic="$(head -c 4 "$entrypoint_source" 2>/dev/null || true)"
        case "$magic" in
            $'\x7fELF'|MZ*)
                echo "[backend-ci] CLI entrypoint was binary; restoring Crystal stub"
                ;;
            *)
                return
                ;;
        esac
    else
        echo "[backend-ci] CLI entrypoint missing; creating Crystal stub"
    fi

    cat <<'EOF' > "$entrypoint_source"
# ---------------------------------
# ------------ ENTRY --------------
# ---------------------------------
require "../src/dragonstone/cli/cli"

# This is the main entry, which just pushes 
# to cli, this is a crystal file despite
# not having an extension (that's on purpose).
exit Dragonstone::CLI.run
EOF
    chmod +x "$entrypoint_source"
}

build_output_path() {
    local base="$repo_root/bin/dragonstone-dev"
    if [[ "${OS:-}" == "Windows_NT" ]]; then
        base="${base}.exe"
    fi
    printf '%s\n' "$base"
}

pick_cc() {
    local candidate
    for candidate in clang gcc cc; do
        if command -v "$candidate" >/dev/null 2>&1; then
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
    local build_include="$repo_root/bin/build/gc/$platform/include"
    if [[ -f "$build_include/gc.h" && -d "$repo_root/bin/build/gc/$platform/lib" ]] && gc_lib_present "$repo_root/bin/build/gc/$platform/lib"; then
        echo "$build_include"
        return 0
    fi

    local vendor_root="$repo_root/src/dragonstone/shared/runtime/abi/std/gc/vendor"
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

    return 1
}

gc_lib_dir() {
    local platform
    platform="$(gc_platform_id)"
    local build_lib="$repo_root/bin/build/gc/$platform/lib"
    if gc_lib_present "$build_lib"; then
        echo "$build_lib"
        return 0
    fi

    local vendor_root="$repo_root/src/dragonstone/shared/runtime/abi/std/gc/vendor"
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
    cc="$(pick_cc)" || { echo "[backend-ci] C compiler not found (needed to build ABI)" >&2; return 1; }
    local gc_include=""
    if gc_include="$(gc_include_dir)"; then
        :
    else
        gc_include=""
    fi
    local ar_tool=""
    if command -v ar >/dev/null 2>&1; then
        ar_tool="ar"
    elif command -v llvm-ar >/dev/null 2>&1; then
        ar_tool="llvm-ar"
    else
        echo "[backend-ci] Archive tool not found (needed to build ABI)" >&2
        return 1
    fi
    local obj_dir="$repo_root/bin/build/abi"
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
                [[ -n "$gc_include" ]] || { echo "[backend-ci] Boehm GC headers not found. Set DRAGONSTONE_GC_INCLUDE or GC_INCLUDE." >&2; return 1; }
                "$cc" -std=c11 -O2 -I"$gc_include" -c "$src" -o "$obj"
            elif [[ -n "$gc_include" ]]; then
                "$cc" -std=c11 -O2 -I"$gc_include" -c "$src" -o "$obj"
            else
                "$cc" -std=c11 -O2 -c "$src" -o "$obj"
            fi
        fi
        objs+=("$obj")
    done
    local lib_path="$repo_root/bin/build/libdragonstone_abi.a"
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

run_build() {
    restore_entrypoint_source
    echo "[backend-ci] Installing shards (if needed)"
    shards install
    local output_path
    output_path="$(build_output_path)"
    echo "[backend-ci] Building CLI stub -> $output_path (backend=$DRAGONSTONE_BACKEND)"
    abi_lib="$(build_abi_objects)"
    if [[ -n "$abi_lib" ]]; then
        local link_flags="-L$repo_root/bin/build"
        local gc_lib=""
        if gc_lib="$(gc_lib_dir)"; then
            if [[ -f "$gc_lib/libgc.a" || -f "$gc_lib/libgc.so" || -f "$gc_lib/libgc.dylib" ]]; then
                link_flags="$link_flags -L$gc_lib -lgc"
            fi
        fi
        crystal build "$entrypoint_source" -o "$output_path" --link-flags "$link_flags"
    else
        crystal build "$entrypoint_source" -o "$output_path"
    fi
}

run_spec() {
    echo "[backend-ci] Running specs (backend=$DRAGONSTONE_BACKEND)"
    crystal spec
}

case "$task" in
    build)
        run_build
        ;;
    spec|test)
        run_spec
        ;;
    ci)
        run_build
        run_spec
        ;;
esac
