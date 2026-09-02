$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\lib\paths.ps1")
Set-Location $DsRoot
Assert-DragonstoneBinary

New-Item -ItemType Directory -Force -Path $DsDevBuild | Out-Null

function Run-Example([string]$file) {
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "FILE: $file"
    Write-Host "CMD : $DsExe run $DsMain build-run --target c --output $DsDevBuild $file"
    & $DsExe run $DsMain build-run --target c --output $DsDevBuild $file
}

$files = @(
    # Non Categorized Examples
    ".\examples\use.ds",
    # ".\examples\test_use.ds",

    # CLI Examples
    ".\examples\cli\argv.ds",
    # ".\examples\cli\io.ds",

    # Collections Examples
    ".\examples\collections\arrays.ds",
    ".\examples\collections\bag.ds",
    ".\examples\collections\collections.ds",
    ".\examples\collections\enum.ds",
    ".\examples\collections\map.ds",
    ".\examples\collections\para.ds",
    ".\examples\collections\range.ds",
    ".\examples\collections\record.ds",
    ".\examples\collections\struct.ds",
    ".\examples\collections\tuple.ds",

    # #! concurrency examples, skipped for now.
    # ".\examples\concurrency\concurrency_example.ds",
    # ".\examples\concurrency\concurrency.ds",

    # Handling Examples
    ".\examples\handling\begin.ds",
    ".\examples\handling\break.ds",
    ".\examples\handling\ensure.ds",
    ".\examples\handling\next.ds",
    ".\examples\handling\raise.ds",
    ".\examples\handling\redo.ds",
    ".\examples\handling\rescue.ds",
    ".\examples\handling\retry.ds",
    ".\examples\handling\unless.ds",
    ".\examples\handling\yield.ds",

    # #! interop examples, skipped for now.
    # ".\examples\interop\interop.ds",

    # Math Examples
    ".\examples\math\addition.ds",
    ".\examples\math\basic_math.ds",
    ".\examples\math\binaries.ds",
    ".\examples\math\bounce.ds",
    ".\examples\math\fibonacci.ds",
    ".\examples\math\particles.ds",
    ".\examples\math\particle_system.ds",
    ".\examples\math\physics_math.ds",
    ".\examples\math\subtraction.ds",

    # #! memory management examples, skipped for now.
    # ".\examples\memory_management\advanced_example.ds",
    # ".\examples\memory_management\borrow_checker_example.ds",
    # ".\examples\memory_management\borrow_checker.ds",
    # ".\examples\memory_management\garbage_collection_example.ds",
    # ".\examples\memory_management\garbage_collection.ds",

    # Method Examples
    ".\examples\methods\accessors.ds",
    ".\examples\methods\alias.ds",
    ".\examples\methods\block_recursive_locals.ds",
    ".\examples\methods\block_return.ds",
    ".\examples\methods\class.ds",
    ".\examples\methods\classes_abstract.ds",
    ".\examples\methods\constants.ds",
    ".\examples\methods\def.ds",
    ".\examples\methods\do.ds",
    ".\examples\methods\extend.ds",
    ".\examples\methods\fun.ds",
    ".\examples\methods\loops.ds",
    ".\examples\methods\operators.ds",
    ".\examples\methods\overloading.ds",
    ".\examples\methods\resolution.ds",
    ".\examples\methods\select.ds",
    ".\examples\methods\self.ds",
    ".\examples\methods\super.ds",
    ".\examples\methods\visibility.ds",
    ".\examples\methods\with.ds",
    ".\examples\methods\yield_value.ds",
    
    # Other Examples
    ".\examples\other\advanced.ds",
    ".\examples\other\case_patterns.ds",
    ".\examples\other\case.ds",
    ".\examples\other\closures.ds",
    ".\examples\other\comments.ds",
    ".\examples\other\conditionals.ds",
    ".\examples\other\datatypes.ds",
    ".\examples\other\display.ds",
    ".\examples\other\equality.ds",
    ".\examples\other\inequalities.ds",
    ".\examples\other\inject.ds",
    ".\examples\other\inspect.ds",
    ".\examples\other\iterator.ds",
    ".\examples\other\lambda.ds",
    ".\examples\other\shifts.ds",
    ".\examples\other\singleton.ds",
    ".\examples\other\slice.ds",
    ".\examples\other\strip.ds",
    ".\examples\other\ternary.ds",
    ".\examples\other\unicode.ds",

    # #! rosetta examples, skipped for now.
    # ".\examples\rosetta\caesar_cipher.ds",

    # #! stdlib examples, skipped for now.
    # ".\examples\stdlib\use_colorize.ds",
    # ".\examples\stdlib\use_levenshtein.ds",
    # ".\examples\stdlib\use_math.ds",
    # ".\examples\stdlib\use_net.ds",
    # ".\examples\stdlib\use_toml.ds",
    # ".\examples\stdlib\use_unicode.ds",

    # #! syslib examples, skipped for now.
    # ".\examples\stdlib\file_and_path.ds",
    # ".\examples\stdlib\str_build.ds",

    # Types Examples
    ".\examples\types\truthiness.ds",
    ".\examples\types\type_casting.ds",
    ".\examples\types\types_math.ds",
    ".\examples\types\types.ds",

    # Variables Examples
    ".\examples\variables\debug.ds",
    ".\examples\variables\echo.ds",
    ".\examples\variables\hello_world.ds",
    ".\examples\variables\instance.ds",
    ".\examples\variables\reassignments.ds",
    ".\examples\variables\strings.ds",
    ".\examples\variables\typeof.ds",
    ".\examples\variables\variables.ds"
)


foreach ($f in $files) {
    Run-Example $f
}
