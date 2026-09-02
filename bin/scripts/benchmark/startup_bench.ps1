<#
    Startup & Lexer Benchmark
#>

param(
    # Seconds allowed for one stage1 cold start. Measured ~2.0s 
    # after lexer fix; 5s leaves room for slower CI hardware 
    # while still catching a return to previous 16.5s.
    [double]$StartupBudget = 5,

    # How much slower a unicode file may lex than its ASCII 
    # variant before we call it a regression. They are within 
    # noise of each other; previously made it 164x.
    [double]$Utf8RatioBudget = 3,

    [switch]$Report
)

. (Join-Path $PSScriptRoot "..\lib\paths.ps1")
Set-Location $DsRoot
Assert-DragonstoneBinary

$work = Join-Path $DsRoot ".cache\benchmark"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# Fixture: 
# N lines of code. The utf8 variant is identical except for
# one leading comment holding a unicode, which is enough to 
# make the whole string non-ascii_only?
function New-Fixture([string]$Path, [int]$Lines, [bool]$NonAscii) {
    $sb = [System.Text.StringBuilder]::new()

    if ($NonAscii) {
        [void]$sb.AppendLine("# note $([char]0x2014) em-dash and arrow $([char]0x2192)")
    }
    for ($i = 0; $i -lt $Lines; $i++) {
        [void]$sb.AppendLine("let value_$i = $i + $($i * 2) # comment $i")
    }
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
}

# Best of N, for scheduler noise & milliseconds for one command run.
function Measure-Best([int]$Runs, [string[]]$CommandArgs) {
    $best = [double]::MaxValue

    for ($i = 0; $i -lt $Runs; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $DsExe @CommandArgs *> $null
        $sw.Stop()

        if ($sw.Elapsed.TotalMilliseconds -lt $best) { $best = $sw.Elapsed.TotalMilliseconds }
    }
    [math]::Round($best)
}

$status = 0

Write-Host "------------------------------------------------------------"
Write-Host "Dragonstone Startup & Lexer Benchmark"
Write-Host "------------------------------------------------------------"

# Part One:
# Stage1 Cold Start
$entry = Join-Path $work "noop.ds"
[System.IO.File]::WriteAllText($entry, "echo `"ready`"`n", [System.Text.UTF8Encoding]::new($false))

$startupMs = Measure-Best 3 @("run", $DsMain, "run", $entry)
$startupS  = [math]::Round($startupMs / 1000, 2)
$budgetMs  = $StartupBudget * 1000

Write-Host ""
Write-Host "Stage1 Cold Start: ${startupMs}ms (${startupS}s)  budget ${StartupBudget}s"
if ($startupMs -gt $budgetMs) {
    Write-Host "  REGRESSION: Stage1 Cold Start exceeds ${StartupBudget}s budget." -ForegroundColor Red
    Write-Host "  This is the number that governs the whole iteration loop."
    Write-Host "  The bootstrap specs pay it once per file, twice per stage."

    $status = 1
} else {
    Write-Host "  OK" -ForegroundColor Green
}

# Part Two:
# Non-ASCII Lexer Parity
Write-Host ""
Write-Host "Stage0 Lexer, ASCII vs Unicode:"
Write-Host ("  {0,-8} {1,-12} {2,-12} {3}" -f "lines", "ascii", "utf8", "ratio")

foreach ($n in @(1000, 4000)) {
    $asciiPath = Join-Path $work "ascii_$n.ds"
    $utf8Path  = Join-Path $work "utf8_$n.ds"

    New-Fixture $asciiPath $n $false
    New-Fixture $utf8Path  $n $true

    $a = Measure-Best 3 @("lex", $asciiPath)
    $u = Measure-Best 3 @("lex", $utf8Path)
    if ($a -lt 1) { $a = 1 }

    $ratio = [math]::Round($u / $a, 2)
    Write-Host ("  {0,-8} {1,-12} {2,-12} {3}x" -f $n, "${a}ms", "${u}ms", $ratio)

    if ($ratio -gt $Utf8RatioBudget) {
        Write-Host "  REGRESSION: Non-ASCII lexing is ${ratio}x slower than ASCII (budget ${Utf8RatioBudget}x)." -ForegroundColor Red
        Write-Host "  The O(n^2) String#[] path is back; see Lexer#initialize."
        $status = 1
    }
}

Write-Host ""
Write-Host "------------------------------------------------------------"
if ($Report) {
    Write-Host "Report-Only: not failing on regressions"
    exit 0
}

if ($status -eq 0) {
    Write-Host "PASS within budget" -ForegroundColor Green
} else {
    Write-Host "FAIL outside budget: see regressions above" -ForegroundColor Red
}
exit $status
