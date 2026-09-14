/**
 * @description Integridade bulk do dominio billing (AXF-65). Visibilidade de sistema para
 * proteger referencias ocultas; regras chamadas apenas pelos handlers de trigger.
 * - Nenhum registro billing e excluido (sem Delete em PS/PSG e bloqueio no trigger).
 * - BillingDocument: lifecycle OPEN -> CLOSED | CANCELLED; identidade imutavel.
 * - BillingDocumentVersion: ISSUED imutavel; transicoes conforme GBI-2; identidade imutavel.
 * - Linhas e alocacoes so nascem/mudam pelo servico e enquanto a versao esta em DRAFT.
 */
public without sharing class ALT_CLS_BillingGuard {
  private static Boolean writing = false;
  private static final Map<String, Set<String>> VERSION_TRANSITIONS = new Map<String, Set<String>>{
    'DRAFT' => new Set<String>{ 'REVIEWED', 'CANCELLED' },
    'REVIEWED' => new Set<String>{ 'DRAFT', 'ISSUING', 'CANCELLED' },
    'ISSUING' => new Set<String>{ 'ISSUED', 'FAILED_BEFORE_ISSUE' },
    'ISSUED' => new Set<String>{ 'CANCELLED', 'REPLACED' },
    'FAILED_BEFORE_ISSUE' => new Set<String>{ 'REVIEWED', 'CANCELLED' },
    'CANCELLED' => new Set<String>(),
    'REPLACED' => new Set<String>()
  };
  private static final Set<String> DOCUMENT_FROZEN = new Set<String>{
    'AXF_BDO_LKP_Account__c',
    'AXF_BDO_LKP_Contract__c',
    'AXF_BDO_LKP_Counterparty__c',
    'AXF_BDO_PKL_DocumentKind__c',
    'AXF_BDO_TXT_SeriesKey__c',
    'AXF_BDO_TXT_CurrencyIsoCode__c',
    'AXF_BDO_EXI_DocumentKey__c',
    'AXF_BDO_EXI_ClientRequestId__c'
  };
  private static final Set<String> VERSION_FROZEN = new Set<String>{
    'AXF_BDV_LKP_BillingDocument__c',
    'AXF_BDV_NUM_Revision__c',
    'AXF_BDV_EXI_VersionKey__c',
    'AXF_BDV_TXT_CurrencyIsoCode__c'
  };

  public static void beginWrite() {
    writing = true;
  }
  public static void endWrite() {
    writing = false;
  }
  public static Boolean isWriting() {
    return writing;
  }

  public static void documents(
    List<AXF_OBJ_BillingDocument__c> rows,
    Map<Id, AXF_OBJ_BillingDocument__c> oldMap,
    Boolean deleting
  ) {
    for (AXF_OBJ_BillingDocument__c row : rows) {
      if (deleting) {
        row.addError('Billing documents cannot be deleted.');
        continue;
      }
      if (oldMap == null) {
        if (row.AXF_BDO_PKL_Lifecycle__c == null) {
          row.AXF_BDO_PKL_Lifecycle__c = 'OPEN';
        }
        if (row.AXF_BDO_PKL_Lifecycle__c != 'OPEN') {
          row.addError('A billing document starts OPEN.');
        }
        continue;
      }
      AXF_OBJ_BillingDocument__c before = oldMap.get(row.Id);
      for (String field : DOCUMENT_FROZEN) {
        if (row.get(field) != before.get(field)) {
          row.addError('Billing document identity is immutable.');
          break;
        }
      }
      if (
        row.AXF_BDO_PKL_Lifecycle__c != before.AXF_BDO_PKL_Lifecycle__c &&
        (before.AXF_BDO_PKL_Lifecycle__c != 'OPEN' ||
        !(row.AXF_BDO_PKL_Lifecycle__c == 'CLOSED' ||
        row.AXF_BDO_PKL_Lifecycle__c == 'CANCELLED'))
      ) {
        row.addError('Invalid billing document lifecycle transition.');
      }
    }
  }

  public static void versions(
    List<AXF_OBJ_BillingDocumentVersion__c> rows,
    Map<Id, AXF_OBJ_BillingDocumentVersion__c> oldMap,
    Boolean deleting
  ) {
    for (AXF_OBJ_BillingDocumentVersion__c row : rows) {
      if (deleting) {
        row.addError('Billing document versions cannot be deleted.');
        continue;
      }
      if (oldMap == null) {
        if (row.AXF_BDV_PKL_State__c == null) {
          row.AXF_BDV_PKL_State__c = 'DRAFT';
        }
        if (row.AXF_BDV_PKL_State__c != 'DRAFT') {
          row.addError('A billing document version starts as DRAFT.');
        }
        continue;
      }
      AXF_OBJ_BillingDocumentVersion__c before = oldMap.get(row.Id);
      for (String field : VERSION_FROZEN) {
        if (row.get(field) != before.get(field)) {
          row.addError('Billing document version identity is immutable.');
          break;
        }
      }
      if (before.AXF_BDV_PKL_State__c == 'ISSUED') {
        for (String field : row.getPopulatedFieldsAsMap().keySet()) {
          if (
            field.endsWith('__c') &&
            field != 'AXF_BDV_PKL_State__c' &&
            row.get(field) != before.get(field)
          ) {
            row.addError('Issued billing content is immutable.');
            break;
          }
        }
      }
      if (row.AXF_BDV_PKL_State__c != before.AXF_BDV_PKL_State__c) {
        Set<String> allowed = VERSION_TRANSITIONS.get(
          before.AXF_BDV_PKL_State__c
        );
        if (allowed == null || !allowed.contains(row.AXF_BDV_PKL_State__c)) {
          row.addError('Invalid billing document version state transition.');
        }
      }
    }
  }

  // Trigger integrity must see the parent version regardless of the caller's CRUD permissions.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static void lines(
    List<AXF_OBJ_BillingDocumentLine__c> rows,
    Map<Id, AXF_OBJ_BillingDocumentLine__c> oldMap,
    Boolean deleting
  ) {
    Set<Id> versionIds = new Set<Id>();
    for (AXF_OBJ_BillingDocumentLine__c row : rows) {
      versionIds.add(row.AXF_BDL_MDR_DocumentVersion__c);
    }
    Map<Id, AXF_OBJ_BillingDocumentVersion__c> parents = new Map<Id, AXF_OBJ_BillingDocumentVersion__c>(
      [
        SELECT Id, AXF_BDV_PKL_State__c
        FROM AXF_OBJ_BillingDocumentVersion__c
        WHERE Id IN :versionIds
      ]
    );
    for (AXF_OBJ_BillingDocumentLine__c row : rows) {
      if (deleting) {
        row.addError('Billing document lines cannot be deleted.');
        continue;
      }
      if (!writing) {
        row.addError('Use the billing draft service.');
        continue;
      }
      AXF_OBJ_BillingDocumentVersion__c parent = parents.get(
        row.AXF_BDL_MDR_DocumentVersion__c
      );
      if (parent == null || parent.AXF_BDV_PKL_State__c != 'DRAFT') {
        row.addError('Only DRAFT versions accept line changes.');
        continue;
      }
      if (
        row.AXF_BDL_LKP_FinancialTransaction__c == null ||
        row.AXF_BDL_LKP_ContractApplicationSnapshot__c == null ||
        row.AXF_BDL_CUR_Amount__c == null
      ) {
        row.addError('Billing lines require typed sources and an amount.');
      }
    }
  }

  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static void workAllocations(
    List<AXF_OBJ_BillingDocumentWorkAllocation__c> rows,
    Map<Id, AXF_OBJ_BillingDocumentWorkAllocation__c> oldMap,
    Boolean deleting
  ) {
    Set<Id> lineIds = new Set<Id>();
    for (AXF_OBJ_BillingDocumentWorkAllocation__c row : rows) {
      lineIds.add(row.AXF_BWA_MDR_Line__c);
    }
    Map<Id, AXF_OBJ_BillingDocumentLine__c> parents = new Map<Id, AXF_OBJ_BillingDocumentLine__c>(
      [
        SELECT Id, AXF_BDL_MDR_DocumentVersion__r.AXF_BDV_PKL_State__c
        FROM AXF_OBJ_BillingDocumentLine__c
        WHERE Id IN :lineIds
      ]
    );
    for (AXF_OBJ_BillingDocumentWorkAllocation__c row : rows) {
      if (deleting) {
        row.addError('Billing work allocations cannot be deleted.');
        continue;
      }
      if (!writing) {
        row.addError('Use the billing draft service.');
        continue;
      }
      AXF_OBJ_BillingDocumentLine__c parent = parents.get(
        row.AXF_BWA_MDR_Line__c
      );
      if (
        parent == null ||
        parent.AXF_BDL_MDR_DocumentVersion__r.AXF_BDV_PKL_State__c != 'DRAFT'
      ) {
        row.addError('Only DRAFT versions accept work allocation changes.');
        continue;
      }
      if (
        row.AXF_BWA_NUM_AllocatedQuantity__c == null ||
        row.AXF_BWA_NUM_AllocatedQuantity__c <= 0
      ) {
        row.addError('Allocated quantity must be positive.');
      }
    }
  }
}
