import test from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  analyzeTrigger,
  analyzeRepository,
  delegations,
  packageDirectories
} from "./trigger-handler-boundary.mjs";

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  ".."
);

const exists = (name) => name === "AXF_CLS_ExampleTriggerHandler";

test("context dispatch with handler delegation passes", () => {
  const source = `/** doc with insert in comment */
trigger AXF_TRG_Example on AXF_OBJ_Example__c(before insert, before update, before delete) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_ExampleTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_ExampleTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  } else if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_ExampleTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}`;
  assert.deepEqual(analyzeTrigger("AXF_TRG_Example", source, exists), []);
});

test("platform event trigger delegating without dispatch passes", () => {
  const source = `trigger AXF_TRG_Evt on AXF_Evt__e(after insert) {
  AXF_CLS_ExampleTriggerHandler.handle(Trigger.new);
}`;
  assert.deepEqual(analyzeTrigger("AXF_TRG_Evt", source, exists), []);
});

test("business logic inside a trigger is rejected", () => {
  const source = `trigger AXF_TRG_Bad on AXF_OBJ_Example__c(before insert) {
  for (AXF_OBJ_Example__c row : Trigger.new) {
    if (row.Amount__c == null) {
      row.addError('required');
    }
    row.Total__c = row.Amount__c * 2;
  }
  List<Account> accounts = [SELECT Id FROM Account];
  insert accounts;
}`;
  const violations = analyzeTrigger("AXF_TRG_Bad", source, exists);
  for (const reason of [
    "SOQL query",
    "DML statement",
    "record validation",
    "record iteration",
    "assignment"
  ]) {
    assert.ok(
      violations.some((violation) => violation.includes(reason)),
      reason
    );
  }
});

test("direct domain-service call is not accepted as delegation", () => {
  const source = `trigger AXF_TRG_Direct on AXF_OBJ_Example__c(before insert, before delete) {
  ALT_CLS_RealizationGuard.originals(
    Trigger.isDelete ? Trigger.old : Trigger.new,
    Trigger.oldMap,
    Trigger.isDelete
  );
}`;
  const violations = analyzeTrigger("AXF_TRG_Direct", source, exists);
  assert.ok(
    violations.some((violation) =>
      violation.includes("not a handler delegation")
    )
  );
});

test("missing handler class and non-handler class names are rejected", () => {
  const missing = `trigger AXF_TRG_Missing on AXF_OBJ_Example__c(before insert) {
  AXF_CLS_MissingTriggerHandler.handleBeforeInsert(Trigger.new);
}`;
  assert.ok(
    analyzeTrigger("AXF_TRG_Missing", missing, exists).some((violation) =>
      violation.includes("does not exist")
    )
  );
  const service = `trigger AXF_TRG_Service on AXF_OBJ_Example__c(before insert) {
  AXF_CLS_SomeService.handleBeforeInsert(Trigger.new);
}`;
  assert.ok(
    analyzeTrigger("AXF_TRG_Service", service, exists).some((violation) =>
      violation.includes("not an AXF_CLS_*Handler class")
    )
  );
});

test("delegation requires trigger context arguments", () => {
  assert.equal(
    delegations("AXF_CLS_XHandler.run(Trigger.new, Trigger.oldMap);").method,
    "run"
  );
  assert.equal(delegations("AXF_CLS_XHandler.run(someList);"), null);
  assert.equal(delegations("AXF_CLS_XHandler.run();"), null);
});

test("switch dispatch, casts, Trigger.size and mixed-case keywords pass", () => {
  const source = `Trigger AXF_TRG_Switch On AXF_OBJ_Example__c(before insert, after update) {
  switch on Trigger.operationType {
    when BEFORE_INSERT {
      AXF_CLS_ExampleTriggerHandler.handleBeforeInsert((List<AXF_OBJ_Example__c>) Trigger.new, Trigger.size);
    }
    when AFTER_UPDATE, AFTER_INSERT {
      AXF_CLS_ExampleTriggerHandler.handleAfter((Map<Id, AXF_OBJ_Example__c>) Trigger.newMap, trigger.OldMap);
    }
    when else {
      AXF_CLS_ExampleTriggerHandler.handleOther(Trigger.operationType);
    }
  }
}`;
  assert.deepEqual(analyzeTrigger("AXF_TRG_Switch", source, exists), []);
});

test("string literals cannot hide code and keywords are case-insensitive", () => {
  const source = `trigger AXF_TRG_Hidden on AXF_OBJ_Example__c(before insert) {
  AXF_CLS_ExampleTriggerHandler.handleBeforeInsert(Trigger.new);
  System.debug('// not a comment');
  INSERT(Trigger.new);
}`;
  const violations = analyzeTrigger("AXF_TRG_Hidden", source, exists);
  assert.ok(
    violations.some((violation) => violation.includes("DML statement"))
  );
  assert.ok(
    violations.some((violation) =>
      violation.includes("not a handler delegation")
    )
  );
});

test("unbalanced parentheses and multiple handlers are reported", () => {
  const unbalanced = `trigger AXF_TRG_Unbalanced on AXF_OBJ_Example__c(before insert) {
  AXF_CLS_ExampleTriggerHandler.handleBeforeInsert((Trigger.new);
}`;
  assert.ok(
    analyzeTrigger("AXF_TRG_Unbalanced", unbalanced, exists).some((violation) =>
      violation.includes("unbalanced parentheses")
    )
  );
  const two = `trigger AXF_TRG_Two on AXF_OBJ_Example__c(before insert) {
  AXF_CLS_ExampleTriggerHandler.handleBeforeInsert(Trigger.new);
  AXF_CLS_OtherHandler.handleBeforeInsert(Trigger.new);
}`;
  assert.ok(
    analyzeTrigger("AXF_TRG_Two", two, (name) =>
      ["AXF_CLS_ExampleTriggerHandler", "AXF_CLS_OtherHandler"].includes(name)
    ).some((violation) => violation.includes("more than one handler"))
  );
});

test("package directories come from sfdx-project.json", () => {
  const directories = packageDirectories(repositoryRoot);
  assert.ok(directories.length >= 1);
  assert.ok(
    directories.some((directory) =>
      directory.split(path.sep).join("/").endsWith("force-app/main/default")
    )
  );
});

test("repository triggers honor the handler boundary", () => {
  const { triggers, violations } = analyzeRepository(repositoryRoot);
  assert.ok(triggers > 0);
  assert.deepEqual(violations, []);
});
