import test from "node:test";
import assert from "node:assert/strict";
import {
  analyzeTrigger,
  analyzeRepository,
  delegations
} from "./trigger-handler-boundary.mjs";

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

test("repository triggers honor the handler boundary", () => {
  const { triggers, violations } = analyzeRepository();
  assert.ok(triggers > 0);
  assert.deepEqual(violations, []);
});
