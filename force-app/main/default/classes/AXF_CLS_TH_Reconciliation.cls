public with sharing class AXF_CLS_TH_Reconciliation {
  private static final String RECONCILED = 'RECONCILED';
  private static final String UNRECONCILED = 'UNRECONCILED';

  public static void validateCashFlows(
    List<AXF_OBJ_CashFlow__c> records,
    Map<Id, AXF_OBJ_CashFlow__c> oldMap
  ) {
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (AXF_OBJ_CashFlow__c record : records) {
      Boolean bankLinked = record.AXF_CF_LKP_BankAccountTransaction__c != null;
      Boolean cardLinked = record.AXF_CF_LKP_CreditCardTransaction__c != null;
      if (
        (record.AXF_CF_PKL_ReconciliationStatus__c == RECONCILED) !=
        (bankLinked ^ cardLinked) ||
        (record.AXF_CF_PKL_ReconciliationStatus__c == UNRECONCILED &&
        (bankLinked || cardLinked))
      ) {
        record.addError(
          'A conciliação exige exatamente uma transação e um status compatível.'
        );
      }
      if (
        !ALT_CLS_CashFlowSettlement.serviceOperation && changed(record, oldMap)
      ) {
        if (bankLinked)
          bankIds.add(record.AXF_CF_LKP_BankAccountTransaction__c);
        if (cardLinked)
          cardIds.add(record.AXF_CF_LKP_CreditCardTransaction__c);
      }
    }
    if (ALT_CLS_CashFlowSettlement.serviceOperation)
      return;
    Map<Id, AXF_OBJ_BankAccountTransaction__c> banks = bankIds.isEmpty()
      ? new Map<Id, AXF_OBJ_BankAccountTransaction__c>()
      : new Map<Id, AXF_OBJ_BankAccountTransaction__c>(
          [
            SELECT
              Id,
              AXF_BAT_LKP_CashFlow__c,
              AXF_BAT_PKL_ReconciliationStatus__c
            FROM AXF_OBJ_BankAccountTransaction__c
            WHERE Id IN :bankIds
            WITH USER_MODE
          ]
        );
    Map<Id, AXF_OBJ_CreditCardTransaction__c> cards = cardIds.isEmpty()
      ? new Map<Id, AXF_OBJ_CreditCardTransaction__c>()
      : new Map<Id, AXF_OBJ_CreditCardTransaction__c>(
          [
            SELECT
              Id,
              AXF_CCT_LKP_CashFlow__c,
              AXF_CCT_PKL_ReconciliationStatus__c
            FROM AXF_OBJ_CreditCardTransaction__c
            WHERE Id IN :cardIds
            WITH USER_MODE
          ]
        );
    for (AXF_OBJ_CashFlow__c record : records) {
      if (
        !changed(record, oldMap) ||
        record.AXF_CF_PKL_ReconciliationStatus__c != RECONCILED
      )
        continue;
      if (record.AXF_CF_LKP_BankAccountTransaction__c != null) {
        AXF_OBJ_BankAccountTransaction__c bank = banks.get(
          record.AXF_CF_LKP_BankAccountTransaction__c
        );
        if (
          bank == null ||
          bank.AXF_BAT_LKP_CashFlow__c != record.Id ||
          bank.AXF_BAT_PKL_ReconciliationStatus__c != RECONCILED
        )
          record.addError(
            'Use a operação de conciliação para manter os vínculos recíprocos.'
          );
      } else if (record.AXF_CF_LKP_CreditCardTransaction__c != null) {
        AXF_OBJ_CreditCardTransaction__c card = cards.get(
          record.AXF_CF_LKP_CreditCardTransaction__c
        );
        if (
          card == null ||
          card.AXF_CCT_LKP_CashFlow__c != record.Id ||
          card.AXF_CCT_PKL_ReconciliationStatus__c != RECONCILED
        )
          record.addError(
            'Use a operação de conciliação para manter os vínculos recíprocos.'
          );
      }
    }
  }

  public static void validateBanks(
    List<AXF_OBJ_BankAccountTransaction__c> records,
    Map<Id, AXF_OBJ_BankAccountTransaction__c> oldMap
  ) {
    Set<Id> cashFlowIds = new Set<Id>();
    for (AXF_OBJ_BankAccountTransaction__c record : records) {
      Boolean linked = record.AXF_BAT_LKP_CashFlow__c != null;
      if ((record.AXF_BAT_PKL_ReconciliationStatus__c == RECONCILED) != linked)
        record.addError(
          'O status e o vínculo de conciliação devem ser atualizados juntos.'
        );
      if (
        !ALT_CLS_CashFlowSettlement.serviceOperation &&
        changedBank(record, oldMap) &&
        linked
      )
        cashFlowIds.add(record.AXF_BAT_LKP_CashFlow__c);
    }
    if (ALT_CLS_CashFlowSettlement.serviceOperation || cashFlowIds.isEmpty())
      return;
    Map<Id, AXF_OBJ_CashFlow__c> flows = new Map<Id, AXF_OBJ_CashFlow__c>(
      [
        SELECT
          Id,
          AXF_CF_LKP_BankAccountTransaction__c,
          AXF_CF_PKL_ReconciliationStatus__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id IN :cashFlowIds
        WITH USER_MODE
      ]
    );
    for (AXF_OBJ_BankAccountTransaction__c record : records)
      if (
        changedBank(record, oldMap) && record.AXF_BAT_LKP_CashFlow__c != null
      ) {
        AXF_OBJ_CashFlow__c flow = flows.get(record.AXF_BAT_LKP_CashFlow__c);
        if (
          flow == null ||
          flow.AXF_CF_LKP_BankAccountTransaction__c != record.Id ||
          flow.AXF_CF_PKL_ReconciliationStatus__c != RECONCILED
        )
          record.addError(
            'Use a operação de conciliação para manter os vínculos recíprocos.'
          );
      }
  }

  public static void validateCards(
    List<AXF_OBJ_CreditCardTransaction__c> records,
    Map<Id, AXF_OBJ_CreditCardTransaction__c> oldMap
  ) {
    Set<Id> cashFlowIds = new Set<Id>();
    for (AXF_OBJ_CreditCardTransaction__c record : records) {
      Boolean linked = record.AXF_CCT_LKP_CashFlow__c != null;
      if ((record.AXF_CCT_PKL_ReconciliationStatus__c == RECONCILED) != linked)
        record.addError(
          'O status e o vínculo de conciliação devem ser atualizados juntos.'
        );
      if (
        !ALT_CLS_CashFlowSettlement.serviceOperation &&
        changedCard(record, oldMap) &&
        linked
      )
        cashFlowIds.add(record.AXF_CCT_LKP_CashFlow__c);
    }
    if (ALT_CLS_CashFlowSettlement.serviceOperation || cashFlowIds.isEmpty())
      return;
    Map<Id, AXF_OBJ_CashFlow__c> flows = new Map<Id, AXF_OBJ_CashFlow__c>(
      [
        SELECT
          Id,
          AXF_CF_LKP_CreditCardTransaction__c,
          AXF_CF_PKL_ReconciliationStatus__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id IN :cashFlowIds
        WITH USER_MODE
      ]
    );
    for (AXF_OBJ_CreditCardTransaction__c record : records)
      if (
        changedCard(record, oldMap) && record.AXF_CCT_LKP_CashFlow__c != null
      ) {
        AXF_OBJ_CashFlow__c flow = flows.get(record.AXF_CCT_LKP_CashFlow__c);
        if (
          flow == null ||
          flow.AXF_CF_LKP_CreditCardTransaction__c != record.Id ||
          flow.AXF_CF_PKL_ReconciliationStatus__c != RECONCILED
        )
          record.addError(
            'Use a operação de conciliação para manter os vínculos recíprocos.'
          );
      }
  }

  public static void preventCashFlowDelete(List<AXF_OBJ_CashFlow__c> records) {
    for (AXF_OBJ_CashFlow__c r : records)
      if (
        r.AXF_CF_LKP_BankAccountTransaction__c != null ||
        r.AXF_CF_LKP_CreditCardTransaction__c != null
      )
        r.addError('Desfaça a conciliação antes de excluir.');
  }
  public static void preventBankDelete(
    List<AXF_OBJ_BankAccountTransaction__c> records
  ) {
    for (AXF_OBJ_BankAccountTransaction__c r : records)
      if (r.AXF_BAT_LKP_CashFlow__c != null)
        r.addError('Desfaça a conciliação antes de excluir.');
  }
  public static void preventCardDelete(
    List<AXF_OBJ_CreditCardTransaction__c> records
  ) {
    for (AXF_OBJ_CreditCardTransaction__c r : records)
      if (r.AXF_CCT_LKP_CashFlow__c != null)
        r.addError('Desfaça a conciliação antes de excluir.');
  }
  private static Boolean changed(
    AXF_OBJ_CashFlow__c r,
    Map<Id, AXF_OBJ_CashFlow__c> olds
  ) {
    AXF_OBJ_CashFlow__c o = olds == null ? null : olds.get(r.Id);
    return o == null ||
      o.AXF_CF_PKL_ReconciliationStatus__c !=
      r.AXF_CF_PKL_ReconciliationStatus__c ||
      o.AXF_CF_LKP_BankAccountTransaction__c !=
      r.AXF_CF_LKP_BankAccountTransaction__c ||
      o.AXF_CF_LKP_CreditCardTransaction__c !=
      r.AXF_CF_LKP_CreditCardTransaction__c;
  }
  private static Boolean changedBank(
    AXF_OBJ_BankAccountTransaction__c r,
    Map<Id, AXF_OBJ_BankAccountTransaction__c> olds
  ) {
    AXF_OBJ_BankAccountTransaction__c o = olds == null ? null : olds.get(r.Id);
    return o == null ||
      o.AXF_BAT_PKL_ReconciliationStatus__c !=
      r.AXF_BAT_PKL_ReconciliationStatus__c ||
      o.AXF_BAT_LKP_CashFlow__c != r.AXF_BAT_LKP_CashFlow__c;
  }
  private static Boolean changedCard(
    AXF_OBJ_CreditCardTransaction__c r,
    Map<Id, AXF_OBJ_CreditCardTransaction__c> olds
  ) {
    AXF_OBJ_CreditCardTransaction__c o = olds == null ? null : olds.get(r.Id);
    return o == null ||
      o.AXF_CCT_PKL_ReconciliationStatus__c !=
      r.AXF_CCT_PKL_ReconciliationStatus__c ||
      o.AXF_CCT_LKP_CashFlow__c != r.AXF_CCT_LKP_CashFlow__c;
  }
}
