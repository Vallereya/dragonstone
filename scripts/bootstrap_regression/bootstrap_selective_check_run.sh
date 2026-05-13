#!/usr/bin/env bash
set -euo pipefail

run_type() {
    local file="$1"
    local backend="$2"   # "parse", "lex", ""

    echo
    echo "============================================================"
    echo "FILE   : $file"
    if [[ -z "$runtype" ]]; then
        echo "RUNTYPE: run"
        echo "CMD    : ./bin/dragonstone.sh run ./bootstrap/bin/main.ds run $file"
        ./bin/dragonstone.sh run ./bootstrap/bin/main.ds run "$file"
    else
        echo "RUNTYPE: $runtype"
        echo "CMD    : ./bin/dragonstone.sh run ./bootstrap/bin/main.ds $runtype $file"
        ./bin/dragonstone.sh run ./bootstrap/bin/main.ds "$runtype" "$file"
    fi
}

FILES=(
    # ADD EXAMPLES HERE!
    ./bootstrap/examples/statements/hello_world.ds
)

for file in "${FILES[@]}"; do
    run_type "$file" "parse"
    run_type "$file" "lex"
    run_type "$file" ""
done
