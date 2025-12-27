<#
    .NOTES
        Command Usage:
            Rebuild:            `dragonstone.ps1 --rebuild`
            Clean:              `dragonstone.ps1 --clean`
            Clean and Rebuild:  `dragonstone.ps1 --clean-rebuild`
            Verbose build:      `dragonstone.ps1 <flag> --verbose`

    .SYNOPSIS
        PowerShell launcher script for Dragonstone.

    .DESCRIPTION
        This script ensures that the Dragonstone executable is built and up to date,
        then launches it with any provided arguments. It can also display environment
        variables related to Dragonstone.

    .EXAMPLE
        `dragonstone.ps1 --rebuild`
        `dragonstone.ps1 --clean`
        `dragonstone.ps1 --clean-rebuild`

        or

        dragonstone.ps1 --rebuild
        dragonstone.ps1 --clean
        dragonstone.ps1 --clean-rebuild
        
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

$script:verboseBuild = $false
$normalizedArgs = @()
foreach ($arg in $DragonstoneArgs) {
    if ($arg -eq '--verbose') {
        $script:verboseBuild = $true
        continue
    }
    $normalizedArgs += $arg
}
$DragonstoneArgs = $normalizedArgs

$scriptPath   = $PSCommandPath
$scriptRoot   = Split-Path -Parent $scriptPath
$projectRoot  = Split-Path -Parent $scriptRoot
$buildDir     = Join-Path $scriptRoot 'build'

$env:SHARDS_BIN_PATH = Join-Path $scriptRoot 'build'

