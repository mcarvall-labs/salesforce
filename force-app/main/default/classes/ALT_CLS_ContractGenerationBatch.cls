/**
 * @description Monthly extension of the recurring contracts: for every Active recurring contract
 * it adds the Pending entries that are missing up to the 12-month horizon. It never rewrites an
 * existing entry, so the real amount a user typed on a variable bill survives; changing amounts
 * and dates is the job of the "Gerar lançamentos" action.
 */
public with sharing class ALT_CLS_ContractGenerationBatch implements Database.Batchable<SObject>, Database.Stateful {
  public static final Integer SCOPE_SIZE = 10;

  // Skipped contracts and failed saves of the whole run, logged in finish().
  @TestVisible
  private final List<String> messages = new List<String>();

  public static Id run() {
    return Database.executeBatch(
      new ALT_CLS_ContractGenerationBatch(),
      SCOPE_SIZE
    );
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM AXF_OBJ_Contract__c
        WHERE
          RecordType.DeveloperName = :ALT_CLS_ContractGeneration.RT_RECURRING
          AND AXF_CTR_PKL_Status__c = :ALT_CLS_ContractGeneration.STATUS_ACTIVE
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<AXF_OBJ_Contract__c> scope
  ) {
    ALT_CLS_ContractGeneration.Result result = new ALT_CLS_ContractGeneration()
      .generate(new Map<Id, AXF_OBJ_Contract__c>(scope).keySet(), false);
    messages.addAll(result.messages);
  }

  public void finish(Database.BatchableContext context) {
    if (!messages.isEmpty()) {
      System.debug(
        LoggingLevel.WARN,
        'Contract generation: ' + String.join(messages, ' | ')
      );
    }
  }
}
