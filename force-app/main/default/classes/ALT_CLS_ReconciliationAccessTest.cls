@IsTest
private class ALT_CLS_ReconciliationAccessTest {
  private static final List<String> OBJECTS = new List<String>{
    'AXF_OBJ_Entry__c',
    'AXF_OBJ_BankAccount__c',
    'AXF_OBJ_BankAccountTransaction__c',
    'AXF_OBJ_CreditCard__c',
    'AXF_OBJ_CreditCardInvoice__c',
    'AXF_OBJ_CreditCardTransaction__c'
  };

  // Two restricted users: one without any Axon permission, one with CRUD/FLS on the Axon objects
  // (through the permission set) but without sharing of the holders it did not receive.
  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String name : new List<String>{ 'AxfNoPerm', 'AxfWithPerm' }) {
      users.add(
        new User(
          Alias = name.left(8),
          Email = name + '@example.com',
          EmailEncodingKey = 'UTF-8',
          LastName = name,
          LanguageLocaleKey = 'en_US',
          LocaleSidKey = 'en_US',
          ProfileId = profileId,
          TimeZoneSidKey = 'America/Sao_Paulo',
          Username = name + System.currentTimeMillis() + '@example.com'
        )
      );
    }
    insert users;
    ALT_CLS_SyncTestUser.create('axfac', OBJECTS, users[1].Id);
    ALT_CLS_SyncTestUser.create('axfad', OBJECTS);
  }

  private static User user(String lastName) {
    return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
  }

  private class Data {
    Account sharedHolder;
    Account hiddenHolder;
    AXF_OBJ_BankAccount__c account;
    AXF_OBJ_BankAccountTransaction__c bank;
    AXF_OBJ_CreditCard__c card;
    AXF_OBJ_CreditCardTransaction__c purchase;
    AXF_OBJ_Entry__c entry;
  }

  // Everything is created by the admin running the test; the restricted user only sees what is
  // shared with it.
  private static Data data(Boolean shareWith) {
    Data data = new Data();
    data.sharedHolder = new Account(Name = 'Titular visível');
    data.hiddenHolder = new Account(Name = 'Titular oculto');
    insert new List<Account>{ data.sharedHolder, data.hiddenHolder };
    if (shareWith) {
      insert new AccountShare(
        AccountId = data.sharedHolder.Id,
        UserOrGroupId = user('AxfWithPerm').Id,
        AccountAccessLevel = 'Edit',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
    }
    data.account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = data.sharedHolder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    data.card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = data.sharedHolder.Id,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert data.account;
    insert data.card;
    data.bank = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = data.account.Id,
      AXF_BAT_DAT_Date__c = Date.newInstance(2026, 10, 7),
      AXF_BAT_CUR_Amount__c = -100,
      AXF_BAT_TXT_Description__c = 'Pagamento'
    );
    data.purchase = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = data.card.Id,
      AXF_CCT_DAT_Date__c = Date.newInstance(2026, 10, 7),
      AXF_CCT_CUR_Amount__c = -30,
      AXF_CCT_CUR_AmountBRL__c = -30,
      AXF_CCT_TXT_CurrencyCode__c = 'BRL',
      AXF_CCT_TXT_Description__c = 'Compra'
    );
    insert data.bank;
    insert data.purchase;
    data.entry = entry(data.sharedHolder.Id);
    return data;
  }

  private static AXF_OBJ_Entry__c entry(Id holderId) {
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Lançamento',
      AXF_ENT_MD_Holder__c = holderId,
      AXF_ENT_CUR_Amount__c = 100,
      AXF_ENT_DAT_DueDate__c = Date.newInstance(2026, 10, 7),
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending'
    );
    insert entry;
    return entry;
  }

  @IsTest
  static void userWithoutAnyPermissionIsDeniedByEveryService() {
    Data data = data(false);
    Integer denied = 0;
    System.runAs(user('AxfNoPerm')) {
      for (Integer i = 0; i < 5; i++) {
        try {
          if (i == 0) {
            new ALT_CLS_Reconciliation()
              .reconcile(
                new List<ALT_CLS_Reconciliation.Pair>{
                  new ALT_CLS_Reconciliation.Pair(
                    data.entry.Id,
                    data.bank.Id,
                    null
                  )
                }
              );
          } else if (i == 1) {
            new ALT_CLS_Reconciliation()
              .unreconcile(new List<Id>{ data.entry.Id });
          } else if (i == 2) {
            new ALT_CLS_ReconciliationSuggestions()
              .suggest(
                data.sharedHolder.Id,
                Date.newInstance(2026, 10, 1),
                Date.newInstance(2026, 10, 31)
              );
          } else if (i == 3) {
            new ALT_CLS_ReconciliationActions()
              .ignore(new List<Id>{ data.bank.Id }, null);
          } else {
            new ALT_CLS_ReconciliationActions()
              .createEntries(new List<Id>{ data.bank.Id }, null);
          }
        } catch (QueryException e) {
          denied++;
        }
      }
    }
    System.assertEquals(5, denied);
    System.assertEquals(
      'Pending',
      [
        SELECT AXF_ENT_PKL_Status__c
        FROM AXF_OBJ_Entry__c
        WHERE Id = :data.entry.Id
      ]
      .AXF_ENT_PKL_Status__c
    );
  }

  @IsTest
  static void permittedUserWithoutSharingFindsNothing() {
    Data data = data(false);
    System.runAs(user('AxfWithPerm')) {
      ALT_CLS_Reconciliation.Outcome reconciled = new ALT_CLS_Reconciliation()
        .reconcile(
          new List<ALT_CLS_Reconciliation.Pair>{
            new ALT_CLS_Reconciliation.Pair(data.entry.Id, data.bank.Id, null)
          }
        )[0];
      System.assertEquals(false, reconciled.success);
      System.assert(reconciled.message.contains('sem acesso'));
      System.assert(
        new ALT_CLS_Reconciliation()
            .unreconcile(new List<Id>{ data.entry.Id })[0]
          .message.contains('não encontrado')
      );
      System.assertEquals(
        0,
        new ALT_CLS_ReconciliationSuggestions()
          .suggest(
            data.sharedHolder.Id,
            Date.newInstance(2026, 10, 1),
            Date.newInstance(2026, 10, 31)
          )
          .size()
      );
      System.assert(
        new ALT_CLS_ReconciliationActions()
            .ignore(new List<Id>{ data.bank.Id }, null)[0]
          .message.contains('não encontrada')
      );
      System.assert(
        new ALT_CLS_ReconciliationActions()
            .createEntries(new List<Id>{ data.bank.Id }, null)[0]
          .message.contains('não encontrada')
      );
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE AXF_BAT_PKL_ReconciliationStatus__c IN ('Reconciled', 'Ignored')
        ]
      );
    }
  }

  @IsTest
  static void permittedUserWithSharingCanReconcileUndoIgnoreAndCreate() {
    Data data = data(true);
    System.runAs(user('AxfWithPerm')) {
      ALT_CLS_Reconciliation service = new ALT_CLS_Reconciliation();
      ALT_CLS_Reconciliation.Outcome reconciled = service.reconcile(
        new List<ALT_CLS_Reconciliation.Pair>{
          new ALT_CLS_Reconciliation.Pair(data.entry.Id, data.bank.Id, null)
        }
      )[0];
      System.assertEquals(true, reconciled.success, '' + reconciled.message);
      ALT_CLS_Reconciliation.Outcome undone = service.unreconcile(
        new List<Id>{ data.entry.Id }
      )[0];
      System.assertEquals(true, undone.success, '' + undone.message);
      AXF_OBJ_Entry__c restored = [
        SELECT AXF_ENT_PKL_Status__c, AXF_ENT_LKP_BankAccount__c
        FROM AXF_OBJ_Entry__c
        WHERE Id = :data.entry.Id
      ];
      System.assertEquals('Pending', restored.AXF_ENT_PKL_Status__c);
      System.assertEquals(null, restored.AXF_ENT_LKP_BankAccount__c);
      ALT_CLS_ReconciliationActions.Outcome created = new ALT_CLS_ReconciliationActions()
        .createEntries(null, new List<Id>{ data.purchase.Id })[0];
      System.assertEquals(true, created.success, '' + created.message);
      System.assertEquals(
        1,
        new ALT_CLS_ReconciliationSuggestions()
          .suggest(
            data.sharedHolder.Id,
            Date.newInstance(2026, 10, 1),
            Date.newInstance(2026, 10, 31)
          )
          .size()
      );
      ALT_CLS_ReconciliationActions.Outcome ignored = new ALT_CLS_ReconciliationActions()
        .ignore(new List<Id>{ data.bank.Id }, null)[0];
      System.assertEquals(true, ignored.success, '' + ignored.message);
    }
  }

  // runAs does not let a without sharing class bypass sharing in this org, so the hidden-link case
  // is checked in two halves: the restricted user really has no access to the linking Entry
  // (UserRecordAccess), and the lookup class finds that link regardless of sharing.
  @IsTest
  static void linkLookupSeesAnEntryTheRestrictedUserCannotRead() {
    Data data = data(true);
    Id restrictedId = user('AxfWithPerm').Id;
    Id hiddenEntryId;
    Id ownEntryId = data.entry.Id;
    AXF_OBJ_Entry__c hiddenOwner = entry(data.hiddenHolder.Id);
    hiddenOwner.AXF_ENT_LKP_BankAccountTransaction__c = data.bank.Id;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update hiddenOwner;
    }
    hiddenEntryId = hiddenOwner.Id;
    System.assertEquals(false, canRead(restrictedId, hiddenEntryId));
    System.assertEquals(true, canRead(restrictedId, ownEntryId));
    Set<Id> bankIds = new Set<Id>{ data.bank.Id };
    System.runAs(new User(Id = UserInfo.getUserId())) {
      System.assertEquals(
        bankIds,
        new ALT_CLS_ReconciliationLinks().linked(bankIds, new Set<Id>())
      );
    }
  }

  private static Boolean canRead(Id userId, Id recordId) {
    // UserRecordAccess only takes literal ids in the filter.
    String soql =
      'SELECT RecordId, HasReadAccess FROM UserRecordAccess WHERE UserId = ' +
      quote(userId) +
      ' AND RecordId = ' +
      quote(recordId);
    List<UserRecordAccess> access = Database.query(soql);
    return access[0].HasReadAccess;
  }

  private static String quote(Id value) {
    return String.fromCharArray(new List<Integer>{ 39 }) +
      value +
      String.fromCharArray(new List<Integer>{ 39 });
  }
}
