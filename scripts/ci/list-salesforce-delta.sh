#!/usr/bin/env bash

set -euo pipefail

if (($# != 2)); then
  echo "Usage: $0 <base-sha> <head-sha>" >&2
  exit 2
fi

base_sha="$1"
head_sha="$2"

declare -A seen=()

while IFS= read -r file; do
  [[ -n "$file" ]] || continue

  source_path="$file"

  if [[ "$file" =~ ^(force-app/.*/(aura|lwc)/[^/]+)/ ]]; then
    source_path="${BASH_REMATCH[1]}"
  elif [[ "$file" == *-meta.xml && -f "${file%-meta.xml}" ]]; then
    source_path="${file%-meta.xml}"
  fi

  if [[ -z "${seen[$source_path]+x}" ]]; then
    seen[$source_path]=1
    printf '%s\n' "$source_path"
  fi
done < <(git diff --name-only --diff-filter=ACMR "$base_sha" "$head_sha" -- force-app)
