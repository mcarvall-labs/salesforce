@IsTest
private class ALT_CLS_BudgetTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfbdg',
      new List<String>{ 'AXF_OBJ_Budget__c', 'AXF_OBJ_Category__c' }
    );
  }

  private static User actor() {
    return new User(Id = UserInfo.getUserId());
  }

  private static AXF_OBJ_Budget__c budget(Id holderId) {
    return new AXF_OBJ_Budget__c(
      Name = 'Meta',
      AXF_BDG_MD_Holder__c = holderId,
      AXF_BDG_CUR_Amount__c = 500,
      AXF_BDG_DAT_StartMonth__c = Date.newInstance(2026, 10, 1)
    );
  }

  private static Id holder() {
    Account holder = new Account(Name = 'Titular');
    insert holder;
    return holder.Id;
  }

  private static String error(AXF_OBJ_Budget__c record) {
    Database.SaveResult result = Database.insert(record, false);
    System.assert(!result.isSuccess(), 'Insert should have been blocked');
    return result.getErrors()[0].getMessage();
  }

  // The validation messages are translated (pt-BR); the test user's language decides which one
  // comes back.
  private static void assertMessage(String actual, String en, String pt) {
    System.assert(
      actual.contains(en) || actual.contains(pt),
      'Unexpected message: ' + actual
    );
  }

  @IsTest
  static void savesWithoutCategoryAndEndMonth() {
    System.runAs(actor()) {
      AXF_OBJ_Budget__c record = budget(holder());
      insert record;
      AXF_OBJ_Budget__c saved = [
        SELECT AXF_BDG_LKP_Category__c, AXF_BDG_DAT_EndMonth__c
        FROM AXF_OBJ_Budget__c
        WHERE Id = :record.Id
      ];
      System.assertEquals(null, saved.AXF_BDG_LKP_Category__c);
      System.assertEquals(null, saved.AXF_BDG_DAT_EndMonth__c);
    }
  }

  @IsTest
  static void acceptsEndMonthEqualToStartMonth() {
    System.runAs(actor()) {
      AXF_OBJ_Budget__c record = budget(holder());
      record.AXF_BDG_DAT_EndMonth__c = record.AXF_BDG_DAT_StartMonth__c;
      insert record;
      System.assertNotEquals(null, record.Id);
    }
  }

  @IsTest
  static void keepsCategoryAndBlocksItsDeletion() {
    System.runAs(actor()) {
      AXF_OBJ_Category__c category = new AXF_OBJ_Category__c(
        Name = 'Mercado',
        AXF_CAT_PKL_Type__c = 'Expense'
      );
      insert category;
      AXF_OBJ_Budget__c record = budget(holder());
      record.AXF_BDG_LKP_Category__c = category.Id;
      insert record;
      System.assertEquals(
        category.Id,
        [
          SELECT AXF_BDG_LKP_Category__c
          FROM AXF_OBJ_Budget__c
          WHERE Id = :record.Id
        ]
        .AXF_BDG_LKP_Category__c
      );
      Database.DeleteResult result = Database.delete(category, false);
      System.assert(!result.isSuccess(), 'Category in use must not be deleted');
    }
  }

  @IsTest
  static void blocksNonPositiveAmount() {
    System.runAs(actor()) {
      AXF_OBJ_Budget__c record = budget(holder());
      record.AXF_BDG_CUR_Amount__c = 0;
      assertMessage(error(record), 'greater than zero', 'maior que zero');
    }
  }

  @IsTest
  static void blocksEndBeforeStart() {
    System.runAs(actor()) {
      AXF_OBJ_Budget__c record = budget(holder());
      record.AXF_BDG_DAT_EndMonth__c = Date.newInstance(2026, 9, 1);
      assertMessage(
        error(record),
        'before the start month',
        'anterior ao mês inicial'
      );
    }
  }

  @IsTest
  static void blocksDatesOutsideFirstDay() {
    System.runAs(actor()) {
      AXF_OBJ_Budget__c record = budget(holder());
      record.AXF_BDG_DAT_StartMonth__c = Date.newInstance(2026, 10, 15);
      assertMessage(error(record), 'first day', 'primeiro dia');
      record = budget(holder());
      record.AXF_BDG_DAT_EndMonth__c = Date.newInstance(2026, 12, 20);
      assertMessage(error(record), 'first day', 'primeiro dia');
    }
  }

  @IsTest
  static void blocksNonBrlCurrency() {
    System.runAs(actor()) {
      AXF_OBJ_Budget__c record = budget(holder());
      record.put('CurrencyIsoCode', 'USD');
      System.assert(error(record).contains('BRL'));
    }
  }
}
