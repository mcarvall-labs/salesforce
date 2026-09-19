/**
 * @description AXF-125: o controlador de apresentacao entrega o contexto autorizado (titulares,
 * moeda de apresentacao canonica, capability) e delega o calculo ao servico, sanitizando falhas
 * como {code}. Sem capacidade -> lista vazia e canConsolidate false; sem escopo -> INVALID_INPUT;
 * sem a concessao da moeda de apresentacao (AXF-87) o painel continua de pe, sem comparacao.
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
    User withCurrency = gestor.clone(false, false, false, false);
    withCurrency.Alias = 'axf125c';
    withCurrency.Username =
      'axf125c.' +
      System.now().getTime() +
      '@example.invalid';
    User participant = gestor.clone(false, false, false, false);
    participant.Alias = 'axf125p';
    participant.Username =
      'axf125p.' +
      System.now().getTime() +
      '@example.invalid';
    insert new List<User>{ gestor, withCurrency, participant };
    Map<String, Id> permissionSets = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_Participante',
          'AXF_PS_ReportCurrency'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    Assert.areEqual(3, permissionSets.size(), 'permission sets must exist');
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = gestor.Id,
        PermissionSetId = permissionSets.get('AXF_PS_GestorFinanceiro')
      ),
      new PermissionSetAssignment(
        AssigneeId = withCurrency.Id,
        PermissionSetId = permissionSets.get('AXF_PS_GestorFinanceiro')
      ),
      new PermissionSetAssignment(
        AssigneeId = withCurrency.Id,
        PermissionSetId = permissionSets.get('AXF_PS_ReportCurrency')
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
        1,
        context.holders.size(),
        'o titular autorizado e listado'
      );
      Assert.areEqual('Empresa Consolidada', context.holders[0].name);
      // This user holds the consolidation capability but not the presentation-currency grant: the
      // panel must still be presented, without a comparison.
      Assert.areEqual(
        0,
        context.currencies.size(),
        'sem a concessao da moeda de apresentacao nao ha opcoes'
      );
      Assert.isNull(context.defaultReportingIso);
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
      // An id the caller cannot see is an exclusion, never an error: the same answer whether it
      // does not exist or is private.
      ALT_CLS_ConsolidationService.Result invisible = AXF_CLS_CTRL_ConsolidationPanel.consolidate(
        new List<Id>{ '001000000000001AAA' },
        null
      );
      Assert.areEqual(
        1,
        invisible.exclusions.size(),
        'um id invisivel vira exclusao, nao falha'
      );
      Assert.areEqual('NOT_AUTHORIZED', invisible.exclusions[0].reason);
      Assert.areEqual(0, invisible.holders.size());
      Assert.areEqual(0, invisible.totals.size());
    }
  }

  @IsTest
  static void thePresentationCurrencyComesFromItsOwnGrant() {
    System.runAs(byAlias('axf125c')) {
      Test.startTest();
      AXF_CLS_CTRL_ConsolidationPanel.Context context = AXF_CLS_CTRL_ConsolidationPanel.getContext();
      Test.stopTest();

      Assert.isTrue(
        context.canConsolidate,
        'a capability continua vindo do servidor'
      );
      Assert.isTrue(
        context.currencies.size() > 0,
        'com a concessao da moeda as opcoes habilitadas chegam ao LWC'
      );
      Assert.isFalse(
        String.isBlank(context.currencies[0].isoCode),
        'cada opcao carrega o proprio codigo ISO'
      );
      AXF_CLS_ReportCurrencyService currencyService = new AXF_CLS_ReportCurrencyService();
      Assert.areEqual(
        currencyService.effectivePreference(),
        context.defaultReportingIso,
        'a moeda inicial e a preferencia canonica do usuario (AXF-87)'
      );
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
