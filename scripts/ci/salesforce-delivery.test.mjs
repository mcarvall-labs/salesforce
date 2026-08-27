import test from "node:test";
import assert from "node:assert/strict";
import {
  sourcePaths,
  completed,
  selectBaseline,
  safeResult,
  run
} from "./salesforce-delivery.mjs";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

test("baseline skips failures/current reruns and chooses highest successful run number", () => {
  const sha = "a".repeat(40);
  const initial = "b".repeat(40);
  const runs = [
    { id: 1, run_number: 1, conclusion: "success", head_sha: initial },
    { id: 2, run_number: 2, conclusion: "success", head_sha: sha },
    { id: 3, run_number: 3, conclusion: "failure", head_sha: "c".repeat(40) },
    { id: 4, run_number: 4, conclusion: "success", head_sha: "d".repeat(40) }
  ];
  assert.equal(selectBaseline(runs, "4", initial), sha);
  assert.equal(selectBaseline([], "4", initial), initial);
  assert.throws(() => selectBaseline([], "4", undefined), /verified initial/);
  assert.throws(() => selectBaseline([], "4", "main"), /verified initial/);
});

test("delta deduplicates whole Lightning bundles and preserves decomposed fields", () => {
  assert.deepEqual(
    sourcePaths([
      { status: "M", file: "force-app/main/default/lwc/example/example.js" },
      { status: "A", file: "force-app/main/default/lwc/example/example.html" },
      {
        status: "M",
        file: "force-app/main/default/objects/A__c/fields/B__c.field-meta.xml"
      }
    ]),
    [
      "force-app/main/default/lwc/example",
      "force-app/main/default/objects/A__c/fields/B__c.field-meta.xml"
    ]
  );
});

test("deletions and renames represented as delete/add cannot silently advance baseline", () => {
  assert.throws(
    () =>
      sourcePaths([
        { status: "D", file: "force-app/main/default/classes/Old.cls" }
      ]),
    /destructive/
  );
  assert.throws(
    () => sourcePaths([{ status: "M", file: "scripts/test.sh" }]),
    /Invalid/
  );
});

test("only a successful terminal Salesforce result counts as success", () => {
  const p = {
    status: 0,
    result: { done: true, success: true, status: "Succeeded" }
  };
  assert.equal(completed(p, 0), true);
  for (const status of [
    "Pending",
    "InProgress",
    "Failed",
    "SucceededPartial"
  ]) {
    assert.equal(
      completed({ ...p, result: { ...p.result, status } }, 0),
      false
    );
  }
  assert.equal(completed(p, 1), false);
  assert.equal(completed({ status: 0, result: { success: true } }, 0), false);
});

test("evidence allowlist excludes authentication data and normalizes singleton failures", () => {
  const evidence = safeResult({
    accessToken: "secret",
    result: {
      id: "0Af123",
      accessToken: "secret",
      details: {
        componentFailures: { fullName: "A", problem: "force://secret" },
        runTestResult: {
          failures: { name: "A", methodName: "test", message: "Bearer secret" }
        }
      }
    }
  });
  assert.equal(evidence.componentFailures.length, 1);
  assert.equal(evidence.testFailures.length, 1);
  assert.doesNotMatch(JSON.stringify(evidence), /secret|accessToken/);
});

test("DEV is rejected before any external command and failure evidence is written", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "axon-delivery-test-"));
  const previous = { ...process.env };
  const previousExit = process.exitCode;
  try {
    process.env.EVIDENCE_DIR = dir;
    process.env.TARGET_ENV = "DEV";
    process.env.OPERATION = "deploy";
    await run();
    const report = JSON.parse(fs.readFileSync(path.join(dir, "result.json")));
    assert.equal(report.outcome, "Failed");
    assert.match(report.error, /Only UAT\/PROD/);
    assert.equal(process.exitCode, 1);
  } finally {
    process.env = previous;
    process.exitCode = previousExit;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
