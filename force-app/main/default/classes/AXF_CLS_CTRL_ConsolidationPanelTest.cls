/**
 * @description AXF-125: o controlador de apresentacao entrega o contexto autorizado (titulares,
 * moeda de apresentacao canonica, capability) e delega o calculo ao servico, sanitizando falhas
 * como {code}. Sem capacidade -> lista vazia e canConsolidate false; sem escopo -> INVALID_INPUT.
 */
@IsTest
private class AXF_CLS_CTRL_ConsolidationPanelTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User gestor = new User(
      Alias = 'axf125g',
      Email = 'axf125g@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Controller Gestor',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf125g.' + System.now().getTime() + '@example.invalid'
    );
    User participant = gestor.clone(false, false, false, false);
    participant.Alias = 'axf125p';
    participant.Username =
      'axf125p.' +
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
    Assert.areEqual(2, permissionSets.size(), 'permission sets must exist');
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
  static void presenterContextAndConsolidationComeFromTheServices() {
    System.runAs(byAlias('axf125g')) {
      Account holder = new Account(
        Name = 'Empresa Consolidada',
        RecordTypeId = Account.SObjectType.getDescribe()
          .getRecordTypeInfosByDeveloperName()
          .get('AXF_Business')
          .getRecordTypeId()
      );
      insert holder;
      Test.startTest();
      AXF_CLS_CTRL_ConsolidationPanel.Context context = AXF_CLS_CTRL_ConsolidationPanel.getContext();
      ALT_CLS_ConsolidationService.Result result = AXF_CLS_CTRL_ConsolidationPanel.consolidate(
        new List<Id>{ holder.Id },
        null
      );
      Test.stopTest();

      Assert.isTrue(context.canConsolidate, 'a capability vem do servidor');
      Assert.areEqual(
        ALT_CLS_ConsolidationService.POLICY_VERSION,
        context.policyVersion,
        'a policy canonica chega intacta ao LWC'
      );
      Assert.areEqual(
        1,
        context.holders.size(),
        'o titular autorizado e listado'
      );
      Assert.areEqual('Empresa Consolidada', context.holders[0].name);
      Assert.isNotNull(
        context.currencies,
        'as moedas de apresentacao vem da preferencia canonica'
      );
      Assert.areEqual(
        holder.Id,
        result.holders[0].accountId,
        'o controlador repassa o resultado derivado, nao o reconstroi'
      );
      Assert.areEqual(
        'AUTHORIZED',
        result.holders[0].state,
        'o titular com controle total e autorizado'
      );
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_FULL,
        result.confidence,
        'sem fatos e sem ressalva a confianca e completa'
      );
      Assert.isNull(
        result.comparableTotal,
        'sem moeda de apresentacao nao ha comparacao'
      );
      try {
        AXF_CLS_CTRL_ConsolidationPanel.consolidate(new List<Id>(), null);
        Assert.fail('INVALID_INPUT esperado');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
    }
  }

  @IsTest
  static void withoutTheCapabilityNothingIsListedAndNothingIsDerived() {
    System.runAs(byAlias('axf125p')) {
      AXF_CLS_CTRL_ConsolidationPanel.Context context = AXF_CLS_CTRL_ConsolidationPanel.getContext();
      Assert.isFalse(
        context.canConsolidate,
        'a capability ausente e declarada'
      );
      Assert.areEqual(
        0,
        context.holders.size(),
        'sem capability nenhum titular e exposto ao LWC'
      );
      try {
        AXF_CLS_CTRL_ConsolidationPanel.consolidate(
          new List<Id>{ '001000000000001' },
          null
        );
        Assert.fail('FORBIDDEN esperado');
      } catch (AuraHandledException expected) {
        Assert.areEqual('FORBIDDEN', expected.getMessage());
      }
    }
  }
}
