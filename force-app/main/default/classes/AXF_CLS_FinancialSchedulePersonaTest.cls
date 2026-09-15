/**
 * @description AXF-103 — acesso EFETIVO das duas personas reais na superfície do cronograma
 * (AXF_PS_GestorFinanceiro e AXF_PS_Participante), exercitado com `System.runAs` e describe em
 * modo de usuário.
 *
 * É este teste que responde se o Gestor consegue criar um cronograma — não uma contagem de
 * entradas de FLS. Espelha ALT_CLS_BankInstitutionTest (concessão real de permissão) e
 * AXF_CLS_AccessConfigEffectiveTest (persona real + `isCreateable()`/`isUpdateable()`).
 *
 * Asserts:
 *  - Gestor cria e edita o cronograma, e não exclui;
 *  - Participante lê mas não cria nem edita;
 *  - campos derivados não são editáveis por nenhuma das duas personas;
 *  - a evidência (SDF/SRF/SCH) não é gravável por usuário;
 *  - a chamada direta do Participante ao comando é negada, sem elevação.
 *
 * AXF-103.
 */
@IsTest(isParallel=false)
private class AXF_CLS_FinancialSchedulePersonaTest {
  private static final String GESTOR_PS = 'AXF_PS_GestorFinanceiro';
  private static final String PARTICIPANTE_PS = 'AXF_PS_Participante';

  private static Id businessRecordType() {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get('AXF_Business')
      .getRecordTypeId();
  }

  /** Persona real: profile padrão do Axon mais o permission set que a define. */
  private static User buildUser(String alias, String permissionSetName) {
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ]
    .Id;
    User value = new User(
      ProfileId = profileId,
      LastName = 'AXF103 ' + alias,
      Email = 'axf103.' + alias + '@example.invalid',
      Username = 'axf103.' +
        alias +
        '.' +
        Crypto.getRandomInteger() +
        '@example.invalid',
      Alias = alias.left(8),
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert value;
      insert new PermissionSetAssignment(
        AssigneeId = value.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = :permissionSetName
          LIMIT 1
        ]
        .Id
      );
    }
    return value;
  }

  private static ALT_CLS_FinancialScheduleService.CreateInput request(
    Id accountId
  ) {
    ALT_CLS_FinancialScheduleService.CreateInput value = new ALT_CLS_FinancialScheduleService.CreateInput();
    value.accountId = accountId;
    value.direction = 'DEBIT';
    value.currencyIsoCode = 'BRL';
    value.method = 'INSTALLMENT';
    value.totalInstallments = 6;
    value.firstSequence = 1;
    value.trackingStartSequence = 1;
    value.trackingDueDate = Date.today();
    value.periodMonths = 1;
    value.principal = 12000.00;
    value.legacyGroupKey = 'axf103-persona';
    return value;
  }

  @IsTest
  static void gestorCriaCronogramaEParticipanteNao() {
    User gestor = buildUser('axf103ge', GESTOR_PS);
    User participante = buildUser('axf103pa', PARTICIPANTE_PS);

    Id holderId;
    // O titular é criado pela própria persona que opera: a autoridade de titular (AXF-3) e a
    // visibilidade nativa do registro têm de valer para ela, não para o administrador do teste.
    System.runAs(gestor) {
      Account holder = new Account(
        Name = 'AXF103 persona gestor',
        RecordTypeId = businessRecordType()
      );
      insert holder;
      holderId = holder.Id;

      DescribeSObjectResult root = AXF_OBJ_FinancialSchedule__c.SObjectType.getDescribe();
      System.assertEquals(
        true,
        root.isCreateable(),
        'Gestor cria cronograma (CRUD nativo efetivo)'
      );
      System.assertEquals(true, root.isUpdateable(), 'Gestor edita cronograma');
      System.assertEquals(
        false,
        root.isDeletable(),
        'Nenhuma persona Axon exclui cronograma'
      );

      // Campos derivados não são editáveis pela persona: a trava existe também no metadado, e
      // não só no handler.
      System.assertEquals(
        false,
        AXF_OBJ_FinancialSchedule__c.AXF_FSC_LKP_ActiveDefinition__c.getDescribe()
          .isUpdateable(),
        'Ponteiro para a definição vigente é derivado'
      );
      System.assertEquals(
        false,
        AXF_OBJ_FinancialSchedule__c.AXF_FSC_LKP_ActiveReference__c.getDescribe()
          .isUpdateable(),
        'Ponteiro para a referência vigente é derivado'
      );
      System.assertEquals(
        false,
        AXF_OBJ_FinancialSchedule__c.AXF_FSC_DAT_TerminationDate__c.getDescribe()
          .isUpdateable(),
        'Data de encerramento é derivada'
      );
      System.assertEquals(
        false,
        AXF_OBJ_FinancialSchedule__c.AXF_FSC_BOL_GenerationEnabled__c.getDescribe()
          .isUpdateable(),
        'Chave de geração é derivada'
      );
      System.assertEquals(
        false,
        AXF_OBJ_FinancialTransaction__c.AXF_FTX_NUM_CurrentBasis__c.getDescribe()
          .isUpdateable(),
        'Base corrente da ocorrência é derivada'
      );

      // Evidência imutável: nenhuma persona a grava por DML direta.
      for (
        SObjectType evidence : new List<SObjectType>{
          AXF_OBJ_ScheduleDefinition__c.SObjectType,
          AXF_OBJ_ScheduleReference__c.SObjectType,
          AXF_OBJ_ScheduleChange__c.SObjectType
        }
      ) {
        System.assertEquals(
          false,
          evidence.getDescribe().isCreateable(),
          evidence.getDescribe().getName() +
          ' não é gravável por usuário: a evidência é do serviço'
        );
        System.assertEquals(
          false,
          evidence.getDescribe().isUpdateable(),
          evidence.getDescribe().getName() + ' não é editável por usuário'
        );
        System.assertEquals(
          true,
          evidence.getDescribe().isAccessible(),
          'O Gestor lê a evidência do próprio cronograma'
        );
      }
    }

    ALT_CLS_FinancialScheduleService.CreateInput input = request(holderId);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holderId
    };

    System.runAs(gestor) {
      ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
        input
      );
      System.assertEquals('CREATED', created.outcome, created.message);
      System.assertNotEquals(null, created.scheduleId, 'O cronograma existe');
    }

    System.runAs(participante) {
      System.assertEquals(
        false,
        AXF_OBJ_FinancialSchedule__c.SObjectType.getDescribe().isCreateable(),
        'Participante não cria cronograma'
      );
      System.assertEquals(
        false,
        AXF_OBJ_FinancialSchedule__c.SObjectType.getDescribe().isUpdateable(),
        'Participante não edita cronograma'
      );
      System.assertEquals(
        true,
        AXF_OBJ_FinancialSchedule__c.SObjectType.getDescribe().isAccessible(),
        'Participante lê o cronograma'
      );

      // Chamada direta ao comando: nenhuma elevação, resultado FORBIDDEN e nada gravado.
      ALT_CLS_FinancialScheduleService.CreateResult denied = ALT_CLS_FinancialScheduleService.createSchedule(
        input
      );
      System.assertEquals('FORBIDDEN', denied.outcome, denied.message);
    }

    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c],
      'Só a criação do Gestor existe'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c],
      'Só o recibo autorizado da criação do Gestor existe'
    );
  }
}
