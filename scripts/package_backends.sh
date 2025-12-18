#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Package Dragonstone backend artifacts into backend-specific directories (and archives).

Usage:
  package_backends.sh [--backend native|core|all] [--output <dir>] [--no-zip]

Options:
  --backend <name>  Backend to package (native, core, or all). Default: all.
  --output <dir>    Directory for staged payloads (defaults to release/backends).
  --no-zip          Skip creating zip archives (stages only).
  -h, --help        Show this help text.
EOF
}

backend="all"
output_root="dev/release/backends"
create_zip=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backend)
            backend="$2"
            shift 2
            ;;
        --backend=*)
            backend="${1#*=}"
            shift
            ;;
        --output)
            output_root="$2"
            shift 2
            ;;
        --output=*)
            output_root="${1#*=}"
            shift
            ;;
        --no-zip)
            create_zip=false
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

case "$backend" in
    native|core|all)
        ;;
    *)
        echo "Invalid backend '$backend' (expected native, core, or all)" >&2
        exit 1
        ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_root="$(cd "$repo_root" && mkdir -p "$output_root" && cd "$output_root" && pwd)"
mkdir -p "$repo_root/dev/release"
archive_root="$(cd "$repo_root/dev/release" && pwd)"

COMMON_PATHS=(
    "LICENSE"
    "README.md"
    "bin/dragonstone"
    "bin/build/dragonstone.exe"
    "bin/dragonstone.ps1"
    "bin/dragonstone.bat"
)

CORE_PATHS=(
    "src/dragonstone/core"
    "src/dragonstone/shared"
    "src/dragonstone/core/runtime"
    "src/dragonstone/core/vm"
)

NATIVE_PATHS=(
    "src/dragonstone/native"
    "src/dragonstone/shared"
    "src/dragonstone/native/runtime"
)

copy_path() {
    local path="$1"
    local stage="$2"
    local source="$repo_root/$path"
    local destination="$stage/$path"

    if [[ -d "$source" ]]; then
        mkdir -p "$(dirname "$destination")"
        rm -rf "$destination"
        cp -R "$source" "$destination"
    elif [[ -f "$source" ]]; then
        mkdir -p "$(dirname "$destination")"
        cp "$source" "$destination"
    else
        echo "[package] Skipping missing path: $path" >&2
    fi
}

write_manifest() {
    local backend="$1"
    local stage="$2"
    local manifest="$stage/manifest.txt"

    {
        echo "backend: $backend"
        echo "generated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "paths:"
        for path in "${COMMON_PATHS[@]}"; do
            echo "  - $path"
        done
        if [[ "$backend" == "core" ]]; then
            for path in "${CORE_PATHS[@]}"; do
                echo "  - $path"
            done
        else
            for path in "${NATIVE_PATHS[@]}"; do
                echo "  - $path"
            done
        fi
    } > "$manifest"
}

verify_backend_stage() {
    local backend="$1"
    local stage="$2"
    case "$backend" in
        core)
            if [[ -e "$stage/src/dragonstone/native" ]]; then
                echo "[package] ERROR: core stage contains native runtime files ($stage/src/dragonstone/native)" >&2
                exit 1
            fi
            ;;
        native)
            if [[ -e "$stage/src/dragonstone/core" ]]; then
                echo "[package] ERROR: native stage contains core runtime files ($stage/src/dragonstone/core)" >&2
                exit 1
            fi
            ;;
    esac
}

create_archive() {
    local backend="$1"
    local stage_dir="$2"
    mkdir -p "$archive_root"
    local archive_path="$archive_root/dragonstone-${backend}.zip"
    if command -v zip >/dev/null 2>&1; then
        (cd "$stage_dir/.." && zip -qry "$archive_path" "$(basename "$stage_dir")")
        echo "[package] Created $archive_path"
    else
        echo "[package] zip command not found; skipping archive creation for $backend" >&2
    fi
}

build_stage() {
    local backend="$1"
    local stage_dir="$output_root/$backend"
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir"

    for path in "${COMMON_PATHS[@]}"; do
        copy_path "$path" "$stage_dir"
    done

    if [[ "$backend" == "core" ]]; then
        for path in "${CORE_PATHS[@]}"; do
            copy_path "$path" "$stage_dir"
        done
    else
        for path in "${NATIVE_PATHS[@]}"; do
            copy_path "$path" "$stage_dir"
        done
    fi

    write_manifest "$backend" "$stage_dir"
    verify_backend_stage "$backend" "$stage_dir"

    if $create_zip; then
        create_archive "$backend" "$stage_dir"
    fi

    echo "[package] Packaged $backend backend into $stage_dir"
}

backends_to_build=()
if [[ "$backend" == "all" ]]; then
    backends_to_build=(native core)
else
    backends_to_build=("$backend")
fi

for entry in "${backends_to_build[@]}"; do
    build_stage "$entry"
done
