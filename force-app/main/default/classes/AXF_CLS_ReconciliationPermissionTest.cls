@IsTest
private class AXF_CLS_ReconciliationPermissionTest {
  private static final Date DUE = Date.newInstance(2026, 10, 10);

  // A user that only has the real Axon - Usuário permission set (no helper permission set), so the
  // test fails when the set misses an object, a field or an Apex class the screen needs.
  private static User axonUser() {
    User user = new User(
      Alias = 'axfusr',
      Email = 'axfusr@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AxonUser',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfusr' + System.currentTimeMillis() + '@example.com'
    );
    insert user;
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'AXF_PS_Usuario'
        LIMIT 1
      ]
      .Id
    );
    return user;
  }

  private class Data {
    Account holder;
    AXF_OBJ_BankAccount__c account;
    AXF_OBJ_CreditCard__c card;
    AXF_OBJ_Entry__c entry;
    AXF_OBJ_BankAccountTransaction__c bank;
    AXF_OBJ_BankAccountTransaction__c transfer;
    AXF_OBJ_CreditCardTransaction__c purchase;
  }

  private static Data data(User user) {
    Data data = new Data();
    data.holder = new Account(Name = 'Titular');
    insert data.holder;
    insert new AccountShare(
      AccountId = data.holder.Id,
      UserOrGroupId = user.Id,
      AccountAccessLevel = 'Edit',
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None'
    );
    data.account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = data.holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    data.card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = data.holder.Id,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert data.account;
    insert data.card;
    data.entry = new AXF_OBJ_Entry__c(
      Name = 'Conta de luz',
      AXF_ENT_MD_Holder__c = data.holder.Id,
      AXF_ENT_CUR_Amount__c = 100,
      AXF_ENT_DAT_DueDate__c = DUE,
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending'
    );
    insert data.entry;
    data.bank = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = data.account.Id,
      AXF_BAT_DAT_Date__c = DUE,
      AXF_BAT_CUR_Amount__c = -100,
      AXF_BAT_TXT_Description__c = 'Pagamento'
    );
    data.transfer = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = data.account.Id,
      AXF_BAT_DAT_Date__c = DUE,
      AXF_BAT_CUR_Amount__c = -500,
      AXF_BAT_TXT_Description__c = 'Transferência'
    );
    data.purchase = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = data.card.Id,
      AXF_CCT_DAT_Date__c = DUE,
      AXF_CCT_CUR_Amount__c = -30,
      AXF_CCT_CUR_AmountBRL__c = -30,
      AXF_CCT_TXT_CurrencyCode__c = 'BRL',
      AXF_CCT_TXT_Description__c = 'Compra'
    );
    insert data.bank;
    insert data.transfer;
    insert data.purchase;
    return data;
  }

  @IsTest
  static void permissionSetGrantsTheControllersAndTheTab() {
    Set<String> classes = new Set<String>();
    for (SetupEntityAccess access : [
      SELECT SetupEntityId
      FROM SetupEntityAccess
      WHERE Parent.Name = 'AXF_PS_Usuario' AND SetupEntityType = 'ApexClass'
    ]) {
      classes.add(access.SetupEntityId);
    }
    List<ApexClass> controllers = [
      SELECT Name
      FROM ApexClass
      WHERE
        Name IN (
          'AXF_CLS_CTRL_Reconciliation',
          'AXF_CLS_CTRL_PluggySync',
          'AXF_CLS_CTRL_InvoiceTransactions'
        )
    ];
    System.assertEquals(3, controllers.size());
    for (ApexClass apexClass : controllers) {
      System.assert(
        classes.contains(apexClass.Id),
        apexClass.Name + ' is not granted'
      );
    }
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM PermissionSetTabSetting
        WHERE
          Parent.Name = 'AXF_PS_Usuario'
          AND Name = 'AXF_CT_Reconciliation'
          AND Visibility = 'DefaultOn'
      ]
    );
  }

  @IsTest
  static void userWithTheAxonPermissionSetRunsTheWholeReconciliationScreen() {
    User user = axonUser();
    Data data = data(user);
    System.runAs(user) {
      System.assertEquals(1, AXF_CLS_CTRL_Reconciliation.getHolders().size());
      AXF_CLS_CTRL_Reconciliation.ScreenData screen = AXF_CLS_CTRL_Reconciliation.getData(
        data.holder.Id,
        '2026-10'
      );
      System.assertEquals(1, screen.entries.size());
      System.assertEquals(3, screen.transactions.size());
      System.assertEquals(1, screen.suggestions.size());

      AXF_CLS_CTRL_Reconciliation.PairInput pair = new AXF_CLS_CTRL_Reconciliation.PairInput();
      pair.entryId = data.entry.Id;
      pair.bankTransactionId = data.bank.Id;
      AXF_CLS_CTRL_Reconciliation.OutcomeView reconciled = AXF_CLS_CTRL_Reconciliation.reconcile(
        new List<AXF_CLS_CTRL_Reconciliation.PairInput>{ pair }
      )[0];
      System.assertEquals(true, reconciled.success, '' + reconciled.message);
      AXF_CLS_CTRL_Reconciliation.OutcomeView undone = AXF_CLS_CTRL_Reconciliation.unreconcile(
        new List<Id>{ data.entry.Id }
      )[0];
      System.assertEquals(true, undone.success, '' + undone.message);
      AXF_CLS_CTRL_Reconciliation.OutcomeView ignored = AXF_CLS_CTRL_Reconciliation.ignoreTransactions(
        new List<Id>{ data.transfer.Id },
        null
      )[0];
      System.assertEquals(true, ignored.success, '' + ignored.message);
      AXF_CLS_CTRL_Reconciliation.OutcomeView created = AXF_CLS_CTRL_Reconciliation.createEntries(
        null,
        new List<Id>{ data.purchase.Id }
      )[0];
      System.assertEquals(true, created.success, '' + created.message);
    }
  }

  @IsTest
  static void userWithoutTheSharingOfTheHolderSeesNothing() {
    User user = axonUser();
    Data data = data(user);
    delete [
      SELECT Id
      FROM AccountShare
      WHERE UserOrGroupId = :user.Id AND RowCause = 'Manual'
    ];
    System.runAs(user) {
      System.assertEquals(0, AXF_CLS_CTRL_Reconciliation.getHolders().size());
      System.assertEquals(
        0,
        AXF_CLS_CTRL_Reconciliation.getData(data.holder.Id, '2026-10')
          .entries.size()
      );
    }
  }

  // Least privilege: the set updates transactions but never creates or deletes them, and the
  // invoice link of an Entry stays read only.
  @IsTest
  static void permissionSetDoesNotGrantMoreThanTheScreenNeeds() {
    User user = axonUser();
    System.runAs(user) {
      for (
        Schema.DescribeSObjectResult describe : new List<Schema.DescribeSObjectResult>{
          AXF_OBJ_BankAccountTransaction__c.SObjectType.getDescribe(),
          AXF_OBJ_CreditCardTransaction__c.SObjectType.getDescribe()
        }
      ) {
        System.assertEquals(true, describe.isUpdateable(), describe.getName());
        System.assertEquals(false, describe.isCreateable(), describe.getName());
        System.assertEquals(false, describe.isDeletable(), describe.getName());
      }
      Schema.DescribeFieldResult invoice = AXF_OBJ_Entry__c.AXF_ENT_LKP_Invoice__c.getDescribe();
      System.assertEquals(true, invoice.isAccessible());
      System.assertEquals(false, invoice.isUpdateable());
      System.assertEquals(
        true,
        AXF_OBJ_Entry__c.AXF_ENT_LKP_BankAccountTransaction__c.getDescribe()
          .isUpdateable()
      );
    }
  }

  @IsTest
  static void userWithoutThePermissionSetIsDenied() {
    User user = new User(
      Alias = 'axfnops',
      Email = 'axfnops@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoPermissionSet',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfnops' + System.currentTimeMillis() + '@example.com'
    );
    insert user;
    System.runAs(user) {
      try {
        AXF_CLS_CTRL_Reconciliation.getHolders();
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }
}
