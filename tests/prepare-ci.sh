#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/prepare_ci_lib.sh"

bash "$script_dir/test_prepare_ci.sh"
prepare_ci .
"${CHECK_ENGINE:-terraform}" fmt -check -recursive -diff
