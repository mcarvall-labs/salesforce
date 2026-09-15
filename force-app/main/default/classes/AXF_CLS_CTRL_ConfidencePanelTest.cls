/**
 * @description AXF-143: controller delega ao servico e sanitiza falhas como {code}.
 */
@IsTest
private class AXF_CLS_CTRL_ConfidencePanelTest {
  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User gestor = new User(
      Alias = 'axf143c',
      Email = 'axf143c@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Controller Gestor',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf143c.' + System.now().getTime() + '@example.invalid'
    );
    User participant = gestor.clone(false, false, false, false);
    participant.Alias = 'axf143d';
    participant.Username =
      'axf143d.' +
      System.now().getTime() +
      '@example.invalid';
    insert new List<User>{ gestor, participant };
    Map<String, Id> permissionSets = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE Name IN ('AXF_PS_GestorFinanceiro', 'AXF_PS_Participante')
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = gestor.Id,
        PermissionSetId = permissionSets.get('AXF_PS_GestorFinanceiro')
      ),
      new PermissionSetAssignment(
        AssigneeId = participant.Id,
        PermissionSetId = permissionSets.get('AXF_PS_Participante')
      )
    };
  }

  @IsTest
  static void delegatesAndSanitizes() {
    User gestor = [SELECT Id FROM User WHERE Alias = 'axf143c' LIMIT 1];
    System.runAs(gestor) {
      Account holder = new Account(
        Name = 'Empresa Controller',
        RecordTypeId = Account.SObjectType.getDescribe()
          .getRecordTypeInfosByDeveloperName()
          .get('AXF_Business')
          .getRecordTypeId()
      );
      insert holder;
      insert new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = holder.Id,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BA_TXT_InstitutionName__c = 'Banco ctrl',
        AXF_BA_TXT_NumberMasked__c = '****ctrl',
        AXF_BA_EXI_ManualKey__c = 'manual-ctrl-' + System.now().getTime(),
        AXF_BA_NUM_Version__c = 0
      );
      Test.startTest();
      List<ALT_CLS_ConfidencePanelService.HolderOption> holders = AXF_CLS_CTRL_ConfidencePanel.getHolders();
      ALT_CLS_ConfidencePanelService.Panel panel = AXF_CLS_CTRL_ConfidencePanel.explain(
        new List<Id>{ holder.Id }
      );
      Test.stopTest();
      Assert.areEqual(1, holders.size());
      Assert.areEqual(
        'DEGRADED',
        panel.level,
        'fonte manual sem importacao = UNKNOWN'
      );
      Assert.areEqual(1, panel.sources.size());
      try {
        AXF_CLS_CTRL_ConfidencePanel.explain(new List<Id>());
        Assert.fail('INVALID_INPUT esperado');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
    }
    User participant = [SELECT Id FROM User WHERE Alias = 'axf143d' LIMIT 1];
    System.runAs(participant) {
      try {
        AXF_CLS_CTRL_ConfidencePanel.getHolders();
        Assert.fail('FORBIDDEN esperado');
      } catch (AuraHandledException expected) {
        Assert.areEqual('FORBIDDEN', expected.getMessage());
      }
    }
  }
}
