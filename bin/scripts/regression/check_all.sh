#!/usr/bin/env bash
set -euo pipefail

# Always run relative to this script's folder, this
# will run check_llvm, check_c, and check_run together.
# Example:
#   `bash ./bin/scripts/regression/check_all.sh`
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$HERE/check_run.sh"
"$HERE/check_llvm.sh"
"$HERE/check_c.sh"
