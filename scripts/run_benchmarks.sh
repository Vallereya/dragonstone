#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Dragonstone benchmark helper.

Runs the standard benchmark suite against the requested backend(s) and
prints wall-clock timings so regressions are easy to spot.

Usage:
  run_benchmarks.sh [--backend <native|core|auto|both>] [--program <path>]... [--iterations <N>]

Examples:
  run_benchmarks.sh
  run_benchmarks.sh --backend core --iterations 3
  run_benchmarks.sh --program tests/benchmark/1b.ds --program tests/benchmark/1m.ds
EOF
}

backend_choice="both"
iterations=1
declare -a programs=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backend)
            [[ $# -lt 2 ]] && { echo "Missing value for --backend" >&2; exit 1; }
            backend_choice="$2"
            shift 2
            ;;
        --backend=*)
            backend_choice="${1#*=}"
            shift
            ;;
        --program)
            [[ $# -lt 2 ]] && { echo "Missing value for --program" >&2; exit 1; }
            programs+=("$2")
            shift 2
            ;;
        --program=*)
            programs+=("${1#*=}")
            shift
            ;;
        --iterations)
            [[ $# -lt 2 ]] && { echo "Missing value for --iterations" >&2; exit 1; }
            iterations="$2"
            shift 2
            ;;
        --iterations=*)
            iterations="${1#*=}"
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

case "$backend_choice" in
    both)
        backends=(native core)
        ;;
    native|core|auto)
        backends=("$backend_choice")
        ;;
    *)
        echo "Invalid backend '$backend_choice'. Expected native, core, auto, or both." >&2
        exit 1
        ;;
esac

if ! [[ "$iterations" =~ ^[0-9]+$ ]] || [[ "$iterations" -lt 1 ]]; then
    echo "Iterations must be a positive integer" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

if [[ ${#programs[@]} -eq 0 ]]; then
    default_programs=(
        tests/benchmark/1b.ds
        tests/benchmark/1b_nested.ds
        tests/benchmark/1m.ds
        tests/benchmark/1m_nested.ds
    )
    for candidate in "${default_programs[@]}"; do
        [[ -f "$candidate" ]] && programs+=("$candidate")
    done
fi

if [[ ${#programs[@]} -eq 0 ]]; then
    echo "No benchmark programs found. Provide paths via --program." >&2
    exit 1
fi

cli_path="$repo_root/bin/dragonstone"
if [[ "${OS:-}" == "Windows_NT" ]] && [[ -x "${cli_path}.exe" ]]; then
    cli_path="${cli_path}.exe"
fi

if [[ ! -x "$cli_path" ]]; then
    echo "CLI binary '$cli_path' not found or not executable. Run shards build first." >&2
    exit 1
fi

measure_run() {
    local backend="$1"
    local program="$2"

    local stdout_file stderr_file
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    set +e
    local timing_output
    timing_output="$({ time -p "$cli_path" run --backend "$backend" "$program" >"$stdout_file" 2>"$stderr_file"; } 2>&1)"
    local status=$?
    set -e

    if [[ $status -ne 0 ]]; then
        echo "Benchmark failed for $program on backend $backend" >&2
        cat "$stderr_file" >&2
        rm -f "$stdout_file" "$stderr_file"
        exit $status
    fi

    local real_seconds
    real_seconds="$(printf '%s\n' "$timing_output" | awk '/^real / {print $2}' | tail -n1)"

    rm -f "$stdout_file" "$stderr_file"

    if [[ -z "$real_seconds" ]]; then
        echo "Unable to parse timing output for $program ($backend)" >&2
        exit 1
    fi

    printf '%s' "$real_seconds"
}

printf "%-28s %-8s %5s %12s\n" "Program" "Backend" "Iter" "Seconds"
printf "%-28s %-8s %5s %12s\n" "--------" "-------" "----" "-------"

for program in "${programs[@]}"; do
    if [[ ! -f "$program" ]]; then
        echo "Program '$program' not found" >&2
        exit 1
    fi
    program_label="$(basename "$program")"
    for backend in "${backends[@]}"; do
        for ((iter=1; iter<=iterations; iter++)); do
            seconds="$(measure_run "$backend" "$program")"
            printf "%-28s %-8s %5d %12s\n" "$program_label" "$backend" "$iter" "$seconds"
        done
    done
done
