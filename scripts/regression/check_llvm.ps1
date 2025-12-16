$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path ".\dev\build" | Out-Null

function Run-Example([string]$file) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "FILE: $file"
    Write-Host "CMD : .\bin\build\dragonstone.exe build-run --target llvm --output .\dev\build $file"
    & .\bin\build\dragonstone.exe build-run --target llvm --output .\dev\build $file
}

$files = @(
    ".\examples\addition.ds",
    ".\examples\arrays.ds",
    ".\examples\case.ds",
    ".\examples\classes.ds",
    ".\examples\comments.ds",
    ".\examples\conditionals.ds",
    ".\examples\equality.ds",
    ".\examples\hello_world.ds",
    ".\examples\inequalities.ds",
    ".\examples\loops.ds",
    ".\examples\math.ds",
    ".\examples\subtraction.ds",
    ".\examples\variables.ds",
    ".\examples\variables_reassignments.ds",
    ".\examples\map.ds",
    ".\examples\strings.ds",
    ".\examples\fibonacci.ds",
    ".\examples\struct.ds",
    ".\examples\tuple.ds",
    ".\examples\enum.ds",
    ".\examples\break.ds",
    ".\examples\next.ds",
    ".\examples\yield.ds",
    ".\examples\unless.ds",
    ".\examples\datatypes.ds",
    ".\examples\functions.ds",
    ".\examples\select.ds",
    ".\examples\begin.ds",
    ".\examples\ensure.ds",
    ".\examples\redo.ds",
    ".\examples\raise.ds",
    ".\examples\rescue.ds",
    ".\examples\retry.ds",
    ".\examples\alias.ds",
    ".\examples\_debug.ds",
    ".\examples\bag.ds",
    ".\examples\binaries.ds",
    ".\examples\display.ds",
    ".\examples\do.ds",
    ".\examples\inspect.ds",
    ".\examples\shifts.ds",
    ".\examples\variables_typeof.ds",
    ".\examples\slice.ds",
    ".\examples\unicode.ds",
    ".\examples\extend.ds",
    ".\examples\resolution.ds",
    ".\examples\singleton.ds",
    ".\examples\_advanced.ds",
    ".\examples\range.ds",
    ".\examples\inject.ds",
    ".\examples\variables_instance.ds",
    ".\examples\lambda.ds",
    ".\examples\with.ds",
    ".\examples\collections.ds",
    ".\examples\para.ds",
    ".\examples\types.ds",
    ".\examples\use.ds",
    ".\examples\interop.ds",
    ".\examples\physics\math.ds",
    ".\examples\physics\bounce.ds",
    ".\examples\physics\particles.ds",
    ".\examples\physics\particle_system.ds",
    ".\examples\stdlib\strings_build.ds",
    ".\examples\stdlib\strings_length.ds",
    ".\examples\stdlib\file.ds"
)


foreach ($f in $files) {
    Run-Example $f
}
