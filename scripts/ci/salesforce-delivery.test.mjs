import test from "node:test";
import assert from "node:assert/strict";
import {
  sourcePaths,
  completed,
  safeResult,
  extractDeclaredTests,
  testPlan,
  run
} from "./salesforce-delivery.mjs";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

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

test("extractDeclaredTests reads bullets under the PR test classes section only", () => {
  assert.deepEqual(
    extractDeclaredTests(
      [
        "Some description.",
        "",
        "## Salesforce test classes",
        "- FooTest",
        "- `BarTest`",
        "* BazTest",
        "",
        "## Another section",
        "- NotATest"
      ].join("\n")
    ),
    ["FooTest", "BarTest", "BazTest"]
  );
  assert.deepEqual(extractDeclaredTests(""), []);
  assert.deepEqual(extractDeclaredTests("No section here"), []);
});

test("testPlan scopes to delta test classes and declared tests, deduplicated", () => {
  const files = {
    "force-app/main/default/classes/FooTest.cls": "@isTest\nclass FooTest {}",
    "force-app/main/default/classes/Foo.cls": "public class Foo {}"
  };
  const plan = testPlan(Object.keys(files), (p) => files[p], [
    "FooTest",
    "ExtraTest"
  ]);
  assert.equal(plan.testLevel, "RunSpecifiedTests");
  assert.deepEqual(new Set(plan.tests), new Set(["FooTest", "ExtraTest"]));
});

test("testPlan falls back to RunLocalTests when no Apex/trigger is in the delta", () => {
  const plan = testPlan(
    ["force-app/main/default/objects/A__c/fields/B__c.field-meta.xml"],
    () => "",
    []
  );
  assert.deepEqual(plan, { testLevel: "RunLocalTests", tests: [] });
});

test("testPlan fails closed when production Apex has no test coverage in scope", () => {
  const files = {
    "force-app/main/default/classes/Foo.cls": "public class Foo {}"
  };
  assert.throws(
    () => testPlan(Object.keys(files), (p) => files[p], []),
    /Salesforce test classes/
  );
  assert.throws(
    () =>
      testPlan(["force-app/main/default/triggers/Bar.trigger"], () => "", []),
    /Salesforce test classes/
  );
});

test("invalid environment is rejected and failure evidence is written", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "axon-delivery-test-"));
  const previous = { ...process.env };
  const previousExit = process.exitCode;
  try {
    process.env.EVIDENCE_DIR = dir;
    process.env.TARGET_ENV = "STAGING";
    process.env.OPERATION = "deploy";
    await run();
    const report = JSON.parse(fs.readFileSync(path.join(dir, "result.json")));
    assert.equal(report.outcome, "Failed");
    assert.match(report.error, /Only DEV\/UAT\/PROD/);
    assert.equal(process.exitCode, 1);
  } finally {
    process.env = previous;
    process.exitCode = previousExit;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("DEV environment enforces develop branch matching", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "axon-delivery-test-"));
  const previous = { ...process.env };
  const previousExit = process.exitCode;
  try {
    process.env.EVIDENCE_DIR = dir;
    process.env.TARGET_ENV = "DEV";
    process.env.TARGET_BRANCH = "main";
    process.env.OPERATION = "validate";
    await run();
    const report = JSON.parse(fs.readFileSync(path.join(dir, "result.json")));
    assert.equal(report.outcome, "Failed");
    assert.match(report.error, /Branch\/environment mismatch/);
    assert.equal(process.exitCode, 1);
  } finally {
    process.env = previous;
    process.exitCode = previousExit;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("UAT environment rejects develop branch", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "axon-delivery-test-"));
  const previous = { ...process.env };
  const previousExit = process.exitCode;
  try {
    process.env.EVIDENCE_DIR = dir;
    process.env.TARGET_ENV = "UAT";
    process.env.TARGET_BRANCH = "develop";
    process.env.OPERATION = "validate";
    await run();
    const report = JSON.parse(fs.readFileSync(path.join(dir, "result.json")));
    assert.equal(report.outcome, "Failed");
    assert.match(report.error, /Branch\/environment mismatch/);
    assert.equal(process.exitCode, 1);
  } finally {
    process.env = previous;
    process.exitCode = previousExit;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("validate fails closed without a resolvable PR base commit (from)", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "axon-delivery-test-"));
  const previous = { ...process.env };
  const previousExit = process.exitCode;
  try {
    process.env.EVIDENCE_DIR = dir;
    process.env.TARGET_ENV = "DEV";
    process.env.TARGET_BRANCH = "develop";
    process.env.OPERATION = "validate";
    delete process.env.PR_BASE_SHA;
    await run();
    const report = JSON.parse(fs.readFileSync(path.join(dir, "result.json")));
    assert.equal(report.outcome, "Failed");
    assert.match(report.error, /Could not resolve the PR base branch commit/);
    assert.equal(process.exitCode, 1);
  } finally {
    process.env = previous;
    process.exitCode = previousExit;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
