$ErrorActionPreference = "Stop"

# Always run relative to this script's folder, this
# will run check_llvm and check_run together.
# Example:
#   `powershell .\scripts\regression\check_all.ps1`
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

& "$here\check_llvm.ps1"
& "$here\check_run.ps1"
