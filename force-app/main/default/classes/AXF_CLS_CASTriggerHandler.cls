/**
 * @description Handler de trigger para AXF_OBJ_ContractApplicationSnapshot__c (AXF-57).
 * Garante: (1) imutabilidade de conteudo apos criacao (correcao = sucessor + SUPERSEDED);
 * (2) transicao de estado exclusiva ACTIVE -> SUPERSEDED via servico; (3) bloqueio de
 * delete (nenhum PSG concede Delete); (4) consistencia da proveniencia canonal e motivo
 * obrigatorio quando ha OVERRIDDEN (validados tambem no servico).
 */
public with sharing class AXF_CLS_CASTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_ContractApplicationSnapshot__c> newList
  ) {
    for (AXF_OBJ_ContractApplicationSnapshot__c record : newList) {
      if (String.isBlank(record.AXF_CAS_EXI_ApplicationIdentityHash__c)) {
        record.addError(
          'ApplicationIdentityHash e obrigatorio (identidade G6).'
        );
        continue;
      }
      validateProvenance(
        record.AXF_CAS_TAL_FieldProvenance__c,
        record.AXF_CAS_TAL_OverrideReason__c
      );
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ContractApplicationSnapshot__c> newList,
    Map<Id, AXF_OBJ_ContractApplicationSnapshot__c> oldMap
  ) {
    for (AXF_OBJ_ContractApplicationSnapshot__c record : newList) {
      AXF_OBJ_ContractApplicationSnapshot__c oldRecord = oldMap.get(record.Id);

      if (
        oldRecord.AXF_CAS_PKL_State__c ==
        ALT_CLS_ContractSnapshotService.STATE_SUPERSEDED
      ) {
        record.addError(
          'Snapshots SUPERSEDED sao historicos e estritamente imutaveis.'
        );
        continue;
      }

      // Em ACTIVE, o unico conteudo editavel sao os campos de bookkeeping de override
      // (proveniencia, motivo, ator, instante, versao). Transicao permitida: ACTIVE -> SUPERSEDED.
      Set<String> allowedMutable = new Set<String>{
        'AXF_CAS_PKL_State__c',
        'AXF_CAS_TAL_FieldProvenance__c',
        'AXF_CAS_TAL_OverrideReason__c',
        'AXF_CAS_LKP_OverriddenByUser__c',
        'AXF_CAS_DT_OverriddenAt__c',
        'AXF_CAS_NUM_Version__c'
      };
      Map<String, Object> oldFields = oldRecord.getPopulatedFieldsAsMap();
      for (String changedField : record.getPopulatedFieldsAsMap().keySet()) {
        if (!isChanged(record.get(changedField), oldFields.get(changedField))) {
          continue;
        }
        if (!allowedMutable.contains(changedField)) {
          record.addError(
            'Campo ' +
              changedField +
              ' nao pode ser alterado em snapshot ACTIVE (AXF-57, G7-2).'
          );
          break;
        }
        if (
          changedField == 'AXF_CAS_PKL_State__c' &&
          record.AXF_CAS_PKL_State__c !=
          ALT_CLS_ContractSnapshotService.STATE_SUPERSEDED
        ) {
          record.addError('Transicao invalida de estado de snapshot ACTIVE.');
          break;
        }
      }

      // Campos de override (proveniencia/reason/ator/instante) so mudam via servico, juntos.
      validateProvenance(
        record.AXF_CAS_TAL_FieldProvenance__c,
        record.AXF_CAS_TAL_OverrideReason__c
      );
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ContractApplicationSnapshot__c> oldList
  ) {
    for (AXF_OBJ_ContractApplicationSnapshot__c record : oldList) {
      record.addError(
        'ContractApplicationSnapshot e imutavel e nao pode ser excluido (AXF-57).'
      );
    }
  }

  /** Compara valores por conteudo (evita comparacao de referencia de Object em Date/Decimal/Id). */
  private static Boolean isChanged(Object newValue, Object oldValue) {
    if (newValue == null && oldValue == null) {
      return false;
    }
    if (newValue == null || oldValue == null) {
      return true;
    }
    return String.valueOf(newValue) != String.valueOf(oldValue);
  }

  private static void validateProvenance(String provenance, String reason) {
    Map<String, String> fields = ALT_CLS_ContractSnapshotService.parseProvenance(
      provenance
    );
    Boolean hasOverride = false;
    for (String field : fields.keySet()) {
      if (
        fields.get(field) == ALT_CLS_ContractSnapshotService.PROV_OVERRIDDEN
      ) {
        hasOverride = true;
      }
    }
    if (hasOverride && String.isBlank(reason)) {
      throw new AXF_CLS_ContractException(
        'Motivo do override e obrigatorio quando ha campo OVERRIDDEN (AC 2).'
      );
    }
  }
}
