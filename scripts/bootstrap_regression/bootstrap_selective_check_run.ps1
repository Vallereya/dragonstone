$ErrorActionPreference = "Stop"

# Selective run examples in bootstrap for regression testing.
# This is for run only, no backends.

function Run-Type([string]$file, [string]$runtype) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "FILE   : $file"

    if ([string]::IsNullOrWhiteSpace($runtype)) {
        Write-Host "RUNTYPE: run"
        Write-Host "CMD    : .\bin\build\dragonstone.exe run .\bootstrap\bin\main.ds run $file"
        & .\bin\build\dragonstone.exe run .\bootstrap\bin\main.ds run $file
    } else {
        Write-Host "RUNTYPE: $runtype"
        Write-Host "CMD    : .\bin\build\dragonstone.exe run .\bootstrap\bin\main.ds $runtype $file"
        & .\bin\build\dragonstone.exe run .\bootstrap\bin\main.ds $runtype $file
    }
}

$files = @(
    # ADD EXAMPLES HERE!
    # Last file cannot have a comma at the end.
    ".\bootstrap\examples\statements\hello_world.ds",
    ".\bootstrap\examples\statements\multi_statements.ds"
)

foreach ($f in $files) {
    Run-Type $f "parse"
    Run-Type $f "lex"
    Run-Type $f ""
}
