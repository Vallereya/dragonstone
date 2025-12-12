#!/usr/bin/env bash
set -euo pipefail
mkdir -p ./dev/build

run() {
    local file="$1"
    echo
    echo "============================================================"
    echo "FILE: $file"
    echo "CMD : ./bin/dragonstone.sh build-run --target llvm --output ./dev/build $file"
    ./bin/dragonstone.sh build-run --target llvm --output ./dev/build "$file"
}

run ./examples/addition.ds
run ./examples/arrays.ds
run ./examples/case.ds
run ./examples/classes.ds
run ./examples/comments.ds
run ./examples/conditionals.ds
run ./examples/equality.ds
run ./examples/hello_world.ds
run ./examples/inequalities.ds
run ./examples/loops.ds
run ./examples/math.ds
run ./examples/subtraction.ds
run ./examples/variables.ds
run ./examples/variables_reassignments.ds
run ./examples/map.ds
run ./examples/strings.ds
run ./examples/fibonacci.ds
run ./examples/struct.ds
run ./examples/tuple.ds
run ./examples/enum.ds
run ./examples/break.ds
run ./examples/next.ds
run ./examples/yield.ds
run ./examples/unless.ds
run ./examples/datatypes.ds
run ./examples/functions.ds
run ./examples/select.ds
run ./examples/begin.ds
run ./examples/ensure.ds
run ./examples/redo.ds
run ./examples/raise.ds
run ./examples/rescue.ds
run ./examples/retry.ds
run ./examples/alias.ds
run ./examples/_debug.ds
run ./examples/bag.ds
run ./examples/binaries.ds
run ./examples/display.ds
run ./examples/do.ds
run ./examples/inspect.ds
run ./examples/shifts.ds
run ./examples/variables_typeof.ds
run ./examples/slice.ds
run ./examples/unicode.ds
run ./examples/extend.ds
run ./examples/resolution.ds
run ./examples/singleton.ds
run ./examples/_advanced.ds
run ./examples/range.ds
run ./examples/inject.ds
run ./examples/variables_instance.ds
run ./examples/lambda.ds
run ./examples/with.ds
run ./examples/collections.ds
run ./examples/para.ds
run ./examples/types.ds
run ./examples/use.ds
run ./examples/interop.ds
run ./examples/physics/math.ds
run ./examples/physics/bounce.ds
run ./examples/physics/particles.ds
run ./examples/physics/particle_system.ds
