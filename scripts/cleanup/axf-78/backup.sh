#!/usr/bin/env bash
# AXF-78 — metadata backup of the exact components listed in destructiveChanges.xml (AC2).
# Read-only against the org: retrieves into _bmad-output/backups/axf-78/<timestamp>/.
# Usage: scripts/cleanup/axf-78/backup.sh            (target org is always AXON_DEV)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$ROOT/_bmad-output/backups/axf-78/$STAMP"
mkdir -p "$OUT"
# The destructive manifest doubles as the retrieve manifest: same members, same types.
sf project retrieve start -o AXON_DEV --manifest "$HERE/destructiveChanges.xml" --target-metadata-dir "$OUT" --unzip
sha256sum "$HERE/destructiveChanges.xml" | tee "$OUT/manifest.sha256"
echo "backup written to $OUT — recovery: sf project deploy start -o AXON_DEV --metadata-dir $OUT/unpackaged"
