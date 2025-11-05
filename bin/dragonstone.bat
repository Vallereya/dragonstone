@REM This adds to local path and then handoff to .ps1 got the idea from the Crystal source.
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "ABS_DIR=%%~fI"
if not "%ABS_DIR:~-1%"=="\" set "ABS_DIR=%ABS_DIR%\"

@REM Persistently add the bin directory to the user's PATH so contributors only need to run this once.
powershell.exe -NoProfile -Command ^
    "$target='%ABS_DIR%';" ^
    "$userPath=[Environment]::GetEnvironmentVariable('PATH','User');" ^
    "$segments=if ([string]::IsNullOrWhiteSpace($userPath)) { @() } else { $userPath -split ';' };" ^
    "if (-not ($segments -contains $target)) {" ^
    "  $newPath=(@($segments) + $target) -join ';';" ^
    "  [Environment]::SetEnvironmentVariable('PATH',$newPath,'User');" ^
    "  Write-Host \"Added $target to user PATH. Restart your shell to pick it up.\";" ^
    "}"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ABS_DIR%dragonstone.ps1" --% %*
endlocal & exit /b %ERRORLEVEL%
