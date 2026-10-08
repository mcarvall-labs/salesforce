public with sharing class AXF_CLS_CTRL_ContractGeneration {
  public class Summary {
    @AuraEnabled
    public Integer created;
    @AuraEnabled
    public Integer updated;
    @AuraEnabled
    public List<String> messages;
  }

  // "Gerar lançamentos": creates the missing entries and refreshes the Pending future ones.
  @AuraEnabled
  public static Summary generate(Id contractId) {
    if (contractId == null) {
      throw new AuraHandledException('Informe o contrato.');
    }
    if (
      !Schema.sObjectType.AXF_OBJ_Entry__c.isCreateable() ||
      !Schema.sObjectType.AXF_OBJ_Entry__c.isUpdateable()
    ) {
      throw new AuraHandledException(
        'Você não tem permissão para gerar lançamentos.'
      );
    }
    List<AXF_OBJ_Contract__c> visible = [
      SELECT Id
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
      WITH USER_MODE
    ];
    if (visible.isEmpty()) {
      throw new AuraHandledException('Contrato não encontrado.');
    }
    ALT_CLS_ContractGeneration.Result result = new ALT_CLS_ContractGeneration()
      .generate(new Set<Id>{ contractId }, true);
    Summary summary = new Summary();
    summary.created = result.created;
    summary.updated = result.updated;
    summary.messages = result.messages;
    return summary;
  }
}
