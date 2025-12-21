$ErrorActionPreference = "Stop"

function Run-Backend([string]$file, [string]$backend) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "FILE   : $file"

    if ([string]::IsNullOrWhiteSpace($backend)) {
        Write-Host "BACKEND: (default)"
        Write-Host "CMD    : .\bin\build\dragonstone.exe run $file"
        & .\bin\build\dragonstone.exe run $file
    } else {
        Write-Host "BACKEND: $backend"
        Write-Host "CMD    : .\bin\build\dragonstone.exe run --backend $backend $file"
        & .\bin\build\dragonstone.exe run --backend $backend $file
    }
}

$files = @(
    ".\examples\raise.ds",
    ".\examples\unicode.ds",
    ".\examples\resolution.ds",
    ".\examples\use.ds",
    # ".\examples\test_use.ds",

    ".\examples\cli\argv.ds",

    ".\examples\variables\hello_world.ds",
    ".\examples\variables\variables.ds",
    ".\examples\variables\reassignments.ds",
    ".\examples\variables\strings.ds",
    ".\examples\variables\typeof.ds",
    ".\examples\variables\instance.ds",
    ".\examples\variables\debug.ds",
    ".\examples\variables\echo.ds",

    ".\examples\math\addition.ds",
    ".\examples\math\subtraction.ds",
    ".\examples\math\basic_math.ds",
    ".\examples\math\binaries.ds",
    ".\examples\math\fibonacci.ds",
    ".\examples\math\physics_math.ds",
    ".\examples\math\bounce.ds",
    ".\examples\math\particles.ds",
    ".\examples\math\particle_system.ds",

    ".\examples\collections\arrays.ds",
    ".\examples\collections\map.ds",
    ".\examples\collections\struct.ds",
    ".\examples\collections\tuple.ds",
    ".\examples\collections\enum.ds",
    ".\examples\collections\range.ds",
    ".\examples\collections\bag.ds",
    ".\examples\collections\collections.ds",
    ".\examples\collections\para.ds",

    ".\examples\methods\functions.ds",
    ".\examples\methods\loops.ds",
    ".\examples\methods\select.ds",
    ".\examples\methods\alias.ds",
    ".\examples\methods\do.ds",
    ".\examples\methods\with.ds",
    ".\examples\methods\extend.ds",
    ".\examples\methods\accessors.ds",
    ".\examples\methods\classes.ds",
    ".\examples\methods\classes_abstract.ds",
    ".\examples\methods\constants.ds",
    ".\examples\methods\self.ds",
    ".\examples\methods\visibility.ds",
    ".\examples\methods\super.ds",
    ".\examples\methods\overloading.ds",

    ".\examples\handling\break.ds",
    ".\examples\handling\next.ds",
    ".\examples\handling\yield.ds",
    ".\examples\handling\unless.ds",
    ".\examples\handling\begin.ds",
    ".\examples\handling\ensure.ds",
    ".\examples\handling\redo.ds",
    ".\examples\handling\rescue.ds",
    ".\examples\handling\retry.ds",

    ".\examples\other\case.ds",
    ".\examples\other\comments.ds",
    ".\examples\other\conditionals.ds",
    ".\examples\other\equality.ds",
    ".\examples\other\inequalities.ds",
    ".\examples\other\datatypes.ds",
    ".\examples\other\display.ds",
    ".\examples\other\inspect.ds",
    ".\examples\other\shifts.ds",
    ".\examples\other\slice.ds",
    ".\examples\other\singleton.ds",
    ".\examples\other\advanced.ds",
    ".\examples\other\inject.ds",
    ".\examples\other\lambda.ds",
    ".\examples\other\ternary.ds",
    ".\examples\other\iterator.ds",
    ".\examples\other\interop.ds",

    ".\examples\types\types.ds",
    ".\examples\types\type_casting.ds"

    # ".\examples\stdlib\strings_build.ds",
    # ".\examples\stdlib\strings_length.ds",
    # ".\examples\stdlib\file.ds",
    # ".\examples\stdlib\toml.ds"
)

foreach ($f in $files) {
    Run-Backend $f ""
    Run-Backend $f "auto"
    Run-Backend $f "native"
    Run-Backend $f "core"
}
