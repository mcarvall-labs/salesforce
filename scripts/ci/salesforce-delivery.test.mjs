import test from "node:test";
import assert from "node:assert/strict";
import {
  sourcePaths,
  completed,
  safeResult,
  extractDeclaredTests,
  testPlan,
  isPermissionSetOrGroupOnly,
  destructiveMember,
  buildDestructiveChangesXml,
  destructiveManifestArgs,
  pendingPermissionSetGroups,
  waitForPermissionSetGroupsUpdated,
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

test("sourcePaths excludes deletions (handled separately as destructive changes)", () => {
  assert.deepEqual(
    sourcePaths([
      { status: "D", file: "force-app/main/default/classes/Old.cls" },
      { status: "M", file: "force-app/main/default/classes/Kept.cls" }
    ]),
    ["force-app/main/default/classes/Kept.cls"]
  );
  assert.throws(
    () => sourcePaths([{ status: "M", file: "scripts/test.sh" }]),
    /Invalid/
  );
});

test("destructiveMember resolves standalone metadata types from their deleted path", () => {
  assert.deepEqual(
    destructiveMember("force-app/main/default/classes/Foo.cls"),
    { type: "ApexClass", member: "Foo" }
  );
  assert.deepEqual(
    destructiveMember("force-app/main/default/classes/Foo.cls-meta.xml"),
    { type: "ApexClass", member: "Foo" }
  );
  assert.deepEqual(
    destructiveMember("force-app/main/default/triggers/Bar.trigger"),
    { type: "ApexTrigger", member: "Bar" }
  );
  assert.deepEqual(
    destructiveMember(
      "force-app/main/default/permissionsets/AXF_PS_Foo.permissionset-meta.xml"
    ),
    { type: "PermissionSet", member: "AXF_PS_Foo" }
  );
  assert.deepEqual(
    destructiveMember(
      "force-app/main/default/layouts/Account-Account Layout.layout-meta.xml"
    ),
    { type: "Layout", member: "Account-Account Layout" }
  );
});

test("destructiveMember resolves whole objects and nested object children", () => {
  assert.deepEqual(
    destructiveMember(
      "force-app/main/default/objects/Foo__c/Foo__c.object-meta.xml"
    ),
    { type: "CustomObject", member: "Foo__c" }
  );
  assert.deepEqual(
    destructiveMember(
      "force-app/main/default/objects/Foo__c/fields/Bar__c.field-meta.xml"
    ),
    { type: "CustomField", member: "Foo__c.Bar__c" }
  );
  assert.deepEqual(
    destructiveMember(
      "force-app/main/default/objects/Foo__c/validationRules/VR1.validationRule-meta.xml"
    ),
    { type: "ValidationRule", member: "Foo__c.VR1" }
  );
});

test("destructiveMember leaves LWC/Aura bundles and unknown paths unresolved", () => {
  assert.equal(
    destructiveMember("force-app/main/default/lwc/foo/foo.js"),
    null
  );
  assert.equal(destructiveMember("scripts/ci/foo.mjs"), null);
  assert.equal(
    destructiveMember("force-app/main/default/unknownFolder/Foo.xml"),
    null
  );
});

test("buildDestructiveChangesXml groups by type, sorts, escapes, and reports unresolved paths", () => {
  const { xml, unresolved } = buildDestructiveChangesXml([
    "force-app/main/default/classes/Zeta.cls",
    "force-app/main/default/classes/Alpha.cls",
    "force-app/main/default/objects/Foo__c/fields/Bar__c.field-meta.xml",
    "force-app/main/default/lwc/foo/foo.js"
  ]);
  assert.deepEqual(unresolved, ["force-app/main/default/lwc/foo/foo.js"]);
  assert.match(xml, /<name>ApexClass<\/name>/);
  assert.match(xml, /<name>CustomField<\/name>/);
  assert.match(xml, /<members>Alpha<\/members>\s*<members>Zeta<\/members>/);
  assert.match(xml, /<members>Foo__c\.Bar__c<\/members>/);
  assert.match(xml, /<version>62\.0<\/version>/);
});

test("destructiveManifestArgs only applies manifests that exist and have <types> content", () => {
  const files = {
    "manifest/destructiveChangesPre.xml":
      "<Package><version>62.0</version></Package>",
    "manifest/destructiveChangesPost.xml":
      "<Package><types><members>Foo</members><name>ApexClass</name></types><version>62.0</version></Package>"
  };
  const exists = (p) => p in files;
  const readFile = (p) => files[p];
  assert.deepEqual(destructiveManifestArgs(exists, readFile), {
    args: ["--post-destructive-changes", "manifest/destructiveChangesPost.xml"],
    applied: ["manifest/destructiveChangesPost.xml"]
  });
});

test("destructiveManifestArgs is a no-op when no manifest file exists", () => {
  assert.deepEqual(
    destructiveManifestArgs(
      () => false,
      () => ""
    ),
    {
      args: [],
      applied: []
    }
  );
});

test("pendingPermissionSetGroups extracts and sorts non-Updated groups from a Tooling API query payload", () => {
  assert.deepEqual(
    pendingPermissionSetGroups({
      result: {
        records: [
          { DeveloperName: "AXF_PSG_Second", Status: "Updating" },
          { DeveloperName: "AXF_PSG_First", Status: "Error" }
        ]
      }
    }),
    ["AXF_PSG_First (Error)", "AXF_PSG_Second (Updating)"]
  );
});

test("pendingPermissionSetGroups returns nothing for an empty or missing query result", () => {
  assert.deepEqual(pendingPermissionSetGroups({}), []);
  assert.deepEqual(pendingPermissionSetGroups({ result: { records: [] } }), []);
});

test("waitForPermissionSetGroupsUpdated polls until settled, without sleeping past the last poll", async () => {
  let calls = 0;
  const sleeps = [];
  const result = await waitForPermissionSetGroupsUpdated({
    queryOnce: () => (++calls < 3 ? ["AXF_PSG_Test (Updating)"] : []),
    sleep: async (ms) => {
      sleeps.push(ms);
    },
    log: () => {},
    intervalMs: 10
  });
  assert.deepEqual(result, { settled: true, pending: [] });
  assert.equal(calls, 3);
  assert.deepEqual(sleeps, [10, 10]);
});

test("waitForPermissionSetGroupsUpdated gives up after the timeout and reports what is still pending", async () => {
  let now = 0;
  const realNow = Date.now;
  Date.now = () => now;
  try {
    const result = await waitForPermissionSetGroupsUpdated({
      queryOnce: () => ["AXF_PSG_Stuck (Error)"],
      sleep: async () => {
        now += 20;
      },
      log: () => {},
      timeoutMs: 30,
      intervalMs: 20
    });
    assert.equal(result.settled, false);
    assert.deepEqual(result.pending, ["AXF_PSG_Stuck (Error)"]);
  } finally {
    Date.now = realNow;
  }
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

test("extractDeclaredTests reads the fenced code block under the Apex test classes heading", () => {
  assert.deepEqual(
    extractDeclaredTests(
      [
        "### Description",
        "",
        "```",
        "Some description.",
        "```",
        "",
        "### Apex test classes to run",
        "",
        "Write test class names separated by space.",
        "",
        "```",
        "FooTest BarTest, BazTest",
        "```",
        "",
        "### Deployment Steps",
        "",
        "```",
        "NotATest",
        "```"
      ].join("\n")
    ),
    ["FooTest", "BarTest", "BazTest"]
  );
  assert.deepEqual(extractDeclaredTests(""), []);
  assert.deepEqual(extractDeclaredTests("No section here"), []);
});

test("extractDeclaredTests returns nothing for an empty test-classes code block", () => {
  assert.deepEqual(
    extractDeclaredTests(
      ["### Apex test classes to run", "", "```", "", "```"].join("\n")
    ),
    []
  );
});

test("extractDeclaredTests ignores prose typed into the code block instead of class names", () => {
  assert.deepEqual(
    extractDeclaredTests(
      [
        "### Apex test classes to run",
        "",
        "```",
        "ALT_CLS_FooTest and the remaining seven changed classes each match a class of same name",
        "```"
      ].join("\n")
    ),
    ["ALT_CLS_FooTest"]
  );
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

test("isPermissionSetOrGroupOnly is true only when every path is a PermissionSet/PermissionSetGroup", () => {
  assert.equal(
    isPermissionSetOrGroupOnly([
      "force-app/main/default/permissionsets/AXF_PS_Foo.permissionset-meta.xml",
      "force-app/main/default/permissionsetgroups/AXF_PSG_Bar.permissionsetgroup-meta.xml"
    ]),
    true
  );
  assert.equal(
    isPermissionSetOrGroupOnly([
      "force-app/main/default/permissionsets/AXF_PS_Foo.permissionset-meta.xml",
      "force-app/main/default/classes/Foo.cls"
    ]),
    false
  );
  assert.equal(isPermissionSetOrGroupOnly([]), false);
});

test("testPlan skips tests entirely for a PermissionSet/PermissionSetGroup-only delta", () => {
  const plan = testPlan(
    [
      "force-app/main/default/permissionsets/AXF_PS_Foo.permissionset-meta.xml",
      "force-app/main/default/permissionsetgroups/AXF_PSG_Bar.permissionsetgroup-meta.xml"
    ],
    () => "",
    []
  );
  assert.deepEqual(plan, { testLevel: "NoTestRun", tests: [] });
});

test("testPlan does not skip tests when PS/PSG changes are mixed with other metadata", () => {
  const files = {
    "force-app/main/default/permissionsets/AXF_PS_Foo.permissionset-meta.xml":
      "",
    "force-app/main/default/classes/Foo.cls": "public class Foo {}"
  };
  assert.throws(
    () => testPlan(Object.keys(files), (p) => files[p], []),
    /Apex test classes to run/
  );
});

test("testPlan fails closed when production Apex has no test coverage in scope", () => {
  const files = {
    "force-app/main/default/classes/Foo.cls": "public class Foo {}"
  };
  assert.throws(
    () => testPlan(Object.keys(files), (p) => files[p], []),
    /Apex test classes to run/
  );
  assert.throws(
    () =>
      testPlan(["force-app/main/default/triggers/Bar.trigger"], () => "", []),
    /Apex test classes to run/
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

test("run() writes structured single-line GITHUB_OUTPUT fields for the PR comment", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "axon-delivery-test-"));
  const outputFile = path.join(dir, "github-output");
  fs.writeFileSync(outputFile, "");
  const previous = { ...process.env };
  const previousExit = process.exitCode;
  try {
    process.env.EVIDENCE_DIR = dir;
    process.env.GITHUB_OUTPUT = outputFile;
    process.env.TARGET_ENV = "STAGING";
    process.env.OPERATION = "deploy";
    await run();
    const output = fs.readFileSync(outputFile, "utf8");
    assert.match(output, /^outcome=Failed$/m);
    assert.match(output, /^deploymentId=$/m);
    assert.match(output, /^errorMessage=Only DEV\/UAT\/PROD/m);
  } finally {
    process.env = previous;
    process.exitCode = previousExit;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
