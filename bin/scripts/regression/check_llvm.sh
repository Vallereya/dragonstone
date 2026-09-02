#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

mkdir -p ./bin/dev/build

run() {
    local file="$1"
    echo
    echo "------------------------------------------------------------"
    echo "FILE: $file"
    echo "CMD : ./bin/dragonstone.sh build-run --target llvm --output ./bin/dev/build $file"
    ./bin/dragonstone.sh build-run --target llvm --output ./bin/dev/build "$file"
}

# Non Categorized Examples
run ./examples/use.ds
# run ./examples/test_use.ds

# CLI Examples
run ./examples/cli/argv.ds
# run ./examples/cli/io.ds

# Collections Examples
run ./examples/collections/arrays.ds
run ./examples/collections/bag.ds
run ./examples/collections/collections.ds
run ./examples/collections/enum.ds
run ./examples/collections/map.ds
run ./examples/collections/para.ds
run ./examples/collections/range.ds
run ./examples/collections/record.ds
run ./examples/collections/struct.ds
run ./examples/collections/tuple.ds

# #! concurrency examples, skipped for now.
# run ./examples/concurrency/concurrency_example.ds
# run ./examples/concurrency/concurrency.ds

# Handling Examples
run ./examples/handling/begin.ds
run ./examples/handling/break.ds
run ./examples/handling/ensure.ds
run ./examples/handling/next.ds
run ./examples/handling/raise.ds
run ./examples/handling/redo.ds
run ./examples/handling/rescue.ds
run ./examples/handling/retry.ds
run ./examples/handling/unless.ds
run ./examples/handling/yield.ds

# #! interop examples, skipped for now.
# run ./examples/interop/interop.ds

# Math Examples
run ./examples/math/addition.ds
run ./examples/math/basic_math.ds
run ./examples/math/binaries.ds
run ./examples/math/bounce.ds
run ./examples/math/fibonacci.ds
run ./examples/math/particles.ds
run ./examples/math/particle_system.ds
run ./examples/math/physics_math.ds
run ./examples/math/subtraction.ds

# #! memory management examples, skipped for now.
# run ./examples/memory_management/advanced_example.ds
# run ./examples/memory_management/borrow_checker_example.ds
# run ./examples/memory_management/borrow_checker.ds
# run ./examples/memory_management/garbage_collection_example.ds
# run ./examples/memory_management/garbage_collection.ds

# Method Examples
run ./examples/methods/accessors.ds
run ./examples/methods/alias.ds
run ./examples/methods/block_recursive_locals.ds
run ./examples/methods/block_return.ds
run ./examples/methods/class.ds
run ./examples/methods/classes_abstract.ds
run ./examples/methods/constants.ds
run ./examples/methods/def.ds
run ./examples/methods/do.ds
run ./examples/methods/extend.ds
run ./examples/methods/fun.ds
run ./examples/methods/loops.ds
run ./examples/methods/operators.ds
run ./examples/methods/overloading.ds
run ./examples/methods/resolution.ds
run ./examples/methods/select.ds
run ./examples/methods/self.ds
run ./examples/methods/super.ds
run ./examples/methods/visibility.ds
run ./examples/methods/with.ds
run ./examples/methods/yield_value.ds

# Other Examples
run ./examples/other/advanced.ds
run ./examples/other/case_patterns.ds
run ./examples/other/case.ds
run ./examples/other/closures.ds
run ./examples/other/comments.ds
run ./examples/other/conditionals.ds
run ./examples/other/datatypes.ds
run ./examples/other/display.ds
run ./examples/other/equality.ds
run ./examples/other/inequalities.ds
run ./examples/other/inject.ds
run ./examples/other/inspect.ds
run ./examples/other/iterator.ds
run ./examples/other/lambda.ds
run ./examples/other/shifts.ds
run ./examples/other/singleton.ds
run ./examples/other/slice.ds
run ./examples/other/strip.ds
run ./examples/other/ternary.ds
run ./examples/other/unicode.ds

# #! rosetta examples, skipped for now.
# run ./examples/rosetta/caesar_cipher.ds

# #! stdlib examples, skipped for now.
# run ./examples/stdlib/use_colorize.ds
# run ./examples/stdlib/use_levenshtein.ds
# run ./examples/stdlib/use_math.ds
# run ./examples/stdlib/use_net.ds
# run ./examples/stdlib/use_toml.ds
# run ./examples/stdlib/use_unicode.ds

# #! syslib examples, skipped for now.
# run ./examples/stdlib/file_and_path.ds
# run ./examples/stdlib/str_build.ds

# Types Examples
run ./examples/types/truthiness.ds
run ./examples/types/type_casting.ds
run ./examples/types/types_math.ds
run ./examples/types/types.ds

# Variables Examples
run ./examples/variables/debug.ds
run ./examples/variables/echo.ds
run ./examples/variables/hello_world.ds
run ./examples/variables/instance.ds
run ./examples/variables/reassignments.ds
run ./examples/variables/strings.ds
run ./examples/variables/typeof.ds
run ./examples/variables/variables.ds
