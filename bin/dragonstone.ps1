<# 

Heavily modified from what was in the Crystal source.

#>

<# 

Commands, I need to remember to rebuild if needed.

    Using either commands will add an icon to dragonstone.exe:
        powershell -ExecutionPolicy Bypass -File .\bin\dragonstone.ps1 --rebuild-exe
        dragonstone.bat --rebuild-exe

    Using the normal crystal/shards build command does not add icon to dragonstone.exe:
        shards build

#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $DragonstoneArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($null -eq $DragonstoneArgs) {
    [string[]]$DragonstoneArgs = @()
}

$scriptPath   = $PSCommandPath
$scriptRoot   = Split-Path -Parent $scriptPath
$projectRoot  = Split-Path -Parent $scriptRoot
$exePath      = Join-Path $scriptRoot 'dragonstone.exe'
$sourceEntry  = Join-Path $projectRoot 'bin/dragonstone'

$resourceScript = $null
$resourceOutputBase = $null
$resourceSearchRoots = @(
    (Join-Path $projectRoot 'resources'),
    (Join-Path $scriptRoot 'resources')
)

foreach ($root in $resourceSearchRoots) {
    if (-not $root) { continue }
    $candidate = Join-Path $root 'dragonstone.rc'
    if (Test-Path -Path $candidate -PathType Leaf) {
        $resourceScript = $candidate
        $resourceOutputBase = Join-Path $root 'dragonstone'
        break
    }
}

if (-not $env:DRAGONSTONE_HOME) {
    $env:DRAGONSTONE_HOME = $projectRoot
}

if (-not $env:DRAGONSTONE_BIN) {
    $env:DRAGONSTONE_BIN = $scriptRoot
}

$pathParts = @($env:PATH -split ';' | Where-Object { $_ -ne '' })
if ($pathParts -notcontains $env:DRAGONSTONE_BIN) {
    $env:PATH = ($env:DRAGONSTONE_BIN, $env:PATH) -join ';'
}

function NormalizeArray {
    param([object] $Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value)
    }

    return ,@($Value)
}

function Show-DragonstoneEnv {
    param([string[]] $Keys)

    $Keys = NormalizeArray $Keys

    $keyCount = @($Keys).Count
    if ($keyCount -eq 0) {
        $Keys = @('DRAGONSTONE_HOME', 'DRAGONSTONE_BIN')
    }

    foreach ($key in $Keys) {
        $value = (Get-Item -Path "Env:$key" -ErrorAction SilentlyContinue).Value
        if ($null -ne $value) {
            Write-Output "$key=$value"
        }
    }
}

function Get-RelativePath {
    param(
        [string] $BasePath,
        [string] $TargetPath
    )

    if ([string]::IsNullOrWhiteSpace($BasePath) -or [string]::IsNullOrWhiteSpace($TargetPath)) {
        return $TargetPath
    }

    try {
        $base = $BasePath
        if (-not ($base.EndsWith([System.IO.Path]::DirectorySeparatorChar) -or $base.EndsWith([System.IO.Path]::AltDirectorySeparatorChar))) {
            $base += [System.IO.Path]::DirectorySeparatorChar
        }

        $baseUri = [System.Uri]::new($base)
        $targetUri = [System.Uri]::new($TargetPath)

        if ($baseUri.Scheme -ne $targetUri.Scheme) {
            return $TargetPath
        }

        $relativeUri = $baseUri.MakeRelativeUri($targetUri)
        $relative = [System.Uri]::UnescapeDataString($relativeUri.ToString())
        return $relative
    } catch {
        return $TargetPath
    }
}

function CompileDragonstoneResource {
    param(
        [string] $ScriptPath,
        [string] $OutputBase
    )

    if ([string]::IsNullOrWhiteSpace($ScriptPath) -or [string]::IsNullOrWhiteSpace($OutputBase)) {
        return $null
    }

    if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
        Write-Warning "WARNING: Resource script not found at: $ScriptPath"
        return $null
    }

    $tool = $null
    $toolNames = @('windres', 'x86_64-w64-mingw32-windres', 'llvm-rc')
    foreach ($name in $toolNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            $tool = $command
            break
        }
    }

    if (-not $tool) {
        Write-Warning 'WARNING: No resource compiler (windres/x86_64-w64-mingw32-windres/llvm-rc) was found; the executable will be built without the custom icon.'
        return $null
    }

    Write-Host "Found resource compiler: $($tool.Name)"

    $extension = '.res'
    if ($tool.Name -notlike 'llvm-rc*') {
        $extension = '.o'
    }

    $outputPath = "$OutputBase$extension"

    $outputDir = Split-Path -Parent $outputPath
    if (-not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    $rcDir = Split-Path -Parent $ScriptPath
    $rcFileName = Split-Path -Leaf $ScriptPath
    $originalLocation = Get-Location
    
    Write-Host "Compiling resource from directory: $rcDir"
    Write-Host "Using Resource file: $rcFileName"
    
    try {
        Set-Location $rcDir
        
        if ($tool.Name -like 'llvm-rc*') {
            Write-Host "Running: $($tool.Name) -fo $outputPath $rcFileName"
            & $tool.Path '-fo' $outputPath $rcFileName
        } else {
            Write-Host "Running: $($tool.Name) $rcFileName -O coff -o $outputPath"
            & $tool.Path $rcFileName '-O' 'coff' '-o' $outputPath
        }

        if ($LASTEXITCODE -ne 0) {
            throw "ERROR: Failed to compile $ScriptPath using $($tool.Name). Exit code: $LASTEXITCODE"
        }

        if (-not (Test-Path -Path $outputPath -PathType Leaf)) {
            throw "WARNING: Resource compilation appeared to succeed but output file not found at: $outputPath"
        }

        Write-Host "Successfully compiled icon resource: $outputPath"
        return $outputPath
    } catch {
        Write-Warning "ERROR: Resource compilation failed: $($_.Exception.Message)"
        throw
    } finally {
        Set-Location $originalLocation
    }
}

