#!/usr/bin/env bash
# AXF-78 — check-only validation of the destructive manifest against AXON_DEV (AC3).
# Nothing is deleted: --dry-run / validate only. Execution requires Michel's written authorization.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
sf project deploy validate -o AXON_DEV --manifest "$HERE/package.xml" \
  --post-destructive-changes "$HERE/destructiveChanges.xml" --test-level RunLocalTests --wait 60
