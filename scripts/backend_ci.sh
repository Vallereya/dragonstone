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

run_build() {
    restore_entrypoint_source
    echo "[backend-ci] Installing shards (if needed)"
    shards install
    local output_path
    output_path="$(build_output_path)"
    echo "[backend-ci] Building CLI stub -> $output_path (backend=$DRAGONSTONE_BACKEND)"
    crystal build "$entrypoint_source" -o "$output_path"
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
