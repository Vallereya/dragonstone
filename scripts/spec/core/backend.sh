#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
backend_ci="$repo_root/scripts/backend_ci.sh"

has_backend_flag=false
for arg in "$@"; do
    case "$arg" in
        --backend|--backend=*)
            has_backend_flag=true
            break
            ;;
    esac
done

if [[ "$has_backend_flag" == "false" ]]; then
    exec "$backend_ci" --backend core "$@"
else
    exec "$backend_ci" "$@"
fi
