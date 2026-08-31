/**
 * @description Tests for ALT_CLS_AxonHolder — cadastro e manutencao de titulares
 * (Person Account / Business Account). AXF-80.
 *
 * Covers: pessoa, empresa, edicao permitida, negacao para usuario sem autoridade,
 * repeticao / nome duplicado, edicao obsoleta (conflito de concorrencia), e a
 * ausencia de User / vinculo criado implicitamente.
 */
@IsTest(isParallel=false)
private class ALT_CLS_AxonHolderTest {
  private static ALT_CLS_AxonHolder authorizedService() {
    ALT_CLS_AxonHolder.canConfigureOverride = true;
    return new ALT_CLS_AxonHolder();
  }

  private static ALT_CLS_AxonHolder.SaveInput personInput(String first, String last) {
    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'PERSON';
    si.firstName = first;
    si.lastName = last;
    return si;
  }

  private static ALT_CLS_AxonHolder.SaveInput businessInput(String name) {
    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'BUSINESS';
    si.name = name;
    return si;
  }

  @IsTest
  static void createsPersonHolderWithoutSideEffects() {
    Integer usersBefore = [SELECT COUNT() FROM User];
    ALT_CLS_AxonHolder svc = authorizedService();

    Test.startTest();
    ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(personInput('Ana', 'Souza'));
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.outcome, r.message);
    System.assertNotEquals(null, r.accountId, 'holder Id returned');

