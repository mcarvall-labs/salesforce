#!/usr/bin/env bash
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
fixture="$(mktemp -d "$repo_root/.tmp-list-salesforce-tests.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
git init -q
git config user.email fixture@example.test
git config user.name fixture
mkdir -p force-app/main/default/classes force-app/main/default/triggers scripts/ci
cp "$repo_root/scripts/ci/list-salesforce-tests.sh" scripts/ci/
echo 'public class Leaf { public void run() {} }' > force-app/main/default/classes/Leaf.cls
echo 'public class Middle { Leaf value; }' > force-app/main/default/classes/Middle.cls
echo '@IsTest private class MiddleTest { static void verifies() { Middle value; } }' > force-app/main/default/classes/MiddleTest.cls
git add . && git commit -qm base
base="$(git rev-parse HEAD)"
echo 'public class Leaf { public void run() { Integer changed = 1; } }' > force-app/main/default/classes/Leaf.cls
git add . && git commit -qm change
head="$(git rev-parse HEAD)"
result="$(bash scripts/ci/list-salesforce-tests.sh "$base" "$head")"
[[ "$result" == 'MiddleTest' ]] || { echo "Expected MiddleTest, got: $result" >&2; exit 1; }
echo 'PASS transitive Apex test selection'
echo 'public class Uncovered {}' > force-app/main/default/classes/Uncovered.cls
git add . && git commit -qm uncovered
uncovered_head="$(git rev-parse HEAD)"
set +e
result="$(bash scripts/ci/list-salesforce-tests.sh "$head" "$uncovered_head" 2>&1)"
status=$?
set -e
[[ "$status" == 3 ]] || { echo "Expected uncovered Apex to fail with 3, got: $status" >&2; exit 1; }
echo 'PASS uncovered Apex fails closed'
