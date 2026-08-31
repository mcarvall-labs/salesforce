/**
 * @description Effective-access tests for the AXF-7 configuration surface itself
 * (AXF_CLS_CTRL_AccessLevelConfig / ALT_CLS_AxonAccessProvisioning), exercised with
 * REAL Axon levels — Gestor Financeiro and Participante on the stock
 * "Minimum Access - Salesforce" base profile plus the real Permission Set Groups
 * and roles deployed by AXF-7 — and with a plain System Administrator.
 *
 * Complements AXF_CLS_HolderAccessTest (which covers the holder register surface).
 * Contract: ARCHITECTURE-SPINE.md "Fechamento G3" (G3-1, G3-2), "Fechamento G2";
 * AD-5, AD-6. Base-profile decision: Michel, 31/08/2026 (Jira AXF-7 id 10229).
 *
 * Asserts:
 *  - Gestor carries AXF_CanConfigure through the PSG and can read the config surface;
 *  - Participante carries neither the permission nor any configuration capability, and
 *    a direct call to the service is denied (FORBIDDEN), with no elevation;
 *  - a System Administrator is NOT a configurador just by being an admin (no auto-elevation);
 *  - no level grants Delete on Account, nor ViewAll/ModifyAll through the Axon PSGs.
 *
 * AXF-7.
 */
@IsTest(isParallel=false)
private class AXF_CLS_AccessConfigEffectiveTest {
  private static final String GESTOR_ROLE = 'Axon_Gestor_Financeiro';
  private static final String PART_ROLE = 'Axon_Participante';
  private static final String GESTOR_PSG = 'AXF_PSG_GestorFinanceiro';
  private static final String PART_PSG = 'AXF_PSG_Participante';

