#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"${PYTHON:-python3}" "$ROOT/tests/test_upstream_sync.py"
