$ErrorActionPreference = "Stop"

# Selective run examples in bootstrap for regression testing.
# This is for run only, no backends.

function Run-Type([string]$file, [string]$runtype) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host "FILE    : $file"

    if ([string]::IsNullOrWhiteSpace($runtype)) {
        Write-Host "RUNTYPE : run"
        Write-Host "CMD     : .\bin\build\dragonstone.exe run .\bootstrap\bin\main.ds run $file"
        & .\bin\build\dragonstone.exe run .\bootstrap\bin\main.ds run $file
    } else {
        Write-Host "RUNTYPE : $runtype"
        Write-Host "CMD     : .\bin\build\dragonstone.exe run .\bootstrap\bin\main.ds $runtype $file"
        & .\bin\build\dragonstone.exe run .\bootstrap\bin\main.ds $runtype $file
    }
}

$files = @(
    # ADD EXAMPLES HERE!
    # Last file cannot have a comma at the end.

    # TIER 0
    # ".\examples\variables\hello_world.ds",
    # ".\examples\variables\echo.ds",
    
    # TIER 1
    # ".\examples\variables\variables.ds",
    # ".\examples\variables\strings.ds",
    # ".\examples\variables\reassignments.ds",
    # ".\examples\variables\debug.ds",
    # ".\examples\variables\typeof.ds",

    # TIER 2
    # ".\examples\math\addition.ds",
    # ".\examples\math\subtraction.ds",
    # ".\examples\math\basic_math.ds",
    # ".\examples\other\equality.ds",
    # ".\examples\other\inequalities.ds",
    # ".\examples\other\shifts.ds",
    # ".\examples\other\ternary.ds",

    # TIER 3
    # ".\examples\other\conditionals.ds",
    # ".\examples\handling\unless.ds",
    # ".\examples\methods\loops.ds",
    # ".\examples\handling\break.ds",
    # ".\examples\handling\next.ds",
    # ".\examples\handling\redo.ds",
    # ".\examples\other\case.ds ",
    # ".\examples\other\comments.ds",
    
    # TIER 4
    # ".\examples\collections\arrays.ds",
    # ".\examples\collections\map.ds",
    # ".\examples\collections\tuple.ds",
    # ".\examples\collections\range.ds",
    # ".\examples\methods\do.ds",
    # ".\examples\methods\select.ds",
    # ".\examples\other\iterator.ds",
    # ".\examples\other\inject.ds",
    
    # TIER 5
    # ".\examples\methods\def.ds",
    # ".\examples\methods\fun.ds ",
    # ".\examples\methods\constants.ds ",
    # ".\examples\other\lambda.ds",
    
    # TIER 6
    # ".\examples\methods\class.ds",
    # ".\examples\methods\accessors.ds",
    # ".\examples\methods\self.ds",
    # ".\examples\methods\visibility.ds ",
    # ".\examples\variables\instance.ds",
    # ".\examples\methods\classes_abstract.ds",
    # ".\examples\methods\super.ds",
    # ".\examples\methods\extend.ds",
    # ".\examples\methods\alias.ds",
    # ".\examples\resolution.ds",
    
    # TIER 7
    # ".\examples\collections\struct.ds",
    # ".\examples\collections\record.ds",
    # ".\examples\collections\enum.ds",
    
    # TIER 8
    # ".\examples\handling\begin.ds",
    # ".\examples\handling\rescue.ds",
    # ".\examples\handling\ensure.ds",
    # ".\examples\handling\retry.ds",
    # ".\examples\handling\yield.ds",
    # ".\examples\raise.ds",
    
    # TIER 9
    # ".\examples\types\types.ds",
    # ".\examples\types\types_math.ds",
    # ".\examples\types\type_casting.ds",
    # ".\examples\cli\argv.ds",
    # ".\examples\cli\io.ds",
    # ".\examples\other\display.ds",
    # ".\examples\other\inspect.ds",
    # ".\examples\other\strip.ds",
    # ".\examples\other\slice.ds",
    
    # TIER 10
    # ".\examples\rosetta\caesar_cipher.ds",
    # ".\examples\math\fibonacci.ds",
    # ".\examples\math\bounce.ds",
    # ".\examples\math\particles.ds"

    # TIER 10+
    # 
)

foreach ($f in $files) {
    Run-Type $f "parse"
    Run-Type $f "lex"
    Run-Type $f ""
}
