/**
 * @description Transactions already linked to an Entry (Lançamento), whoever the Entry belongs to.
 * It ignores sharing on purpose: a transaction linked to an Entry the caller cannot see is still
 * linked, and reconciling it again would break the 1 Entry : 1 transaction rule. Only the ids of
 * the requested transactions come back, nothing of the Entries is exposed.
 */
public without sharing class ALT_CLS_ReconciliationLinks {
  public Set<Id> linked(Set<Id> bankIds, Set<Id> cardIds) {
    Set<Id> linked = new Set<Id>();
    if (bankIds != null && !bankIds.isEmpty()) {
      for (AXF_OBJ_Entry__c entry : [
        SELECT AXF_ENT_LKP_BankAccountTransaction__c
        FROM AXF_OBJ_Entry__c
        WHERE AXF_ENT_LKP_BankAccountTransaction__c IN :bankIds
      ]) {
        linked.add(entry.AXF_ENT_LKP_BankAccountTransaction__c);
      }
    }
    if (cardIds != null && !cardIds.isEmpty()) {
      for (AXF_OBJ_Entry__c entry : [
        SELECT AXF_ENT_LKP_CreditCardTransaction__c
        FROM AXF_OBJ_Entry__c
        WHERE AXF_ENT_LKP_CreditCardTransaction__c IN :cardIds
      ]) {
        linked.add(entry.AXF_ENT_LKP_CreditCardTransaction__c);
      }
    }
    return linked;
  }
}
