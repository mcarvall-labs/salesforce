/**
 * @description AXF-6: colaboracao em despesa com escopo limitado — concessao/revogacao pelo
 * titular, leitura redigida e edicao restrita pelo colaborador, revalidacao a cada acesso,
 * idempotencia/versao, revogacao preservando direitos independentes, guards e erros sanitizados.
 */
@IsTest
private class ALT_CLS_SharedExpenseServiceTest {
  private static User owner() {
    return [SELECT Id FROM User WHERE Alias = 'axf6own' LIMIT 1];
  }
  private static User collaborator() {
    return [SELECT Id FROM User WHERE Alias = 'axf6col' LIMIT 1];
  }
  private static User outsider() {
    return [SELECT Id FROM User WHERE Alias = 'axf6out' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User owner = new User(
      Alias = 'axf6own',
      Email = 'axf6own@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Expense Owner',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf6own.' + System.now().getTime() + '@example.invalid'
    );
    User collaborator = owner.clone(false, false, false, false);
    collaborator.Alias = 'axf6col';
    collaborator.LastName = 'Expense Collaborator';
    collaborator.LanguageLocaleKey = 'en_US';
    collaborator.Username =
      'axf6col.' +
      System.now().getTime() +
      '@example.invalid';
    User outsider = owner.clone(false, false, false, false);
    outsider.Alias = 'axf6out';
    outsider.LastName = 'Peer Gestor';
    outsider.Username =
      'axf6out.' +
      System.now().getTime() +
      '@example.invalid';
    insert new List<User>{ owner, collaborator, outsider };

    Map<String, Id> permissionSets = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization',
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (
      String name : new List<String>{
        'AXF_PS_GestorFinanceiro',
        'AXF_PS_FinancialEntry',
        'AXF_PS_Realization'
      }
    ) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = owner.Id,
          PermissionSetId = permissionSets.get(name)
        )
      );
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = outsider.Id,
          PermissionSetId = permissionSets.get(name)
        )
      );
    }
    for (
      String name : new List<String>{
        'AXF_PS_Participante',
        'AXF_PS_FinancialEntry',
        'AXF_PS_Realization'
      }
    ) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = collaborator.Id,
          PermissionSetId = permissionSets.get(name)
        )
      );
    }
    insert assignments;
    PermissionSetGroup psg = [
      SELECT Id, Status
      FROM PermissionSetGroup
      WHERE DeveloperName = 'AXF_PSG_Participante'
      LIMIT 1
    ];
    if (psg.Status != 'Updated') {
      Test.calculatePermissionSetGroup(psg.Id);
    }
    insert new PermissionSetAssignment(
      AssigneeId = collaborator.Id,
      PermissionSetGroupId = psg.Id
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  private static AXF_OBJ_FinancialTransaction__c expense(String key) {
    Account holder = new Account(
      Name = 'Holder ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert holder;
    AXF_OBJ_FinancialTransaction__c result = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holder.Id,
      AXF_FTX_NUM_Magnitude__c = 120,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_DAT_DueDate__c = Date.today().addDays(5),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_TXT_Description__c = 'Internet do escritorio',
      AXF_FTX_EXI_ClientRequestId__c = 'axf6-' + key
    );
    insert result;
    return result;
  }

  private static ALT_CLS_SharedExpenseService.GrantInput grantInput(
    Id expenseId,
    Id userId,
    String permission,
    String key
  ) {
    ALT_CLS_SharedExpenseService.GrantInput input = new ALT_CLS_SharedExpenseService.GrantInput();
    input.financialTransactionId = expenseId;
    input.collaboratorId = userId;
    input.permission = permission;
    input.clientRequestId = key;
    return input;
  }

  private static ALT_CLS_SharedExpenseService.UpdateInput updateInput(
    Id expenseId,
    String description,
    Decimal version,
    String key
  ) {
    ALT_CLS_SharedExpenseService.UpdateInput input = new ALT_CLS_SharedExpenseService.UpdateInput();
    input.financialTransactionId = expenseId;
    input.description = description;
    input.userCategory = 'Escritorio';
    input.expectedVersion = version;
    input.clientRequestId = key;
    return input;
  }

  private static String code(Exception failure) {
    return failure instanceof ALT_CLS_SharedExpenseService.SharedExpenseException
      ? ((ALT_CLS_SharedExpenseService.SharedExpenseException) failure).code
      : failure.getMessage();
  }

  @IsTest
  static void ownerGrantsIdempotentlyAndRevokesWithVersionControl() {
    Id collaboratorId = collaborator().Id;
    System.runAs(owner()) {
      AXF_OBJ_FinancialTransaction__c expense = expense('a');
      ALT_CLS_SharedExpenseService service = new ALT_CLS_SharedExpenseService();
      Test.startTest();
      ALT_CLS_SharedExpenseService.GrantView first = service.share(
        grantInput(expense.Id, collaboratorId, 'VIEW', 'req-1')
      );
      ALT_CLS_SharedExpenseService.GrantView replay = service.share(
        grantInput(expense.Id, collaboratorId, 'EDIT', 'req-1')
      );
      ALT_CLS_SharedExpenseService.GrantView upgraded = service.share(
        grantInput(expense.Id, collaboratorId, 'EDIT', 'req-2')
      );
      Test.stopTest();
      Assert.areEqual('VIEW', first.permission);
      Assert.areEqual('ACTIVE', first.status);
      Assert.areEqual(first.grantId, replay.grantId);
      Assert.areEqual(
        'VIEW',
        replay.permission,
        'Replay da mesma chave nao altera.'
      );
      Assert.areEqual(1, replay.version);
      Assert.areEqual('EDIT', upgraded.permission);
      Assert.areEqual(2, upgraded.version);
      Assert.areEqual(1, service.listGrants(expense.Id).size());
      try {
        service.revoke(upgraded.grantId, 1);
        Assert.fail('Versao obsoleta deve conflitar.');
      } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
        Assert.areEqual('CONFLICT', expected.code);
      }
      ALT_CLS_SharedExpenseService.GrantView revoked = service.revoke(
        upgraded.grantId,
        2
      );
      Assert.areEqual('REVOKED', revoked.status);
      Assert.areEqual(
        'REVOKED',
        service.revoke(upgraded.grantId, null).status,
        'Revogacao repetida e idempotente.'
      );
      try {
        service.share(grantInput(expense.Id, owner().Id, 'VIEW', 'req-3'));
        Assert.fail('Titular nao se concede a si mesmo.');
      } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
        Assert.areEqual('INVALID_INPUT', expected.code);
      }
      Assert.isFalse(
        Database.delete(
            new AXF_OBJ_SharedExpenseGrant__c(Id = first.grantId),
            false
          )
          .isSuccess(),
        'Concessao nao e excluida.'
      );
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_SharedExpenseGrant__c(
              Id = first.grantId,
              AXF_SEG_LKP_Collaborator__c = owner().Id
            ),
            false
          )
          .isSuccess(),
        'Identidade da concessao e imutavel.'
      );
    }
  }

  @IsTest
  static void collaboratorReadsRedactedViewAndEditsOnlyWithEditGrant() {
    Id collaboratorId = collaborator().Id;
    AXF_OBJ_FinancialTransaction__c expense;
    ALT_CLS_SharedExpenseService.GrantView grant;
    System.runAs(owner()) {
      expense = expense('b');
      grant = new ALT_CLS_SharedExpenseService()
        .share(grantInput(expense.Id, collaboratorId, 'VIEW', 'req-b1'));
    }
    System.runAs(collaborator()) {
      ALT_CLS_SharedExpenseService service = new ALT_CLS_SharedExpenseService();
      Test.startTest();
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :expense.Id
        ],
        'Nenhum share do registro e concedido ao colaborador.'
      );
      List<ALT_CLS_SharedExpenseService.SharedView> shared = service.listShared();
      Assert.areEqual(1, shared.size());
      ALT_CLS_SharedExpenseService.SharedView view = service.readShared(
        expense.Id
      );
      Assert.areEqual('Internet do escritorio', view.description);
      Assert.areEqual(120, view.amount);
      Assert.isFalse(view.canEdit);
      String payload = JSON.serialize(view);
      Assert.isFalse(
        payload.contains('Account'),
        'Sem conta de origem no DTO.'
      );
      Assert.isFalse(
        payload.contains('Holder b'),
        'Sem nome do titular no DTO.'
      );
      try {
        service.updateShared(updateInput(expense.Id, 'x', 0, 'u-1'));
        Assert.fail('VIEW nao edita.');
      } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
      Test.stopTest();
    }
    System.runAs(owner()) {
      new ALT_CLS_SharedExpenseService()
        .share(grantInput(expense.Id, collaboratorId, 'EDIT', 'req-b2'));
    }
    System.runAs(collaborator()) {
      ALT_CLS_SharedExpenseService service = new ALT_CLS_SharedExpenseService();
      ALT_CLS_SharedExpenseService.notificationsSent = false;
      ALT_CLS_SharedExpenseService.SharedView updated = service.updateShared(
        updateInput(expense.Id, 'Internet + telefone', 0, 'u-2')
      );
      Assert.areEqual('Internet + telefone', updated.description);
      Assert.areEqual('Escritorio', updated.userCategory);
      Assert.areEqual(1, updated.version);
      Assert.isTrue(
        ALT_CLS_SharedExpenseService.notificationsSent,
        'Titular notificado.'
      );
      ALT_CLS_SharedExpenseService.SharedView replay = service.updateShared(
        updateInput(expense.Id, 'outra coisa', 1, 'u-2')
      );
      Assert.areEqual(
        'Internet + telefone',
        replay.description,
        'Replay da mesma chave nao repete efeito.'
      );
      Assert.areEqual(1, replay.version);
      try {
        service.updateShared(updateInput(expense.Id, 'stale', 0, 'u-3'));
        Assert.fail('Versao obsoleta deve conflitar.');
      } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
        Assert.areEqual('CONFLICT', expected.code);
      }
      ALT_CLS_SharedExpenseService.RealizeInput realize = new ALT_CLS_SharedExpenseService.RealizeInput();
      realize.financialTransactionId = expense.Id;
      realize.amount = 120;
      realize.expectedVersion = 1;
      realize.clientRequestId = 'r-1';
      try {
        service.confirmRealization(realize);
        Assert.fail('Sem acesso ao registro a realizacao AXF-25 e negada.');
      } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
        Assert.areEqual('REALIZATION_DENIED', expected.code);
      }
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
    }
    AXF_OBJ_FinancialTransaction__c stored = [
      SELECT AXF_FTX_TXT_Description__c, AXF_FTX_NUM_Magnitude__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :expense.Id
    ];
    Assert.areEqual('Internet + telefone', stored.AXF_FTX_TXT_Description__c);
    Assert.areEqual(
      120,
      stored.AXF_FTX_NUM_Magnitude__c,
      'Campos financeiros intocados.'
    );
  }

  @IsTest
  static void revocationClosesAccessImmediatelyAndKeepsIndependentRights() {
    Id collaboratorId = collaborator().Id;
    AXF_OBJ_FinancialTransaction__c expense;
    ALT_CLS_SharedExpenseService.GrantView grant;
    System.runAs(owner()) {
      expense = expense('c');
      grant = new ALT_CLS_SharedExpenseService()
        .share(grantInput(expense.Id, collaboratorId, 'EDIT', 'req-c1'));
    }
    AXF_OBJ_FinancialTransaction__c own;
    System.runAs(collaborator()) {
      own = expense('c-own');
      Assert.isTrue(
        new ALT_CLS_SharedExpenseService().readShared(expense.Id).canEdit
      );
    }
    System.runAs(owner()) {
      new ALT_CLS_SharedExpenseService().revoke(grant.grantId, null);
    }
    System.runAs(collaborator()) {
      ALT_CLS_SharedExpenseService service = new ALT_CLS_SharedExpenseService();
      Test.startTest();
      Assert.areEqual(0, service.listShared().size());
      for (Integer i = 0; i < 2; i++) {
        try {
          if (i == 0) {
            service.readShared(expense.Id);
          } else {
            service.updateShared(updateInput(expense.Id, 'late', 0, 'late'));
          }
          Assert.fail('Acesso revogado deve fechar: ' + i);
        } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
          Assert.areEqual('NOT_ACCESSIBLE', expected.code);
        }
      }
      Test.stopTest();
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :own.Id
        ],
        'Direitos independentes do colaborador preservados.'
      );
    }
    Assert.areEqual(
      'Internet do escritorio',
      [
        SELECT AXF_FTX_TXT_Description__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :expense.Id
      ]
      .AXF_FTX_TXT_Description__c
    );
  }

  @IsTest
  static void unauthorizedUsersCannotShareListOrDiscover() {
    Id collaboratorId = collaborator().Id;
    AXF_OBJ_FinancialTransaction__c expense;
    System.runAs(owner()) {
      expense = expense('d');
    }
    System.runAs(collaborator()) {
      try {
        new ALT_CLS_SharedExpenseService()
          .share(grantInput(expense.Id, collaboratorId, 'VIEW', 'x'));
        Assert.fail('Participante nao concede.');
      } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
    System.runAs(outsider()) {
      ALT_CLS_SharedExpenseService service = new ALT_CLS_SharedExpenseService();
      for (Integer i = 0; i < 2; i++) {
        try {
          if (i == 0) {
            service.share(grantInput(expense.Id, collaboratorId, 'VIEW', 'y'));
          } else {
            service.listGrants(expense.Id);
          }
          Assert.fail(
            'Gestor sem acesso ao registro nao concede nem lista: ' + i
          );
        } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
          Assert.areEqual('NOT_ACCESSIBLE', expected.code);
        }
      }
      try {
        service.listShared();
        Assert.fail('Sem capacidade de colaboracao.');
      } catch (ALT_CLS_SharedExpenseService.SharedExpenseException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
  }

  @IsTest
  static void controllerSanitizesErrorsAndExposesCapabilities() {
    Id collaboratorId = collaborator().Id;
    AXF_OBJ_FinancialTransaction__c expense;
    System.runAs(owner()) {
      expense = expense('e');
      Test.startTest();
      AXF_CLS_CTRL_SharedExpense.Capabilities capabilities = AXF_CLS_CTRL_SharedExpense.getCapabilities();
      Assert.isTrue(capabilities.canShare);
      Assert.isFalse(capabilities.canCollaborate);
      List<AXF_CLS_CTRL_SharedExpense.CollaboratorOption> options = AXF_CLS_CTRL_SharedExpense.getCollaborators();
      Boolean listed = false;
      for (AXF_CLS_CTRL_SharedExpense.CollaboratorOption option : options) {
        listed = listed || option.userId == collaboratorId;
      }
      Assert.isTrue(listed, 'Participante elegivel listado.');
      ALT_CLS_SharedExpenseService.GrantView grant = AXF_CLS_CTRL_SharedExpense.share(
        JSON.serialize(grantInput(expense.Id, collaboratorId, 'EDIT', 'ctrl-1'))
      );
      Assert.areEqual(
        1,
        AXF_CLS_CTRL_SharedExpense.getGrants(expense.Id).size()
      );
      try {
        AXF_CLS_CTRL_SharedExpense.share('{"unknown":true}');
        Assert.fail('JSON invalido');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_SharedExpense.revoke(grant.grantId, 99);
        Assert.fail('Conflito');
      } catch (AuraHandledException expected) {
        Assert.areEqual('CONFLICT', expected.getMessage());
      }
      Test.stopTest();
    }
    System.runAs(collaborator()) {
      Assert.isTrue(
        AXF_CLS_CTRL_SharedExpense.getCapabilities().canCollaborate
      );
      Assert.areEqual(1, AXF_CLS_CTRL_SharedExpense.listShared().size());
      ALT_CLS_SharedExpenseService.SharedView view = AXF_CLS_CTRL_SharedExpense.readShared(
        expense.Id
      );
      view = AXF_CLS_CTRL_SharedExpense.updateShared(
        JSON.serialize(
          updateInput(expense.Id, 'via controller', view.version, 'ctrl-2')
        )
      );
      Assert.areEqual('via controller', view.description);
      try {
        AXF_CLS_CTRL_SharedExpense.readShared(null);
        Assert.fail('Entrada ausente');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_SharedExpense.confirmRealization(
          '{"financialTransactionId":"' +
            expense.Id +
            '","amount":10,"clientRequestId":"ctrl-3"}'
        );
        Assert.fail('Realizacao negada');
      } catch (AuraHandledException expected) {
        Assert.areEqual('REALIZATION_DENIED', expected.getMessage());
      }
    }
  }
}