if (-not (Test-Path -Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

$exePath      = Join-Path $buildDir 'dragonstone.exe'
$sourceEntry  = Join-Path $projectRoot 'bin/dragonstone'

$resourceScript = $null
$resourceOutputBase = $null

$resourceSearchRoots = @(
    (Join-Path $projectRoot 'resources'),
    (Join-Path $scriptRoot 'resources')
)

$abiSourceDir = Join-Path $projectRoot 'src/dragonstone/shared/runtime/abi'
$abiSources = @(
    (Join-Path $abiSourceDir 'abi.c'),
    (Join-Path $abiSourceDir 'std/std.c'),
    (Join-Path $abiSourceDir 'std/io/io.c'),
    (Join-Path $abiSourceDir 'std/file/file.c'),
    (Join-Path $abiSourceDir 'std/path/path.c'),
    (Join-Path $abiSourceDir 'std/value/value.c'),
    (Join-Path $abiSourceDir 'std/gc/gc.c'),
    (Join-Path $abiSourceDir 'platform/platform.c'),
    (Join-Path $abiSourceDir 'platform/lib_c/lib_c.c')
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

# Cleans up Dragonstone build artifacts, including the build directory,
# compiled resource files, and the version header file.
function Clean-DragonstoneArtifacts {
    Write-Host "Cleaning build..........."
    
    $itemsToClean = @(
        @{
            Path = (Join-Path $scriptRoot 'build')
            Type = 'Directory'
            Description = 'build directory'
        },
        @{
            Path = (Join-Path $scriptRoot 'resources/dragonstone.o')
            Type = 'File'
            Description = 'dragonstone.o'
        },
        @{
            Path = (Join-Path $scriptRoot 'resources/dragonstone.res')
            Type = 'File'
            Description = 'dragonstone.res'
        },
        @{
            Path = (Join-Path $projectRoot 'src/dragonstone/core/runtime/include/dragonstone/core/version.h')
            Type = 'File'
            Description = 'version.h'
        },
        @{
            Path = (Join-Path $projectRoot 'src/dragonstone/shared/runtime/abi/std/gc/vendor/lib/cord')
            Type = 'Directory'
            Description = 'GC vendor/cord junction'
        },
        @{
            Path = (Join-Path $projectRoot 'src/dragonstone/shared/runtime/abi/std/gc/vendor/lib/extra')
            Type = 'Directory'
            Description = 'GC vendor/extra junction'
        },
        @{
            Path = (Join-Path $projectRoot 'src/dragonstone/shared/runtime/abi/std/gc/vendor/lib/include')
            Type = 'Directory'
            Description = 'GC vendor/include junction'
        },
        @{
            Path = (Join-Path $projectRoot 'src/dragonstone/shared/runtime/abi/std/gc/vendor/lib/libatomic_ops')
            Type = 'Directory'
            Description = 'GC vendor/libatomic_ops stub'
        }
    )
    
    $cleanedCount = 0

    foreach ($item in $itemsToClean) {
        if (Test-Path -Path $item.Path) {
            try {
                if ($item.Type -eq 'Directory') {
                    Remove-Item -Path $item.Path -Recurse -Force -ErrorAction Stop
                } else {
                    Remove-Item -Path $item.Path -Force -ErrorAction Stop
                }

                Write-Host "  Removed: $($item.Description)"

                $cleanedCount++

            } catch {
                Write-Warning "  Failed to remove build file: $($item.Description): $($_.Exception.Message)"
            }
        }
    }
    
    if ($cleanedCount -eq 0) {
        Write-Host "  No build files found to clean."
    } else {
        Write-Host "Cleaned $cleanedCount files(s)."
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
        Write-Warning "WARNING: Resource not found at: $ScriptPath"
        return $null
    }

    $tool = $null
    $toolNames = @('llvm-rc', 'x86_64-w64-mingw32-windres', 'windres')

    foreach ($name in $toolNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            $tool = $command
            break
        }
    }

    if (-not $tool) {
        Write-Warning 'WARNING: No resource compiler (windres/x86_64-w64-mingw32-windres/llvm-rc) was found; the executable will be built without the resource.'
        return $null
    }

    $extension = '.res'

    if ($tool.Name -notlike 'llvm-rc*') {
        $extension = '.o'
    }

    $outputPath = "$OutputBase$extension"

    $outputDir = Split-Path -Parent $outputPath

    if (-not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    if (Test-Path -Path $outputPath -PathType Leaf) {
        Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
    }

    $rcDir = Split-Path -Parent $ScriptPath
    $rcFileName = Split-Path -Leaf $ScriptPath
    $originalLocation = Get-Location

    Write-Host "Compiling, please wait..."
    
    try {
        Set-Location $rcDir

        if ($tool.Name -like 'llvm-rc*') {
            & $tool.Path '-fo' $outputPath $rcFileName 2>&1 | Out-Null
        } else {
            $gccPath = Get-Command 'gcc' -ErrorAction SilentlyContinue
            $oldPath = $env:PATH
            try {
                if ($gccPath) {
                    $gccDir = Split-Path -Parent $gccPath.Path
                    $env:PATH = "$gccDir;$env:PATH"
                }
                & $tool.Path $rcFileName '-O' 'coff' '-o' $outputPath 2>&1 | Out-Null
            } finally {
                $env:PATH = $oldPath
            }
        }

        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        if (-not (Test-Path -Path $outputPath -PathType Leaf)) {
            return $null
        }

        return $outputPath
    } catch {
        return $null
    } finally {
        Set-Location $originalLocation
    }
}

function Get-CCompiler {
    $candidates = @('clang', 'gcc', 'cc')
    foreach ($name in $candidates) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Path
        }
    }
    return $null
}

function Get-ArchiveTool {
    $candidates = @('llvm-lib', 'lib')
    foreach ($name in $candidates) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Path
        }
    }
    return $null
}

function Get-GcPlatformId {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -and $arch -match 'ARM64') {
        return 'win-arm64'
    }
    return 'win-x64'
}

function Test-GcLibDir {
    param([string] $GcLibDir)

    if (-not $GcLibDir) {
        return $false
    }

    $candidates = @('gc.lib', 'libgc.a', 'libgc.lib')
    foreach ($candidate in $candidates) {
        if (Test-Path -Path (Join-Path $GcLibDir $candidate)) {
            return $true
        }
    }

    return $false
}

