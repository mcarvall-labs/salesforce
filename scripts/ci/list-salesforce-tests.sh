#!/usr/bin/env bash

set -euo pipefail

if (($# != 2)); then
  echo "Usage: $0 <base-sha> <head-sha>" >&2
  exit 2
fi

base_sha="$1"
head_sha="$2"
declare -A tests=()
declare -A impacted=()
apex_changed=false

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  apex_changed=true

  name="${file##*/}"
  name="${name%.cls}"
  name="${name%.trigger}"

  if [[ "$file" == *Test.cls ]]; then
    tests["$name"]=1
  else
    impacted["$name"]=1
  fi
done < <(
  git diff --name-only --diff-filter=ACMRD "$base_sha" "$head_sha" -- \
    'force-app/main/default/classes/*.cls' \
    'force-app/main/default/triggers/*.trigger'
)

if [[ "$apex_changed" == false ]]; then
  exit 0
fi

changed=true
while [[ "$changed" == true ]]; do
  changed=false
  while IFS= read -r production_file; do
    [[ -n "$production_file" && "$production_file" != *Test.cls ]] || continue
    production_file="${production_file//\\//}"
    production_name="${production_file##*/}"
    production_name="${production_name%.cls}"
    production_name="${production_name%.trigger}"
    [[ -z "${impacted[$production_name]+x}" ]] || continue
    for symbol in "${!impacted[@]}"; do
      if rg -q --fixed-strings "$symbol" "$production_file"; then
        impacted["$production_name"]=1
        changed=true
        break
      fi
    done
  done < <(rg --files force-app/main/default/classes force-app/main/default/triggers 2>/dev/null | rg '\.(cls|trigger)$' || true)
done

while IFS= read -r test_file; do
  [[ -n "$test_file" ]] || continue
  test_file="${test_file//\\//}"
  for symbol in "${!impacted[@]}"; do
    if rg -q --fixed-strings "$symbol" "$test_file"; then
      test_name="${test_file##*/}"
      tests["${test_name%.cls}"]=1
      break
    fi
  done
done < <(rg --files force-app/main/default/classes | rg 'Test\.cls$' || true)

if ((${#tests[@]} == 0)); then
  echo "Apex changed, but no related Apex test was found in the transitive production impact." >&2
  echo "Add or update a *Test.cls that references an impacted class, trigger, or handler." >&2
  exit 3
fi

printf '%s\n' "${!tests[@]}" | sort
