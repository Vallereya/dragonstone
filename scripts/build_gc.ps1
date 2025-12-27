param(
    [switch]$IfNeeded,
    [switch]$Clean,
    [switch]$Verbose
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..')
$vendorRoot = Join-Path $repoRoot 'src/dragonstone/shared/runtime/abi/std/gc/vendor'
$sourceRoot = $null

if (Test-Path -Path (Join-Path $vendorRoot 'CMakeLists.txt')) {
    $sourceRoot = $vendorRoot
} elseif (Test-Path -Path (Join-Path $vendorRoot 'lib\CMakeLists.txt')) {
    $sourceRoot = Join-Path $vendorRoot 'lib'
} else {
    throw "Boehm GC source not found. Expected CMakeLists.txt in $vendorRoot or $vendorRoot\lib"
}

if (-not (Test-Path -Path (Join-Path $sourceRoot 'CMakeLists.txt'))) {
    throw "Boehm GC source not found. Expected CMakeLists.txt in $sourceRoot"
}

$arch = $env:PROCESSOR_ARCHITECTURE
if (-not $arch) {
    $arch = 'AMD64'
}

$platform = if ($arch -match 'ARM64') { 'win-arm64' } else { 'win-x64' }
$cmakeArch = if ($platform -eq 'win-arm64') { 'ARM64' } else { 'x64' }

$outputRoot = Join-Path $repoRoot "bin/build/gc/$platform"
$buildDir = Join-Path $outputRoot 'build'
$installDir = $outputRoot

if ($IfNeeded) {
    $gcHeader = Join-Path $installDir 'include/gc.h'
    $gcLib = Join-Path $installDir 'lib/gc.lib'
    if ((Test-Path -Path $gcHeader) -and (Test-Path -Path $gcLib)) {
        return
    }
}

if ($Clean) {
    if (Test-Path -Path $buildDir) {
        Remove-Item -Recurse -Force $buildDir
    }
    if (Test-Path -Path (Join-Path $installDir 'lib')) {
        Remove-Item -Recurse -Force (Join-Path $installDir 'lib')
    }
    if (Test-Path -Path (Join-Path $installDir 'include')) {
        Remove-Item -Recurse -Force (Join-Path $installDir 'include')
    }
    $atomicOpsStubToClean = Join-Path $sourceRoot 'libatomic_ops'
    if (Test-Path -Path $atomicOpsStubToClean) {
        Remove-Item -Recurse -Force $atomicOpsStubToClean
    }
}

$junctionTargets = @('extra', 'cord', 'include')
foreach ($dir in $junctionTargets) {
    $localPath = Join-Path $sourceRoot $dir
    $vendorPath = Join-Path $vendorRoot $dir
    if (-not (Test-Path -Path $localPath) -and (Test-Path -Path $vendorPath)) {
        try {
            New-Item -ItemType Junction -Path $localPath -Target $vendorPath | Out-Null
        } catch {
            $cmd = "mklink /J `"$localPath`" `"$vendorPath`""
            cmd.exe /c $cmd | Out-Null
        }
    }
}

$atomicOpsStub = Join-Path $sourceRoot 'libatomic_ops\src'
if (-not (Test-Path -Path $atomicOpsStub)) {
    New-Item -ItemType Directory -Force -Path $atomicOpsStub | Out-Null
    $stubHeader = Join-Path $atomicOpsStub 'atomic_ops.h'
    @'
#ifndef AO_ATOMIC_OPS_H
#define AO_ATOMIC_OPS_H

#if defined(_MSC_VER) || defined(__MINGW32__)
  #include <intrin.h>
  #include <windows.h>

  #ifdef _WIN64
    typedef volatile __int64 AO_t;
  #else
    typedef volatile LONG AO_t;
  #endif
  typedef unsigned char AO_TS_t;

  #define AO_TS_CLEAR 0
  #define AO_TS_SET 1
  #define AO_TS_INITIALIZER AO_TS_CLEAR

  #define AO_compiler_barrier() _ReadWriteBarrier()

  #define AO_HAVE_nop_full
  static inline void AO_nop_full(void) {
    MemoryBarrier();
  }

  #define AO_HAVE_load
  static inline AO_t AO_load(const volatile AO_t *addr) {
    return *addr;
  }

  #define AO_HAVE_store
  static inline void AO_store(volatile AO_t *addr, AO_t val) {
    *addr = val;
  }

  #define AO_HAVE_test_and_set_full
  static inline AO_TS_t AO_test_and_set_full(volatile AO_TS_t *addr) {
    return (AO_TS_t)_InterlockedExchange8((char*)addr, AO_TS_SET);
  }

  #define AO_HAVE_fetch_and_add
  static inline AO_t AO_fetch_and_add(volatile AO_t *addr, AO_t incr) {
    #ifdef _WIN64
      return _InterlockedExchangeAdd64((__int64*)addr, incr);
    #else
      return _InterlockedExchangeAdd((LONG*)addr, incr);
    #endif
  }

  #define AO_HAVE_fetch_and_add1
  static inline AO_t AO_fetch_and_add1(volatile AO_t *addr) {
    #ifdef _WIN64
      return _InterlockedIncrement64((__int64*)addr) - 1;
    #else
      return _InterlockedIncrement((LONG*)addr) - 1;
    #endif
  }

  #define AO_HAVE_compare_and_swap
  static inline int AO_compare_and_swap(volatile AO_t *addr, AO_t old_val, AO_t new_val) {
    #ifdef _WIN64
      return _InterlockedCompareExchange64((__int64*)addr, new_val, old_val) == old_val;
    #else
      return _InterlockedCompareExchange((LONG*)addr, new_val, old_val) == old_val;
    #endif
  }

  #define AO_HAVE_or
  static inline void AO_or(volatile AO_t *addr, AO_t val) {
    #ifdef _WIN64
      _InterlockedOr64((__int64*)addr, val);
    #else
      _InterlockedOr((LONG*)addr, val);
    #endif
  }

  #define AO_HAVE_load_acquire
  static inline AO_t AO_load_acquire(const volatile AO_t *addr) {
    AO_t result = *addr;
    MemoryBarrier();
    return result;
  }

  #define AO_HAVE_store_release
  static inline void AO_store_release(volatile AO_t *addr, AO_t val) {
    MemoryBarrier();
    *addr = val;
  }

  #define AO_HAVE_char_load
  static inline unsigned char AO_char_load(const volatile unsigned char *addr) {
    return *addr;
  }

  #define AO_HAVE_char_store
  static inline void AO_char_store(volatile unsigned char *addr, unsigned char val) {
    *addr = val;
  }
#endif

#endif
'@ | Out-File -FilePath $stubHeader -Encoding ASCII
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$cmakeArgs = @(
    '-S', $sourceRoot,
    '-B', $buildDir,
    '-G', 'Visual Studio 17 2022',
    '-A', $cmakeArch,
    '-DBUILD_SHARED_LIBS=OFF',
    '-Denable_threads=ON',
    '-Denable_cplusplus=OFF',
    '-Denable_docs=OFF',
    "-DCMAKE_INSTALL_PREFIX=$installDir"
)

if ($Verbose) {
    Write-Host "Configuring Boehm GC: cmake $($cmakeArgs -join ' ')"
}
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    throw "CMake configure failed with exit code $LASTEXITCODE."
}

if ($Verbose) {
    Write-Host "Building Boehm GC in $buildDir"
}
& cmake --build $buildDir --config Release --target install
if ($LASTEXITCODE -ne 0) {
    throw "CMake build failed with exit code $LASTEXITCODE."
}

$installInclude = Join-Path $installDir 'include'
$installLib = Join-Path $installDir 'lib'
New-Item -ItemType Directory -Force -Path $installInclude | Out-Null
New-Item -ItemType Directory -Force -Path $installLib | Out-Null

if (-not (Test-Path -Path (Join-Path $installInclude 'gc.h'))) {
    $vendorInclude = Join-Path $vendorRoot 'include'
    if (Test-Path -Path $vendorInclude) {
        Copy-Item -Path (Join-Path $vendorInclude '*') -Destination $installInclude -Recurse -Force
    }
}

if (-not (Test-Path -Path (Join-Path $installLib 'gc.lib'))) {
    $libCandidate = Get-ChildItem -Path $buildDir -Filter 'gc.lib' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($libCandidate) {
        Copy-Item -Path $libCandidate.FullName -Destination (Join-Path $installLib 'gc.lib') -Force
    }
}

if ($Verbose) {
    Write-Host "Boehm GC installed to $installDir"
}