  private static User buildUser(
    String lastName,
    String alias,
    String roleDevName,
    String psgDevName
  ) {
    // Modelo aprovado (Michel, 31/08): usuarios do Axon ficam no profile padrao
    // "Minimum Access - Salesforce"; todo o acesso operacional vem pelos PSGs.
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ]
    .Id;
    Id roleId = [
      SELECT Id
      FROM UserRole
      WHERE DeveloperName = :roleDevName
      LIMIT 1
    ]
    .Id;
    Id psgId = [
      SELECT Id
      FROM PermissionSetGroup
      WHERE DeveloperName = :psgDevName
      LIMIT 1
    ]
    .Id;
    String uniq = alias + Crypto.getRandomInteger();
    User u = new User(
      ProfileId = profileId,
      UserRoleId = roleId,
      LastName = lastName,
      Email = 'axf7.' + alias + '@example.com',
      Username = 'axf7.' + uniq + '@example.com.invalid',
      Alias = alias.left(8),
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetGroupId = psgId
      );
    }
    return u;
  }

  private static void calculateGroups() {
    for (PermissionSetGroup psg : [
      SELECT Id, Status
      FROM PermissionSetGroup
      WHERE DeveloperName IN :new Set<String>{ GESTOR_PSG, PART_PSG }
    ]) {
      if (psg.Status != 'Updated') {
        Test.calculatePermissionSetGroup(psg.Id);
      }
    }
  }

  @IsTest
  static void gestorHasConfigurationAuthorityButNoDelete() {
    User gestor = buildUser('Gestor AXF7', 'axf7g', GESTOR_ROLE, GESTOR_PSG);
    calculateGroups();

    Test.startTest();
    System.runAs(gestor) {
      System.assertEquals(
        true,
        FeatureManagement.checkPermission('AXF_CanConfigure'),
        'Gestor carrega AXF_CanConfigure pelo PSG'
      );
      System.assertEquals(
        true,
        AXF_CLS_CTRL_AccessLevelConfig.canConfigure(),
        'a superficie de configuracao reconhece o Gestor como configurador'
      );
      // getEligibleUsers nao lanca e devolve pelo menos o proprio Gestor
      System.assert(
        !AXF_CLS_CTRL_AccessLevelConfig.getEligibleUsers().isEmpty(),
        'Gestor autorizado enxerga a lista de usuarios'
      );

      DescribeSObjectResult acc = Account.SObjectType.getDescribe();
      System.assertEquals(
        false,
        acc.isDeletable(),
        'nenhum nivel Axon concede Delete em Account'
      );
      System.assertEquals(true, acc.isCreateable(), 'Gestor cadastra Account');
      System.assertEquals(true, acc.isUpdateable(), 'Gestor edita Account');
    }
    Test.stopTest();
  }

  @IsTest
  static void participanteHasNoConfigurationCapabilityAndIsDeniedDirectly() {
    User gestor = buildUser('Gestor AXF7', 'axf7g', GESTOR_ROLE, GESTOR_PSG);
    User part = buildUser('Part AXF7', 'axf7p', PART_ROLE, PART_PSG);
    calculateGroups();

    Test.startTest();
    System.runAs(part) {
      System.assertEquals(
        false,
        FeatureManagement.checkPermission('AXF_CanConfigure'),
        'Participante NAO carrega AXF_CanConfigure'
      );
      System.assertEquals(
        false,
        AXF_CLS_CTRL_AccessLevelConfig.canConfigure(),
        'a superficie de configuracao nega o Participante'
      );
      System.assertEquals(
        0,
        AXF_CLS_CTRL_AccessLevelConfig.getEligibleUsers().size(),
        'sem autoridade -> lista vazia, nao excecao (UI mostra FORBIDDEN)'
      );

      // Chamada direta a operacao: nenhuma elevacao, resultado FORBIDDEN.
      ALT_CLS_AxonAccessProvisioning.Result r = new ALT_CLS_AxonAccessProvisioning()
        .applyAccessLevel(
          gestor.Id,
          ALT_CLS_AxonAccessProvisioning.Tier.PARTICIPANTE
        );
      System.assertEquals(
        ALT_CLS_AxonAccessProvisioning.Outcome.FORBIDDEN,
        r.outcome,
        'chamada direta pelo Participante e negada'
      );

      System.assertEquals(
        false,
        Account.SObjectType.getDescribe().isDeletable(),
        'Participante nao tem Delete em Account'
      );
      System.assertEquals(
        false,
        Account.SObjectType.getDescribe().isCreateable(),
        'Participante nao cadastra Account'
      );
    }
    Test.stopTest();

    // Nenhuma atribuicao Axon foi criada para o alvo pela tentativa negada.
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :gestor.Id AND PermissionSetGroupId != NULL
      ],
      'o Gestor mantem exatamente o seu PSG; a tentativa negada nao adicionou nada'
    );
  }

  @IsTest
  static void systemAdministratorIsNotAConfiguradorByDefault() {
    // O usuario que roda o teste e System Administrator (ViewAllData/ModifyAllData).
    Test.startTest();
    System.assertEquals(
      false,
      FeatureManagement.checkPermission('AXF_CanConfigure'),
      'ser System Administrator nao concede AXF_CanConfigure (sem autoelevacao)'
    );
    System.assertEquals(
      false,
      AXF_CLS_CTRL_AccessLevelConfig.canConfigure(),
      'admin sem a Custom Permission nao e configurador'
    );
    Test.stopTest();
  }

  @IsTest
  static void axonPsgsGrantNoGlobalAdminPrivileges() {
    Set<Id> psgIds = new Map<Id, PermissionSetGroup>(
        [
          SELECT Id
          FROM PermissionSetGroup
          WHERE DeveloperName IN :new Set<String>{ GESTOR_PSG, PART_PSG }
        ]
      )
      .keySet();

    for (PermissionSet ps : [
      SELECT
        PermissionsModifyAllData,
        PermissionsViewAllData,
        PermissionsManageUsers,
        PermissionSetGroup.DeveloperName
      FROM PermissionSet
      WHERE PermissionSetGroupId IN :psgIds
    ]) {
      String name = ps.PermissionSetGroup.DeveloperName;
      System.assertEquals(
        false,
        ps.PermissionsModifyAllData,
        name + ': sem ModifyAllData'
      );
      System.assertEquals(
        false,
        ps.PermissionsViewAllData,
        name + ': sem ViewAllData'
      );
      System.assertEquals(
        false,
        ps.PermissionsManageUsers,
        name + ': sem Manage Users'
      );
    }
  }
}
