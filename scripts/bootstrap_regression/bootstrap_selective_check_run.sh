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
    ./bootstrap/examples/statements/hello_world.ds
    ./bootstrap/examples/statements/multi_statements.ds
    ./bootstrap/examples/statements/newline_statements.ds
    ./bootstrap/examples/statements/reassignments.ds
    ./bootstrap/examples/statements/typeof.ds

    ./bootstrap/examples/comments/comments.ds

    ./bootstrap/examples/imports/use.ds

)

for file in "${FILES[@]}"; do
    run_type "$file" "parse"
    run_type "$file" "lex"
    run_type "$file" ""
done
