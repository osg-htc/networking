#!/usr/bin/env bash
set -euo pipefail

# CI script: build site and detect any visible triple backticks in prepared site HTML
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
python3 scripts/check_site_for_backticks.py --build

echo "CI check: No visible triple backticks found in site HTML"