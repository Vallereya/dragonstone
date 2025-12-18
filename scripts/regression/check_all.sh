#!/usr/bin/env bash
set -euo pipefail

# Always run relative to this script's folder, this
# will run check_llvm and check_run together.
# Example:
#   `bash ./scripts/regression/check_all.sh`
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$HERE/check_llvm.sh"
"$HERE/check_run.sh"
