@IsTest
private class AXF_CLS_CTRL_DashboardBudgetTest {
  private static final List<String> OBJECTS = new List<String>{
    'AXF_OBJ_Entry__c',
    'AXF_OBJ_Budget__c',
    'AXF_OBJ_Category__c',
    'AXF_OBJ_CreditCard__c'
  };

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User restricted = new User(
      Alias = 'AxfBdg',
      Email = 'AxfBdg@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AxfBdg',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'AxfBdg' + System.currentTimeMillis() + '@example.com'
    );
    insert restricted;
    ALT_CLS_SyncTestUser.create('axfbr', OBJECTS, restricted.Id);
    ALT_CLS_SyncTestUser.create('axfba', OBJECTS);
  }

  private static Account holder(String name, String recordType) {
    Account account = new Account(
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get(recordType)
        .getRecordTypeId()
    );
    if (recordType == 'AXF_Person') {
      account.LastName = name;
    } else {
      account.Name = name;
    }
    insert account;
    return account;
  }

  private static AXF_OBJ_Category__c category(String name) {
    AXF_OBJ_Category__c category = new AXF_OBJ_Category__c(
      Name = name,
      AXF_CAT_PKL_Type__c = 'Expense'
    );
    insert category;
    return category;
  }

  private static AXF_OBJ_Entry__c expense(
    Id holderId,
    Id categoryId,
    String status,
    Decimal amount
  ) {
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = 'Despesa',
      AXF_ENT_MD_Holder__c = holderId,
      AXF_ENT_LKP_Category__c = categoryId,
      AXF_ENT_CUR_Amount__c = amount,
      AXF_ENT_DAT_DueDate__c = Date.today().toStartOfMonth(),
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = status
    );
    if (status == 'Realized') {
      entry.AXF_ENT_DAT_PaymentDate__c = entry.AXF_ENT_DAT_DueDate__c;
    }
    return entry;
  }

  private static AXF_OBJ_Budget__c goal(
    Id holderId,
    Id categoryId,
    Decimal amount,
    Date startMonth
  ) {
    return new AXF_OBJ_Budget__c(
      Name = 'Meta',
      AXF_BDG_MD_Holder__c = holderId,
      AXF_BDG_LKP_Category__c = categoryId,
      AXF_BDG_CUR_Amount__c = amount,
      AXF_BDG_DAT_StartMonth__c = startMonth
    );
  }

  private static ALT_CLS_DashboardBudget.Row line(
    ALT_CLS_DashboardBudget.View view,
    Id categoryId
  ) {
    for (ALT_CLS_DashboardBudget.Row row : view.rows) {
      if (row.categoryId == categoryId) {
        return row;
      }
    }
    return null;
  }

  private static ALT_CLS_DashboardBudget.View view(Id holderId) {
    return AXF_CLS_CTRL_Dashboard.getBudget(holderId, Date.today());
  }

  @IsTest
  static void sumsRealizedPlannedAndGoalByCategory() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Business');
      AXF_OBJ_Category__c food = category('Mercado');
      AXF_OBJ_Category__c fun = category('Lazer');
      Date start = Date.today().toStartOfMonth();
      insert new List<AXF_OBJ_Entry__c>{
        expense(holder.Id, food.Id, 'Realized', 60),
        expense(holder.Id, food.Id, 'Pending', 40),
        expense(holder.Id, fun.Id, 'Realized', 30),
        expense(holder.Id, null, 'Pending', 10)
      };
      Account other = holder('Outro', 'AXF_Person');
      AXF_OBJ_Entry__c income = expense(holder.Id, food.Id, 'Realized', 1000);
      income.AXF_ENT_PKL_Type__c = 'Income';
      AXF_OBJ_Entry__c before = expense(holder.Id, food.Id, 'Realized', 2000);
      before.AXF_ENT_DAT_DueDate__c = start.addDays(-1);
      before.AXF_ENT_DAT_PaymentDate__c = before.AXF_ENT_DAT_DueDate__c;
      AXF_OBJ_Entry__c after = expense(holder.Id, food.Id, 'Realized', 3000);
      after.AXF_ENT_DAT_DueDate__c = start.addMonths(1);
      after.AXF_ENT_DAT_PaymentDate__c = after.AXF_ENT_DAT_DueDate__c;
      insert new List<AXF_OBJ_Entry__c>{
        income,
        before,
        after,
        expense(other.Id, food.Id, 'Realized', 4000)
      };
      insert new List<AXF_OBJ_Budget__c>{
        goal(holder.Id, food.Id, 120, start),
        goal(holder.Id, null, 500, start)
      };
      ALT_CLS_DashboardBudget.View result = view(holder.Id);
      System.assertEquals(140, result.total.planned);
      System.assertEquals(90, result.total.realized);
      System.assertEquals(500, result.total.goal);
      System.assertEquals(100, line(result, food.Id).planned);
      System.assertEquals(60, line(result, food.Id).realized);
      System.assertEquals(120, line(result, food.Id).goal);
      System.assertEquals('Mercado', line(result, food.Id).name);
      System.assertEquals(null, line(result, fun.Id).goal, 'No goal, no bar');
      System.assertEquals('Sem categoria', line(result, null).name);
      System.assertEquals(
        food.Id,
        result.rows[0].categoryId,
        'Sorted by planned'
      );
    }
  }

  @IsTest
  static void picksTheLatestStartedGoalAndHonorsTheEndMonth() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Person');
      AXF_OBJ_Category__c food = category('Mercado');
      AXF_OBJ_Category__c old = category('Antiga');
      Date start = Date.today().toStartOfMonth();
      AXF_OBJ_Budget__c ended = goal(
        holder.Id,
        old.Id,
        77,
        start.addMonths(-6)
      );
      ended.AXF_BDG_DAT_EndMonth__c = start.addMonths(-1);
      insert new List<AXF_OBJ_Budget__c>{
        goal(holder.Id, food.Id, 100, start.addMonths(-4)),
        goal(holder.Id, food.Id, 150, start.addMonths(-1)),
        goal(holder.Id, food.Id, 999, start.addMonths(1)),
        ended
      };
      AXF_OBJ_Category__c last = category('Ultimo mes');
      AXF_OBJ_Budget__c endsNow = goal(
        holder.Id,
        last.Id,
        33,
        start.addMonths(-2)
      );
      endsNow.AXF_BDG_DAT_EndMonth__c = start;
      insert endsNow;
      ALT_CLS_DashboardBudget.View result = view(holder.Id);
      System.assertEquals(
        33,
        line(result, last.Id).goal,
        'Ends in the month shown'
      );
      System.assertEquals(150, line(result, food.Id).goal);
      System.assertEquals(null, line(result, old.Id), 'Ended goal is out');
    }
  }

  @IsTest
  static void allHoldersUsesTheFamilyGoalOrSumsTheHolders() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account first = holder('Primeiro', 'AXF_Business');
      Account second = holder('Segundo', 'AXF_Person');
      Account family = holder('Família', 'AXF_Family');
      AXF_OBJ_Category__c food = category('Mercado');
      AXF_OBJ_Category__c fun = category('Lazer');
      Date start = Date.today().toStartOfMonth();
      insert new List<AXF_OBJ_Budget__c>{
        goal(first.Id, food.Id, 100, start),
        goal(second.Id, food.Id, 50, start),
        goal(first.Id, fun.Id, 30, start),
        goal(second.Id, fun.Id, 20, start),
        goal(family.Id, food.Id, 400, start)
      };
      ALT_CLS_DashboardBudget.View all = view(null);
      System.assertEquals(400, line(all, food.Id).goal, 'Family goal wins');
      System.assertEquals(50, line(all, fun.Id).goal, 'No family goal: sums');
      System.assertEquals(100, line(view(first.Id), food.Id).goal);
      System.assertEquals(null, all.total.goal, 'No total goal anywhere');
      insert new List<AXF_OBJ_Budget__c>{
        goal(first.Id, null, 300, start),
        goal(second.Id, null, 200, start)
      };
      System.assertEquals(
        500,
        view(null).total.goal,
        'Holders total goals sum'
      );
      insert goal(family.Id, null, 800, start);
      System.assertEquals(800, view(null).total.goal, 'Family total goal wins');
    }
  }

  @IsTest
  static void cardPurchaseNotInAnInvoiceIsLeftOut() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = holder('Titular', 'AXF_Business');
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        Name = 'Cartão',
        AXF_CC_MD_Holder__c = holder.Id,
        AXF_CC_PKL_Institution__c = '341'
      );
      insert card;
      AXF_OBJ_Entry__c onCard = expense(holder.Id, null, 'Pending', 80);
      onCard.AXF_ENT_LKP_CreditCard__c = card.Id;
      insert new List<AXF_OBJ_Entry__c>{
        onCard,
        expense(holder.Id, null, 'Pending', 15)
      };
      ALT_CLS_DashboardBudget.View result = view(holder.Id);
      System.assertEquals(15, result.total.planned);
    }
  }

  @IsTest
  static void restrictedUserSeesOnlySharedHoldersAndTheirGoals() {
    User restricted = [SELECT Id FROM User WHERE LastName = 'AxfBdg'];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account shared = holder('Dela', 'AXF_Person');
      Account hidden = holder('Do outro', 'AXF_Business');
      AXF_OBJ_Category__c food = category('Mercado');
      Date start = Date.today().toStartOfMonth();
      insert new List<AXF_OBJ_Entry__c>{
        expense(shared.Id, food.Id, 'Realized', 10),
        expense(hidden.Id, food.Id, 'Realized', 500)
      };
      insert new List<AXF_OBJ_Budget__c>{
        goal(shared.Id, food.Id, 40, start),
        goal(hidden.Id, food.Id, 900, start)
      };
      insert new AccountShare(
        AccountId = shared.Id,
        UserOrGroupId = restricted.Id,
        AccountAccessLevel = 'Edit',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
    }
    System.runAs(restricted) {
      ALT_CLS_DashboardBudget.View result = view(null);
      System.assertEquals(10, result.total.realized);
      System.assertEquals(40, result.rows[0].goal);
    }
  }

  @IsTest
  static void emptyMonthReturnsZeroedTotalAndNoRows() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      ALT_CLS_DashboardBudget.View result = AXF_CLS_CTRL_Dashboard.getBudget(
        null,
        null
      );
      System.assertEquals(0, result.total.planned);
      System.assertEquals(null, result.total.goal);
      System.assertEquals(0, result.rows.size());
    }
  }
}
