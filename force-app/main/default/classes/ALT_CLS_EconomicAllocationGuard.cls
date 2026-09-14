/**
 * @description Integridade bulk do rateio economico (AXF-126). Visibilidade de sistema para
 * proteger referencias ocultas; chamado apenas pelos handlers de trigger.
 * - Sem Delete em set/parcela. - Set: identidade/ancora imutaveis; CONFIRMED imutavel exceto
 *   transicao para SUPERSEDED|REVERSED via servico; escrita somente pelo servico.
 * - Parcela: nasce/muda so pelo servico e so em set DRAFT; magnitude positiva; percentual em (0,100].
 */
public without sharing class ALT_CLS_EconomicAllocationGuard {
  private static Boolean writing = false;
  private static final Set<String> SET_FROZEN = new Set<String>{
    'AXF_EAS_LKP_BankTransaction__c',
    'AXF_EAS_LKP_CardTransaction__c',
    'AXF_EAS_LKP_FinancialTransaction__c',
    'AXF_EAS_LKP_HolderAccount__c',
    'AXF_EAS_TXT_FactIdentity__c',
    'AXF_EAS_NUM_Revision__c',
    'AXF_EAS_EXI_SetKey__c',
    'AXF_EAS_NUM_FactMagnitude__c',
    'AXF_EAS_TXT_CurrencyIsoCode__c'
  };
  private static final Map<String, Set<String>> TRANSITIONS = new Map<String, Set<String>>{
    'DRAFT' => new Set<String>{ 'CONFIRMED' },
    'CONFIRMED' => new Set<String>{ 'SUPERSEDED', 'REVERSED' },
    'SUPERSEDED' => new Set<String>(),
    'REVERSED' => new Set<String>()
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

  public static void sets(
    List<AXF_OBJ_EconomicAllocationSet__c> rows,
    Map<Id, AXF_OBJ_EconomicAllocationSet__c> oldMap,
    Boolean deleting
  ) {
    for (AXF_OBJ_EconomicAllocationSet__c row : rows) {
      if (deleting) {
        row.addError('Economic allocation sets cannot be deleted.');
        continue;
      }
      if (!writing) {
        row.addError('Use the economic allocation service.');
        continue;
      }
      if (oldMap == null) {
        if (row.AXF_EAS_PKL_State__c == null) {
          row.AXF_EAS_PKL_State__c = 'DRAFT';
        }
        if (row.AXF_EAS_PKL_State__c != 'DRAFT') {
          row.addError('An economic allocation set starts as DRAFT.');
        }
        continue;
      }
      AXF_OBJ_EconomicAllocationSet__c before = oldMap.get(row.Id);
      for (String field : SET_FROZEN) {
        if (row.get(field) != before.get(field)) {
          row.addError('Economic allocation identity is immutable.');
          break;
        }
      }
      if (row.AXF_EAS_PKL_State__c != before.AXF_EAS_PKL_State__c) {
        Set<String> allowed = TRANSITIONS.get(before.AXF_EAS_PKL_State__c);
        if (allowed == null || !allowed.contains(row.AXF_EAS_PKL_State__c)) {
          row.addError('Invalid economic allocation state transition.');
        }
      }
    }
  }

  // Trigger integrity must see the parent set regardless of the caller's CRUD permissions.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static void allocations(
    List<AXF_OBJ_EconomicAllocation__c> rows,
    Map<Id, AXF_OBJ_EconomicAllocation__c> oldMap,
    Boolean deleting
  ) {
    Set<Id> setIds = new Set<Id>();
    for (AXF_OBJ_EconomicAllocation__c row : rows) {
      setIds.add(row.AXF_EA_MDR_AllocationSet__c);
    }
    Map<Id, AXF_OBJ_EconomicAllocationSet__c> parents = new Map<Id, AXF_OBJ_EconomicAllocationSet__c>(
      [
        SELECT Id, AXF_EAS_PKL_State__c
        FROM AXF_OBJ_EconomicAllocationSet__c
        WHERE Id IN :setIds
      ]
    );
    for (AXF_OBJ_EconomicAllocation__c row : rows) {
      if (deleting) {
        row.addError(
          'Economic allocations cannot be deleted; reverse with a compensating set.'
        );
        continue;
      }
      if (!writing) {
        row.addError('Use the economic allocation service.');
        continue;
      }
      AXF_OBJ_EconomicAllocationSet__c parent = parents.get(
        row.AXF_EA_MDR_AllocationSet__c
      );
      if (parent == null || parent.AXF_EAS_PKL_State__c != 'DRAFT') {
        row.addError('Only DRAFT sets accept allocation changes.');
        continue;
      }
      if (
        row.AXF_EA_NUM_Magnitude__c == null ||
        row.AXF_EA_NUM_Magnitude__c <= 0 ||
        row.AXF_EA_NUM_Percent__c == null ||
        row.AXF_EA_NUM_Percent__c <= 0 ||
        row.AXF_EA_NUM_Percent__c > 100
      ) {
        row.addError('Allocation magnitude and percent must be positive.');
      }
    }
  }
}
