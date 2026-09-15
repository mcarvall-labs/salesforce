/**
 * @description Handler de trigger para AXF_OBJ_TransactionObservation__c (AXF-109).
 * Somente despacho de contexto; observacoes sao imutaveis: sem update de conteudo e sem delete.
 */
public with sharing class AXF_CLS_TOBTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_TransactionObservation__c> newList
  ) {
    for (AXF_OBJ_TransactionObservation__c row : newList) {
      if (!ALT_CLS_TransactionObservationService.isWriting()) {
        row.addError('Use the transaction observation service.');
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_TransactionObservation__c> newList,
    Map<Id, AXF_OBJ_TransactionObservation__c> oldMap
  ) {
    for (AXF_OBJ_TransactionObservation__c row : newList) {
      row.addError(
        'Observations are immutable; a changed fact creates a new revision.'
      );
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_TransactionObservation__c> oldList,
    Map<Id, AXF_OBJ_TransactionObservation__c> oldMap
  ) {
    for (AXF_OBJ_TransactionObservation__c row : oldList) {
      row.addError('Observations cannot be deleted.');
    }
  }
}
