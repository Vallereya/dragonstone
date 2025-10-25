<# 

Heavily modified from what was in the Crystal 
source, tried to mirror how they build for this.

#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $DragonstoneArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath  = $PSCommandPath
$scriptRoot  = Split-Path -Parent $scriptPath
$projectRoot = Split-Path -Parent $scriptRoot
$exePath     = Join-Path $scriptRoot 'dragonstone.exe'
$sourceEntry = Join-Path $projectRoot 'bin/dragonstone'

if (-not $env:DRAGONSTONE_HOME) {
    $env:DRAGONSTONE_HOME = $projectRoot
}

if (-not $env:DRAGONSTONE_BIN) {
    $env:DRAGONSTONE_BIN = $scriptRoot
}

$pathParts = $env:PATH -split ';' | Where-Object { $_ -ne '' }
if ($pathParts -notcontains $env:DRAGONSTONE_BIN) {
    $env:PATH = ($env:DRAGONSTONE_BIN, $env:PATH) -join ';'
}

function Show-DragonstoneEnv {
    param([string[]] $Keys)

    if (-not $Keys -or $Keys.Count -eq 0) {
        $Keys = @('DRAGONSTONE_HOME', 'DRAGONSTONE_BIN')
    }

    foreach ($key in $Keys) {
        $value = (Get-Item -Path "Env:$key" -ErrorAction SilentlyContinue).Value
        if ($null -ne $value) {
            Write-Output "$key=$value"
        }
    }
}

if ($DragonstoneArgs.Count -gt 0 -and $DragonstoneArgs[0].ToLowerInvariant() -eq 'env') {
    $requested = if ($DragonstoneArgs.Count -gt 1) { 
        $DragonstoneArgs[1..($DragonstoneArgs.Count - 1)] 
    } else { @() }
    Show-DragonstoneEnv $requested
    exit 0
}

if (Test-Path -Path $exePath -PathType Leaf) {
    & $exePath @DragonstoneArgs
    exit $LASTEXITCODE
}

$crystal = Get-Command 'crystal' -ErrorAction SilentlyContinue
if (-not $crystal) {
    Write-Error 'dragonstone.exe was not found and the Crystal compiler is unavailable. Build the project before running Dragonstone.'
    exit 1
}

& $crystal.Path 'run' $sourceEntry '--' @DragonstoneArgs
exit $LASTEXITCODE
