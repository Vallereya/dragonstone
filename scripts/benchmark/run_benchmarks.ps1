param(
    [ValidateSet("native", "core", "auto", "both")]
    [string]$Backend = "both",
    [int]$Iterations = 1,
    [string[]]$Programs
)

function Show-Usage {
    @"
Dragonstone benchmark helper.

Usage:
  .\run_benchmarks.ps1 [-Backend native|core|auto|both] [-Iterations N] [-Programs <path>...]

Examples:
  .\run_benchmarks.ps1
  .\run_benchmarks.ps1 -Backend core -Iterations 3
  .\run_benchmarks.ps1 -Programs scripts\benchmark\1b.ds,scripts\benchmark\1m.ds
"@
}

if ($Iterations -lt 1) {
    Write-Error "Iterations must be a positive integer."
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
Set-Location $repoRoot

if (-not $Programs -or $Programs.Count -eq 0) {
    $defaultPrograms = @(
        "scripts\benchmark\1b.ds",
        "scripts\benchmark\1b_nested.ds",
        "scripts\benchmark\1m.ds",
        "scripts\benchmark\1m_nested.ds"
    ) | Where-Object { Test-Path $_ }
    $Programs = $defaultPrograms
}

if (-not $Programs -or $Programs.Count -eq 0) {
    Write-Error "No benchmark programs were found. Pass paths with -Programs."
    exit 1
}

$cliPath = Join-Path $repoRoot "bin\build\dragonstone.exe"
if (-not (Test-Path $cliPath)) {
    $cliPath = Join-Path $repoRoot "bin\dragonstone"
}

if (-not (Test-Path $cliPath)) {
    Write-Error "CLI binary not found. Run shards build first."
    exit 1
}

switch ($Backend) {
    "both" { $backends = @("native", "core") }
    default { $backends = @($Backend) }
}

"{0,-28} {1,-8} {2,-5} {3,10}" -f "Program", "Backend", "Iter", "Seconds"
"{0,-28} {1,-8} {2,-5} {3,10}" -f "--------", "-------", "----", "-------"

foreach ($program in $Programs) {
    if (-not (Test-Path $program)) {
        Write-Error "Program '$program' not found."
        exit 1
    }

    $resolved = (Resolve-Path -LiteralPath $program).Path
    $label = Split-Path -Leaf $resolved

    foreach ($backend in $backends) {
        for ($i = 1; $i -le $Iterations; $i++) {
            $stdoutFile = [System.IO.Path]::GetTempFileName()
            $stderrFile = [System.IO.Path]::GetTempFileName()

            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            & $cliPath run --backend $backend $resolved 1> $stdoutFile 2> $stderrFile
            $exitCode = $LASTEXITCODE
            $timer.Stop()

            if ($exitCode -ne 0) {
                $errorOutput = Get-Content $stderrFile | Out-String
                Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
                Write-Error "Benchmark failed for $resolved on $backend`n$errorOutput"
                exit $exitCode
            }

            Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
            $seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 4)
            "{0,-28} {1,-8} {2,5} {3,10:F4}" -f $label, $backend, $i, $seconds
        }
    }
}
