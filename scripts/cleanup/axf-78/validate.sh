#!/usr/bin/env bash
# AXF-78 — check-only validation of the destructive manifest against AXON_DEV (AC3).
# Nothing is deleted here. Executed on 2026-09-15 (validation 0Afaj00000kQtWDCA0, deletion
# 0Afaj00000kR09VCAS) — see docs/implementation/AXF-78.md section 4. To execute again after a green
# validation: same command with `sf project deploy start` and --test-level NoTestRun.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
sf project deploy validate -o AXON_DEV --manifest "$HERE/package.xml" \
  --post-destructive-changes "$HERE/destructiveChanges.xml" --test-level RunLocalTests --wait 60
