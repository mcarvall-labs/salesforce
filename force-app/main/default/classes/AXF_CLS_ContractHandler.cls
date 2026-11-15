public with sharing class AXF_CLS_ContractHandler {
  @TestVisible
  private static Boolean bypass = false;

  private static final List<SObjectField> WATCHED = new List<SObjectField>{
    AXF_OBJ_Contract__c.Name,
    AXF_OBJ_Contract__c.CurrencyIsoCode,
    AXF_OBJ_Contract__c.AXF_CTR_PKL_Direction__c,
    AXF_OBJ_Contract__c.AXF_CTR_LKP_Category__c,
    AXF_OBJ_Contract__c.AXF_CTR_LKP_BankAccount__c,
    AXF_OBJ_Contract__c.AXF_CTR_LKP_CreditCard__c,
    AXF_OBJ_Contract__c.AXF_CTR_DAT_FirstDueDate__c,
    AXF_OBJ_Contract__c.AXF_CTR_NUM_DueDay__c,
    AXF_OBJ_Contract__c.AXF_CTR_DAT_EndDate__c,
    AXF_OBJ_Contract__c.AXF_CTR_CUR_Amount__c,
    AXF_OBJ_Contract__c.AXF_CTR_NUM_InstallmentCount__c,
    AXF_OBJ_Contract__c.AXF_CTR_CUR_FinancedAmount__c,
    AXF_OBJ_Contract__c.AXF_CTR_PCT_MonthlyRate__c,
    AXF_OBJ_Contract__c.AXF_CTR_PKL_AmortizationSystem__c
  };

  // Editing an active recurring, installment, consortium or financing contract
  // refreshes its Pending entries due today or later; existing Realized and
  // past entries are never changed (missing ones may still be added).
  public static void handleAfterUpdate(
    List<AXF_OBJ_Contract__c> contracts,
    Map<Id, AXF_OBJ_Contract__c> oldContracts
  ) {
    if (bypass) {
      return;
    }
    Set<Id> generating = generatingRecordTypes();
    Set<Id> changed = new Set<Id>();
    for (AXF_OBJ_Contract__c contract : contracts) {
      if (
        contract.AXF_CTR_PKL_Status__c ==
        ALT_CLS_ContractGeneration.STATUS_ACTIVE &&
        generating.contains(contract.RecordTypeId) &&
        hasChanged(contract, oldContracts.get(contract.Id))
      ) {
        changed.add(contract.Id);
      }
    }
    if (!changed.isEmpty()) {
      new ALT_CLS_ContractGeneration().generate(changed, true);
    }
  }

  private static Boolean hasChanged(
    AXF_OBJ_Contract__c current,
    AXF_OBJ_Contract__c previous
  ) {
    for (SObjectField field : WATCHED) {
      if (current.get(field) != previous.get(field)) {
        return true;
      }
    }
    return false;
  }

  private static Set<Id> generatingRecordTypes() {
    Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName();
    Set<Id> ids = new Set<Id>();
    for (
      String name : new List<String>{
        ALT_CLS_ContractGeneration.RT_RECURRING,
        ALT_CLS_ContractGeneration.RT_INSTALLMENT,
        ALT_CLS_ContractGeneration.RT_CONSORTIUM,
        ALT_CLS_ContractGeneration.RT_FINANCING
      }
    ) {
      if (infos.containsKey(name)) {
        ids.add(infos.get(name).getRecordTypeId());
      }
    }
    return ids;
  }
}