function EnsureDragonstoneExecutable {
    param([switch] $Force)

    $exeExists = Test-Path -Path $exePath -PathType Leaf
    if (-not $Force -and $exeExists) {
        return $true
    }

    if (-not $script:shards -and -not $script:crystal) {
        if ($Force) {
            throw 'ERROR: Neither shards nor crystal was found on PATH; cannot rebuild dragonstone.exe.'
        }

        return $exeExists
    }

    Write-Host 'Building Dragonstone...'

    $resourcePath = $null
    if ($resourceScript) {
        Write-Host "Running resource script: $resourceScript"
    } else {
        Write-Host 'WARNING: The dragonstone.rc resource script was found; But, continuing without embedding an icon to the dragonstone.exe'
    }

    try {
        $resourcePath = CompileDragonstoneResource -ScriptPath $resourceScript -OutputBase $resourceOutputBase
    } catch {
        if ($Force) {
            throw
        }

        Write-Warning $_.Exception.Message
    }

    $envFlagSet = $false
    $resourceLinkArg = $null
    if ($resourcePath) {
        $resourceLinkArg = $resourcePath
        $resourceLinkArg = $resourceLinkArg -replace '\\','/'

        Write-Host "Resource object file: $resourceLinkArg"
        Write-Host "Passing resource to linker: $resourceLinkArg"

        $env:CRFLAGS = "--link-flags `"$resourceLinkArg`""
        $envFlagSet = $true
    }

    try {
        if ($resourceLinkArg -and $script:crystal) {
            $buildArgs = @('build', $sourceEntry, '-o', $exePath, '--release', '--link-flags', $resourceLinkArg)
            Write-Host "Building with crystal: crystal $($buildArgs -join ' ')"
            & $script:crystal.Path @buildArgs
        } elseif ($script:shards) {
            Write-Host "Building with shards..."
            if ($resourceLinkArg) {
                Write-Host "CRFLAGS environment variable: $env:CRFLAGS"
                Write-Host "WARNING: shards may not pick up CRFLAGS. Consider using crystal build directly."
            }
            & $script:shards.Path 'build'
        } else {
            $buildArgs = @('build', $sourceEntry, '-o', $exePath, '--release')
            Write-Host "Building with crystal: crystal $($buildArgs -join ' ')"
            & $script:crystal.Path @buildArgs
        }

        if ($LASTEXITCODE -ne 0) {
            if ($Force) {
                throw "Build command exited with status $LASTEXITCODE."
            }

            Write-Warning "Build command exited with status $LASTEXITCODE."
            return Test-Path -Path $exePath -PathType Leaf
        }

        Write-Host "Dragonstone has successfully built!"
    } finally {
        if ($envFlagSet) {
            Remove-Item Env:CRFLAGS -ErrorAction SilentlyContinue
        }
    }

    return (Test-Path -Path $exePath -PathType Leaf)
}

$forceRebuild = $false

$argCount = @($DragonstoneArgs).Count
if ($argCount -gt 0) {
    $firstArg = $DragonstoneArgs[0].ToLowerInvariant()
    if ($firstArg -eq '--rebuild-exe') {
        $forceRebuild = $true
        if ($argCount -gt 1) {
            $DragonstoneArgs = $DragonstoneArgs[1..($argCount - 1)]
        } else {
            [string[]]$DragonstoneArgs = @()
        }
    }
}

$argCount = @($DragonstoneArgs).Count
if ($argCount -gt 0 -and $DragonstoneArgs[0].ToLowerInvariant() -eq 'env') {
    $requested = @()
    if ($argCount -gt 1) { 
        $requested = $DragonstoneArgs[1..($argCount - 1)]
    }
    Show-DragonstoneEnv $requested
    exit 0
}

$script:shards  = Get-Command 'shards' -ErrorAction SilentlyContinue
$script:crystal = Get-Command 'crystal' -ErrorAction SilentlyContinue

try {
    $buildEnsured = EnsureDragonstoneExecutable -Force:$forceRebuild
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

if (-not $buildEnsured -and -not (Test-Path -Path $exePath -PathType Leaf)) {
    if (-not $script:crystal) {
        Write-Error 'ERROR: The dragonstone.exe was not found and the Crystal compiler is unavailable. Build the project before running Dragonstone.'
        exit 1
    }

    Write-Warning 'WARNING: The dragonstone.exe is missing; running the Crystal sources directly...'
    & $script:crystal.Path 'run' $sourceEntry '--' @DragonstoneArgs
    exit $LASTEXITCODE
}

if (Test-Path -Path $exePath -PathType Leaf) {
    & $exePath @DragonstoneArgs
    exit $LASTEXITCODE
}

Write-Error 'ERROR: The dragonstone.exe could not be located or built.'
exit 1