function Get-GcIncludeDir {
    $gcPlatform = Get-GcPlatformId
    $gcBuildRoot = Join-Path $buildDir 'gc'
    $gcBuildInclude = Join-Path (Join-Path $gcBuildRoot $gcPlatform) 'include'
    if ((Test-Path -Path (Join-Path $gcBuildInclude 'gc.h')) -and (Test-GcLibDir (Join-Path (Join-Path $gcBuildRoot $gcPlatform) 'lib'))) {
        return $gcBuildInclude
    }

    $vendorRoot = Join-Path $projectRoot 'src/dragonstone/shared/runtime/abi/std/gc/vendor'
    $vendorCandidates = @(
        $vendorRoot,
        (Join-Path $vendorRoot 'include')
    )
    $vendorLibCandidates = @(
        (Join-Path $vendorRoot 'lib'),
        (Join-Path $vendorRoot 'lib\win-x64')
    )
    foreach ($candidate in $vendorCandidates) {
        $hasLib = $false
        foreach ($libCandidate in $vendorLibCandidates) {
            if (Test-GcLibDir $libCandidate) {
                $hasLib = $true
                break
            }
        }
        if ($hasLib -and (Test-Path -Path (Join-Path $candidate 'gc.h'))) {
            return $candidate
        }
    }

    if ($env:DRAGONSTONE_GC_INCLUDE) {
        $candidate = $env:DRAGONSTONE_GC_INCLUDE
        if (Test-Path -Path (Join-Path $candidate 'gc.h')) {
            return $candidate
        }
    }

    if ($env:GC_INCLUDE) {
        $candidate = $env:GC_INCLUDE
        if (Test-Path -Path (Join-Path $candidate 'gc.h')) {
            return $candidate
        }
    }

    if ($script:crystal) {
        $crystalBin = Split-Path -Parent $script:crystal.Path
        $crystalRoot = Split-Path -Parent $crystalBin
        $candidates = @(
            (Join-Path $crystalRoot 'include'),
            (Join-Path $crystalRoot 'lib\gc\include'),
            (Join-Path $crystalRoot 'lib\gc\include\gc'),
            (Join-Path $crystalRoot 'lib\gc')
        )
        foreach ($candidate in $candidates) {
            if (Test-Path -Path (Join-Path $candidate 'gc.h')) {
                return $candidate
            }
        }
    }

    return $null
}

function Get-GcLibDir {
    $gcPlatform = Get-GcPlatformId
    $gcBuildRoot = Join-Path $buildDir 'gc'
    $gcBuildLib = Join-Path (Join-Path $gcBuildRoot $gcPlatform) 'lib'
    if (Test-GcLibDir $gcBuildLib) {
        return $gcBuildLib
    }

    $vendorRoot = Join-Path $projectRoot 'src/dragonstone/shared/runtime/abi/std/gc/vendor'
    $vendorCandidates = @(
        (Join-Path $vendorRoot 'lib'),
        (Join-Path $vendorRoot 'lib\win-x64')
    )
    foreach ($candidate in $vendorCandidates) {
        if (Test-GcLibDir $candidate) {
            return $candidate
        }
    }

    if ($env:DRAGONSTONE_GC_LIB) {
        if (Test-GcLibDir $env:DRAGONSTONE_GC_LIB) {
            return $env:DRAGONSTONE_GC_LIB
        }
    }

    if ($env:GC_LIB) {
        if (Test-GcLibDir $env:GC_LIB) {
            return $env:GC_LIB
        }
    }

    return $null
}

