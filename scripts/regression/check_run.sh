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
    ./examples/raise.ds
    ./examples/unicode.ds
    ./examples/resolution.ds
    ./examples/use.ds
    # ./examples/test_use.ds

    ./examples/cli/argv.ds

    ./examples/variables/hello_world.ds
    ./examples/variables/variables.ds
    ./examples/variables/reassignments.ds
    ./examples/variables/strings.ds
    ./examples/variables/typeof.ds
    ./examples/variables/instance.ds
    ./examples/variables/debug.ds
    ./examples/variables/echo.ds

    ./examples/math/addition.ds
    ./examples/math/subtraction.ds
    ./examples/math/basic_math.ds
    ./examples/math/binaries.ds
    ./examples/math/fibonacci.ds
    ./examples/math/physics_math.ds
    ./examples/math/bounce.ds
    ./examples/math/particles.ds
    ./examples/math/particle_system.ds

    ./examples/collections/arrays.ds
    ./examples/collections/map.ds
    ./examples/collections/struct.ds
    ./examples/collections/tuple.ds
    ./examples/collections/enum.ds
    ./examples/collections/range.ds
    ./examples/collections/bag.ds
    ./examples/collections/collections.ds
    ./examples/collections/para.ds

    ./examples/methods/loops.ds
    ./examples/methods/select.ds
    ./examples/methods/alias.ds
    ./examples/methods/do.ds
    ./examples/methods/with.ds
    ./examples/methods/extend.ds
    ./examples/methods/accessors.ds
    ./examples/methods/classes_abstract.ds
    ./examples/methods/constants.ds
    ./examples/methods/self.ds
    ./examples/methods/visibility.ds
    ./examples/methods/super.ds
    ./examples/methods/overloading.ds
    ./examples/methods/fun.ds
    ./examples/methods/class.ds
    ./examples/methods/def.ds

    ./examples/handling/break.ds
    ./examples/handling/next.ds
    ./examples/handling/yield.ds
    ./examples/handling/unless.ds
    ./examples/handling/begin.ds
    ./examples/handling/ensure.ds
    ./examples/handling/redo.ds
    ./examples/handling/rescue.ds
    ./examples/handling/retry.ds

    ./examples/other/case.ds
    ./examples/other/comments.ds
    ./examples/other/conditionals.ds
    ./examples/other/equality.ds
    ./examples/other/inequalities.ds
    ./examples/other/datatypes.ds
    ./examples/other/display.ds
    ./examples/other/inspect.ds
    ./examples/other/shifts.ds
    ./examples/other/slice.ds
    ./examples/other/strip.ds
    ./examples/other/singleton.ds
    ./examples/other/advanced.ds
    ./examples/other/inject.ds
    ./examples/other/lambda.ds
    ./examples/other/ternary.ds
    ./examples/other/iterator.ds
    ./examples/other/interop.ds

    ./examples/types/types.ds
    ./examples/types/type_casting.ds

    # ./examples/stdlib/strings_build.ds
    # ./examples/stdlib/strings_length.ds
    # ./examples/stdlib/file.ds
    # ./examples/stdlib/toml.ds
)

for file in "${FILES[@]}"; do
    run_backend "$file" ""
    run_backend "$file" "auto"
    run_backend "$file" "native"
    run_backend "$file" "core"
done