    Account saved = [
      SELECT Id, IsPersonAccount, FirstName, LastName, OwnerId, RecordType.DeveloperName
      FROM Account
      WHERE Id = :r.accountId
    ];
    System.assertEquals(true, saved.IsPersonAccount, 'pessoa = Person Account');
    System.assertEquals('AXF_Person', saved.RecordType.DeveloperName);
    System.assertEquals('Souza', saved.LastName);
    System.assertEquals(UserInfo.getUserId(), saved.OwnerId, 'owner = configurador');
    System.assertEquals(usersBefore, [SELECT COUNT() FROM User], 'no user created');
  }

  @IsTest
  static void createsBusinessHolder() {
    ALT_CLS_AxonHolder svc = authorizedService();

    Test.startTest();
    ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(businessInput('Padaria do Bairro LTDA'));
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.outcome, r.message);
    Account saved = [
      SELECT IsPersonAccount, Name, RecordType.DeveloperName FROM Account WHERE Id = :r.accountId
    ];
    System.assertEquals(false, saved.IsPersonAccount);
    System.assertEquals('AXF_Business', saved.RecordType.DeveloperName);
    System.assertEquals('Padaria do Bairro LTDA', saved.Name);
  }

  @IsTest
  static void rejectsCreateWhenCallerCannotConfigure() {
    ALT_CLS_AxonHolder.canConfigureOverride = false;
    ALT_CLS_AxonHolder svc = new ALT_CLS_AxonHolder();

    ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(personInput('Bruno', 'Lima'));

    System.assertEquals('FORBIDDEN', r.outcome);
    System.assertEquals(0, [SELECT COUNT() FROM Account WHERE LastName = 'Lima'], 'nothing created');
  }

  @IsTest
  static void rejectsInvalidType() {
    ALT_CLS_AxonHolder svc = authorizedService();
    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'GARBAGE';
    si.lastName = 'X';

    ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(si);

    System.assertEquals('INVALID', r.outcome);
    System.assert(r.invalidFields.contains('type'), 'flags the type field');
  }

  @IsTest
  static void rejectsPersonWithoutLastName() {
    ALT_CLS_AxonHolder svc = authorizedService();

    ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(personInput('Só Nome', '   '));

    System.assertEquals('INVALID', r.outcome);
    System.assert(r.invalidFields.contains('lastName'));
  }

  @IsTest
  static void rejectsBusinessWithoutName() {
    ALT_CLS_AxonHolder svc = authorizedService();

    ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(businessInput(null));

    System.assertEquals('INVALID', r.outcome);
    System.assert(r.invalidFields.contains('name'));
  }

  @IsTest
  static void warnsOnDuplicateNameThenCreatesWhenConfirmed() {
    ALT_CLS_AxonHolder svc = authorizedService();
    svc.saveHolder(businessInput('Mercado Central'));

    ALT_CLS_AxonHolder.SaveResult warn = svc.saveHolder(businessInput('  mercado   central '));
    System.assertEquals('DUPLICATE_WARNING', warn.outcome, 'same normalized name warns');
    System.assertEquals(1, warn.possibleDuplicates.size());
    System.assertEquals(null, warn.accountId, 'not created yet');

    ALT_CLS_AxonHolder.SaveInput confirmed = businessInput('Mercado Central');
    confirmed.confirmedDespiteDuplicates = true;
    ALT_CLS_AxonHolder.SaveResult ok = svc.saveHolder(confirmed);
    System.assertEquals('SUCCEEDED', ok.outcome);
    System.assertEquals(2, [SELECT COUNT() FROM Account WHERE Name = 'Mercado Central'], 'no auto-merge');
  }

  @IsTest
  static void editsDescriptiveDataKeepingOwnership() {
    ALT_CLS_AxonHolder svc = authorizedService();
    ALT_CLS_AxonHolder.SaveResult created = svc.saveHolder(personInput('Carla', 'Dias'));
    ALT_CLS_AxonHolder.HolderView v = svc.getHolder(created.accountId);
    Id ownerBefore = v.ownerId;

    ALT_CLS_AxonHolder.SaveInput edit = personInput('Carla', 'Dias Nogueira');
    edit.accountId = created.accountId;
    edit.expectedLastModifiedDate = v.lastModifiedDate;

    Test.startTest();
    ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(edit);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.outcome, r.message);
    Account after = [SELECT LastName, OwnerId FROM Account WHERE Id = :created.accountId];
    System.assertEquals('Dias Nogueira', after.LastName);
    System.assertEquals(ownerBefore, after.OwnerId, 'edit never changes owner');
  }

  @IsTest
  static void rejectsStaleEdit() {
    ALT_CLS_AxonHolder svc = authorizedService();
    ALT_CLS_AxonHolder.SaveResult created = svc.saveHolder(businessInput('Oficina X'));

    ALT_CLS_AxonHolder.SaveInput edit = businessInput('Oficina Y');
    edit.accountId = created.accountId;
    edit.expectedLastModifiedDate = Datetime.newInstance(2000, 1, 1); // stale

    ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(edit);

    System.assertEquals('CONFLICT', r.outcome);
    System.assertEquals('Oficina X', [SELECT Name FROM Account WHERE Id = :created.accountId].Name);
  }

  @IsTest
  static void rejectsEditWithoutExpectedTimestamp() {
    ALT_CLS_AxonHolder svc = authorizedService();
    ALT_CLS_AxonHolder.SaveResult created = svc.saveHolder(businessInput('Loja A'));

    ALT_CLS_AxonHolder.SaveInput edit = businessInput('Loja B');
    edit.accountId = created.accountId; // expectedLastModifiedDate left null

    System.assertEquals('CONFLICT', svc.saveHolder(edit).outcome);
  }

  @IsTest
  static void updateReportsNotFoundForUnknownRecord() {
    ALT_CLS_AxonHolder svc = authorizedService();

    ALT_CLS_AxonHolder.SaveInput edit = businessInput('x');
    edit.accountId = '001000000000000AAA'; // well-formed Account Id that does not exist
    edit.expectedLastModifiedDate = Datetime.now();

    System.assertEquals('NOT_FOUND', svc.saveHolder(edit).outcome);
  }

  @IsTest
  static void listAndGetHolderFilterToHolders() {
    ALT_CLS_AxonHolder svc = authorizedService();
    svc.saveHolder(personInput('Diego', 'Alvarez'));
    svc.saveHolder(businessInput('Transportes Delta'));

    List<ALT_CLS_AxonHolder.HolderView> all = svc.listHolders(null);
    System.assertEquals(2, all.size(), 'both created holders listed');

    List<ALT_CLS_AxonHolder.HolderView> filtered = svc.listHolders('Delta');
    System.assertEquals(1, filtered.size());
    System.assertEquals('BUSINESS', filtered[0].type);

    System.assertEquals(null, svc.getHolder(null));
  }

  @IsTest
  static void standardUserWithoutAuthorityIsDeniedOnSave() {
    User standard = buildStandardUser();

    System.runAs(standard) {
      ALT_CLS_AxonHolder svc = new ALT_CLS_AxonHolder(); // no override => real permission check
      ALT_CLS_AxonHolder.SaveResult r = svc.saveHolder(personInput('Edu', 'Faria'));
      System.assertEquals('FORBIDDEN', r.outcome, 'no AXF_CanConfigure => denied');
    }
  }

  private static User buildStandardUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User u = new User(
      ProfileId = p.Id,
      LastName = 'Tester',
      Email = 'axf80.tester@example.com',
      Username = 'axf80.tester.' + Crypto.getRandomInteger() + '@example.com.invalid',
      Alias = 'axf80t',
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
    }
    return u;
  }
}