function Get-GcLibName {
    param([string] $GcLibDir)

    $candidates = @('gc.lib', 'libgc.a', 'libgc.lib')
    foreach ($candidate in $candidates) {
        if (Test-Path -Path (Join-Path $GcLibDir $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Ensure-GcBuild {
    param([switch] $Verbose)

    $gcPlatform = Get-GcPlatformId
    $gcOutputRoot = Join-Path $buildDir "gc\$gcPlatform"
    $gcInclude = Join-Path $gcOutputRoot 'include\gc.h'
    $gcLibDir = Join-Path $gcOutputRoot 'lib'

    if ((Test-Path -Path $gcInclude) -and (Test-GcLibDir $gcLibDir)) {
        return
    }

    $vendorSource = Join-Path $projectRoot 'src/dragonstone/shared/runtime/abi/std/gc/vendor/lib/CMakeLists.txt'
    if (-not (Test-Path -Path $vendorSource)) {
        return
    }

    $buildScript = Join-Path $projectRoot 'scripts/build_gc.ps1'
    if (-not (Test-Path -Path $buildScript)) {
        return
    }

    $gcArgs = @('-IfNeeded')
    if ($Verbose) {
        $gcArgs += '-Verbose'
    }

    if ($script:verboseBuild) {
        Write-Host "Building Boehm GC: $buildScript $($gcArgs -join ' ')"
    }
    & $buildScript @gcArgs
}

function Build-DragonstoneAbi {
    param([string] $OutputDir)

    $compiler = Get-CCompiler
    if (-not $compiler) {
        Write-Host "ERROR: C compiler not found" -ForegroundColor Red
        Write-Host "A C compiler is needed to build the ABI library" -ForegroundColor Yellow
        throw [System.Exception]::new("C compiler not found")
    }

    $archiver = Get-ArchiveTool
    if (-not $archiver) {
        Write-Host "ERROR: Archive tool not found" -ForegroundColor Red
        Write-Host "llvm-lib or lib.exe is needed to build the ABI library" -ForegroundColor Yellow
        throw [System.Exception]::new("Archive tool not found")
    }

    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    $gcIncludeDir = Get-GcIncludeDir

    $objects = @()

    foreach ($src in $abiSources) {
        if (-not (Test-Path -Path $src -PathType Leaf)) {
            continue
        }

        $relative = $src.Substring($abiSourceDir.Length).TrimStart('\', '/')
        $objName = ($relative -replace '[\\/]', '_') -replace '\.c$', '.obj'
        $objPath = Join-Path $OutputDir $objName

        $needsBuild = -not (Test-Path -Path $objPath -PathType Leaf)
        if (-not $needsBuild) {
            $srcTime = (Get-Item $src).LastWriteTimeUtc
            $objTime = (Get-Item $objPath).LastWriteTimeUtc
            if ($srcTime -gt $objTime) {
                $needsBuild = $true
            }
        }

        if ($needsBuild) {
            $compileArgs = @('-std=c11', '-O2', '-c')
            if ($src -like '*\std\gc\gc.c') {
                if (-not $gcIncludeDir) {
                    Write-Host "ERROR: Boehm GC headers not found" -ForegroundColor Red
                    Write-Host "Please set DRAGONSTONE_GC_INCLUDE to the folder containing gc.h" -ForegroundColor Yellow
                    throw [System.Exception]::new("GC headers not found")
                }
                $compileArgs += "-I$gcIncludeDir"
                if ($script:verboseBuild) {
                    Write-Host "GC include dir: $gcIncludeDir"
                }
            } elseif ($gcIncludeDir) {
                $compileArgs += "-I$gcIncludeDir"
            }
            $compileArgs += @($src, '-o', $objPath)
            if ($script:verboseBuild) {
                $compileArgs = @('-v') + $compileArgs
                Write-Host "ABI compile: $compiler $($compileArgs -join ' ')"
            }

            & $compiler @compileArgs 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: Failed to compile ABI source: $(Split-Path -Leaf $src)" -ForegroundColor Red
                throw [System.Exception]::new("Compilation failed")
            }
        }

        $objects += $objPath
    }

    $libPath = Join-Path $buildDir 'dragonstone_abi.lib'
    $needsArchive = -not (Test-Path -Path $libPath -PathType Leaf)

    if (-not $needsArchive) {
        foreach ($obj in $objects) {
            $objTime = (Get-Item $obj).LastWriteTimeUtc
            $libTime = (Get-Item $libPath).LastWriteTimeUtc
            if ($objTime -gt $libTime) {
                $needsArchive = $true
                break
            }
        }
    }

    if ($needsArchive) {
        $archiveArgs = @("/OUT:$libPath") + $objects
        if ($script:verboseBuild) {
            $archiveArgs = @('/VERBOSE') + $archiveArgs
            Write-Host "ABI archive: $archiver $($archiveArgs -join ' ')"
        }
        $output = & $archiver @archiveArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($script:verboseBuild) {
                Write-Host $output
            }
            throw "ERROR: Failed to archive ABI library at $libPath"
        }
    }

    return $libPath
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

    Write-Host 'Building Dragonstone.....'

    $resourcePath = $null

    if ($resourceScript) {
        try {
            $resourcePath = CompileDragonstoneResource -ScriptPath $resourceScript -OutputBase $resourceOutputBase
        } catch {
            if ($Force) {
                throw
            }
            # Resource compilation failed but continue without it
        }
    }

    $envFlagSet = $false
    $resourceLinkArg = $null
    $abiLibPath = $null

    $abiOutputDir = Join-Path $buildDir 'abi'
    Ensure-GcBuild -Verbose:$script:verboseBuild

    try {
        $abiLibPath = Build-DragonstoneAbi -OutputDir $abiOutputDir
    } catch {
        if (-not $Force) {
            throw
        }
        $abiLibPath = $null
    }

    if ($resourcePath) {
        $resourceLinkArg = $resourcePath
        $resourceLinkArg = $resourceLinkArg -replace '\\','/'
        $env:CRFLAGS = "--link-flags `"$resourceLinkArg`""
        $envFlagSet = $true
    }

    try {
        $linkFlags = @()
        if ($resourceLinkArg) {
            $linkFlags += $resourceLinkArg
        }
        if ($abiLibPath) {
            $linkFlags += "/LIBPATH:$buildDir"
        }
        $gcLibDir = Get-GcLibDir
        if ($gcLibDir) {
            $linkFlags += "/LIBPATH:$gcLibDir"
            $gcLibName = Get-GcLibName -GcLibDir $gcLibDir
            if ($gcLibName) {
                $linkFlags += $gcLibName
            }
            if ($script:verboseBuild) {
                Write-Host "GC lib dir: $gcLibDir"
            }
        }
        if ($script:verboseBuild) {
            $linkFlags += "/VERBOSE"
        }

        if ($linkFlags.Count -gt 0 -and $script:crystal) {
            $linkFlagsArg = ($linkFlags | ForEach-Object { $_ -replace '\\','/' }) -join ' '
            $buildArgs = @('build', $sourceEntry, '-o', $exePath, '--release', '--link-flags', $linkFlagsArg)
            if ($script:verboseBuild) {
                $buildArgs += '--verbose'
                Write-Host "Building with crystal: $($script:crystal.Path) $($buildArgs -join ' ')"
            }
            & $script:crystal.Path @buildArgs
        } else {
            $buildArgs = @('build', $sourceEntry, '-o', $exePath, '--release')
            if ($script:verboseBuild) {
                $buildArgs += '--verbose'
                Write-Host "Building with crystal: $($script:crystal.Path) $($buildArgs -join ' ')"
            }
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
    
    # Handles the `--clean` flag.
    if ($firstArg -eq '--clean') {
        Clean-DragonstoneArtifacts
        exit 0
    }

    # Handles the `--clean-rebuild` flag.
    if ($firstArg -eq '--clean-rebuild') {
        Clean-DragonstoneArtifacts

        if (-not (Test-Path -Path $buildDir)) {
            New-Item -ItemType Directory -Path $buildDir | Out-Null
        }

        $forceRebuild = $true

        if ($argCount -gt 1) {
            $DragonstoneArgs = $DragonstoneArgs[1..($argCount - 1)]
        } else {
            [string[]]$DragonstoneArgs = @()
        }
    }
    
    # Handles the `--rebuild-exe` flag.
    if ($firstArg -eq '--rebuild') {
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
    Write-Host "ERROR: Build failed." -ForegroundColor Red
    try {
        Write-Host $_.Exception.Message -ForegroundColor Red
    } catch {
        # Ignore errors in error reporting
    }
    exit 1
}

if (-not $buildEnsured -and -not (Test-Path -Path $exePath -PathType Leaf)) {
    if (-not $script:crystal) {
        Write-Host 'ERROR: The dragonstone.exe was not found. The Crystal compiler is also unavailable. Build the project before running Dragonstone.' -ForegroundColor Red
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
