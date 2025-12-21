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

run ./examples/raise.ds
run ./examples/unicode.ds
run ./examples/resolution.ds
run ./examples/use.ds
# run ./examples/test_use.ds

run ./examples/cli/argv.ds

run ./examples/variables/hello_world.ds
run ./examples/variables/variables.ds
run ./examples/variables/reassignments.ds
run ./examples/variables/strings.ds
run ./examples/variables/typeof.ds
run ./examples/variables/instance.ds
run ./examples/variables/debug.ds
run ./examples/variables/echo.ds

run ./examples/math/addition.ds
run ./examples/math/subtraction.ds
run ./examples/math/basic_math.ds
run ./examples/math/binaries.ds
run ./examples/math/fibonacci.ds
run ./examples/math/physics_math.ds
run ./examples/math/bounce.ds
run ./examples/math/particles.ds
run ./examples/math/particle_system.ds

run ./examples/collections/arrays.ds
run ./examples/collections/map.ds
run ./examples/collections/struct.ds
run ./examples/collections/tuple.ds
run ./examples/collections/enum.ds
run ./examples/collections/range.ds
run ./examples/collections/bag.ds
run ./examples/collections/collections.ds
run ./examples/collections/para.ds

run ./examples/methods/fun.ds
run ./examples/methods/loops.ds
run ./examples/methods/select.ds
run ./examples/methods/alias.ds
run ./examples/methods/do.ds
run ./examples/methods/with.ds
run ./examples/methods/extend.ds
run ./examples/methods/accessors.ds
run ./examples/methods/class.ds
run ./examples/methods/classes_abstract.ds
run ./examples/methods/constants.ds
run ./examples/methods/self.ds
run ./examples/methods/visibility.ds
run ./examples/methods/super.ds
run ./examples/methods/overloading.ds
run ./examples/methods/def.ds

run ./examples/handling/break.ds
run ./examples/handling/next.ds
run ./examples/handling/yield.ds
run ./examples/handling/unless.ds
run ./examples/handling/begin.ds
run ./examples/handling/ensure.ds
run ./examples/handling/redo.ds
run ./examples/handling/rescue.ds
run ./examples/handling/retry.ds

run ./examples/other/case.ds
run ./examples/other/comments.ds
run ./examples/other/conditionals.ds
run ./examples/other/equality.ds
run ./examples/other/inequalities.ds
run ./examples/other/datatypes.ds
run ./examples/other/display.ds
run ./examples/other/inspect.ds
run ./examples/other/shifts.ds
run ./examples/other/slice.ds
run ./examples/other/strip.ds
run ./examples/other/singleton.ds
run ./examples/other/advanced.ds
run ./examples/other/inject.ds
run ./examples/other/lambda.ds
run ./examples/other/ternary.ds
run ./examples/other/iterator.ds
run ./examples/other/interop.ds

run ./examples/types/types.ds
run ./examples/types/type_casting.ds

# run ./examples/stdlib/strings_build.ds
# run ./examples/stdlib/strings_length.ds
# run ./examples/stdlib/file.ds
# run ./examples/stdlib/toml.ds
