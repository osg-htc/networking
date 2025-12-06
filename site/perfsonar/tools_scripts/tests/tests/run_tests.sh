#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR" || exit 1

echo "Running perfSONAR helper tests..."

bash tests/test_validate.sh
bash tests/test_sanitize.sh

echo "All tests completed."
