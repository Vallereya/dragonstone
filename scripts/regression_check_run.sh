#!/usr/bin/env bash
set -euo pipefail

run_backend() {
    local file="$1"
    local backend="$2"   # "", "auto", "native", "core"

    echo
    echo "============================================================"
    echo "FILE   : $file"
    if [[ -z "$backend" ]]; then
        echo "BACKEND: (default)"
        echo "CMD    : ./bin/dragonstone.sh run $file"
        ./bin/dragonstone.sh run "$file"
    else
        echo "BACKEND: $backend"
        echo "CMD    : ./bin/dragonstone.sh run --backend $backend $file"
        ./bin/dragonstone.sh run --backend "$backend" "$file"
    fi
}

FILES=(
    ./examples/addition.ds
    ./examples/arrays.ds
    ./examples/case.ds
    ./examples/classes.ds
    ./examples/comments.ds
    ./examples/conditionals.ds
    ./examples/equality.ds
    ./examples/hello_world.ds
    ./examples/inequalities.ds
    ./examples/loops.ds
    ./examples/math.ds
    ./examples/subtraction.ds
    ./examples/variables.ds
    ./examples/variables_reassignments.ds
    ./examples/map.ds
    ./examples/strings.ds
    ./examples/fibonacci.ds
    ./examples/struct.ds
    ./examples/tuple.ds
    ./examples/enum.ds
    ./examples/break.ds
    ./examples/next.ds
    ./examples/yield.ds
    ./examples/unless.ds
    ./examples/datatypes.ds
    ./examples/functions.ds
    ./examples/select.ds
    ./examples/begin.ds
    ./examples/ensure.ds
    ./examples/redo.ds
    ./examples/raise.ds
    ./examples/rescue.ds
    ./examples/retry.ds
    ./examples/alias.ds
    ./examples/_debug.ds
    ./examples/bag.ds
    ./examples/binaries.ds
    ./examples/display.ds
    ./examples/do.ds
    ./examples/inspect.ds
    ./examples/shifts.ds
    ./examples/variables_typeof.ds
    ./examples/slice.ds
    ./examples/unicode.ds
    ./examples/extend.ds
    ./examples/resolution.ds
    ./examples/singleton.ds
    ./examples/_advanced.ds
    ./examples/range.ds
    ./examples/inject.ds
    ./examples/variables_instance.ds
    ./examples/lambda.ds
    ./examples/with.ds
    ./examples/collections.ds
    ./examples/para.ds
    ./examples/types.ds
    ./examples/use.ds
    ./examples/interop.ds
    ./examples/stdlib_strings_build.ds
    ./examples/stdlib_strings_length.ds
    ./examples/stdlib_file.ds
    # ./examples/physics/math.ds
    # ./examples/physics/bounce.ds
    # ./examples/physics/particles.ds
    # ./examples/physics/particle_system.ds
)

for file in "${FILES[@]}"; do
    run_backend "$file" ""
    run_backend "$file" "auto"
    run_backend "$file" "native"
    run_backend "$file" "core"
done
