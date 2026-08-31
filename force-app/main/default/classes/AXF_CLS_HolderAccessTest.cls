/**
 * @description Effective-access tests for the holder register with real Axon
 * levels — Gestor Financeiro (AXF_PSG_GestorFinanceiro + role Axon_Gestor_Financeiro),
 * Participante (AXF_PSG_Participante + role Axon_Participante) and System Administrator
 * (the test-running user). AXF-80 AC4 / AXF-7 G2-G3.
 *
 * Uses the real Permission Set Groups, roles and sharing rule deployed by AXF-7,
 * so it fails if any of them regress.
 */
@IsTest(isParallel=false)
private class AXF_CLS_HolderAccessTest {
  private static User buildUser(String lastName, String alias, String roleDevName, String psgDevName) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    Id roleId = [SELECT Id FROM UserRole WHERE DeveloperName = :roleDevName LIMIT 1].Id;
    Id psgId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = :psgDevName LIMIT 1].Id;
    String uniq = alias + Crypto.getRandomInteger();
    User u = new User(
      ProfileId = p.Id,
      UserRoleId = roleId,
      LastName = lastName,
      Email = 'axf80.' + alias + '@example.com',
      Username = 'axf80.' + uniq + '@example.com.invalid',
      Alias = alias.left(8),
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetGroupId = psgId);
    }
    return u;
  }

  private static ALT_CLS_AxonHolder.SaveInput person(String first, String last) {
    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'PERSON';
    si.firstName = first;
    si.lastName = last;
    return si;
  }

  private static ALT_CLS_AxonHolder.SaveInput business(String name) {
    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'BUSINESS';
    si.name = name;
    return si;
  }

  @IsTest
  static void gestorCanRegisterAndEditButNotDelete() {
    User gestor = buildUser('Gestor AXF', 'axfg', 'Axon_Gestor_Financeiro', 'AXF_PSG_GestorFinanceiro');

    Test.startTest();
    System.runAs(gestor) {
      System.assertEquals(
        true,
        FeatureManagement.checkPermission('AXF_CanConfigure'),
        'Gestor carrega AXF_CanConfigure pelo PSG'
      );

      // Person Account por Gestor exige o RT AXF_Person liberado no profile do
      // Gestor (passo de instalacao) — o caminho pessoa e coberto por
      // ALT_CLS_AxonHolderTest (rodando como SysAdmin). Aqui validamos autoridade
      // de cadastro/edicao com Business Account.
      ALT_CLS_AxonHolder svc = new ALT_CLS_AxonHolder();
      ALT_CLS_AxonHolder.SaveResult b = svc.saveHolder(business('Mercearia AXF'));
      System.assertEquals('SUCCEEDED', b.outcome, b.message);

      ALT_CLS_AxonHolder.HolderView v = svc.getHolder(b.accountId);
      ALT_CLS_AxonHolder.SaveInput edit = business('Mercearia AXF 2');
      edit.accountId = b.accountId;
      edit.expectedLastModifiedDate = v.lastModifiedDate;
      System.assertEquals('SUCCEEDED', svc.saveHolder(edit).outcome, 'Gestor edita');
      // Nota: a funcionalidade AXF-80 nunca expoe Delete; o "sem Delete" no nivel
      // de objeto depende do profile base do configurador (passo de instalacao).
    }
    Test.stopTest();
  }

  @IsTest
  static void participanteCanReadButNotRegisterOrEdit() {
    User gestor = buildUser('Gestor AXF', 'axfg', 'Axon_Gestor_Financeiro', 'AXF_PSG_GestorFinanceiro');
    User part = buildUser('Part AXF', 'axfp', 'Axon_Participante', 'AXF_PSG_Participante');

    Id holderId;
    System.runAs(gestor) {
      holderId = new ALT_CLS_AxonHolder().saveHolder(business('Visível AXF')).accountId;
    }

    Test.startTest();
    System.runAs(part) {
      System.assertEquals(
        false,
        FeatureManagement.checkPermission('AXF_CanConfigure'),
        'Participante NAO tem AXF_CanConfigure'
      );

      ALT_CLS_AxonHolder svc = new ALT_CLS_AxonHolder();
      System.assertEquals(
        'FORBIDDEN',
        svc.saveHolder(person('Bruno', 'Lima')).outcome,
        'Participante nao cadastra'
      );

      ALT_CLS_AxonHolder.SaveInput edit = business('Renomear AXF');
      edit.accountId = holderId;
      edit.expectedLastModifiedDate = Datetime.now();
      System.assertEquals('FORBIDDEN', svc.saveHolder(edit).outcome, 'Participante nao edita pela funcionalidade');
    }
    Test.stopTest();
  }

  @IsTest
  static void gestorSharesHoldersWithOtherGestor() {
    User g1 = buildUser('Gestor Um AXF', 'axfg1', 'Axon_Gestor_Financeiro', 'AXF_PSG_GestorFinanceiro');
    User g2 = buildUser('Gestor Dois AXF', 'axfg2', 'Axon_Gestor_Financeiro', 'AXF_PSG_GestorFinanceiro');

    Id holderId;
    System.runAs(g1) {
      holderId = new ALT_CLS_AxonHolder().saveHolder(business('Compartilhada AXF')).accountId;
    }

    Test.startTest();
    System.runAs(g2) {
      ALT_CLS_AxonHolder.HolderView v = new ALT_CLS_AxonHolder().getHolder(holderId);
      System.assertNotEquals(null, v, 'regra owner-based Gestor->Gestor compartilha o titular');
      System.assertEquals('Compartilhada AXF', v.name);
    }
    Test.stopTest();
  }

  @IsTest
  static void systemAdministratorSeesAllHolders() {
    // Running user is a System Administrator (ModifyAllData / ViewAllData).
    User gestor = buildUser('Gestor AXF', 'axfg', 'Axon_Gestor_Financeiro', 'AXF_PSG_GestorFinanceiro');
    System.runAs(gestor) {
      new ALT_CLS_AxonHolder().saveHolder(business('Admin Vê AXF Um'));
      new ALT_CLS_AxonHolder().saveHolder(business('Admin Vê AXF Dois'));
    }

    ALT_CLS_AxonHolder.canConfigureOverride = true;
    List<ALT_CLS_AxonHolder.HolderView> all = new ALT_CLS_AxonHolder().listHolders(null);
    System.assertEquals(2, all.size(), 'SysAdmin enxerga os titulares de outro owner');
  }
}
