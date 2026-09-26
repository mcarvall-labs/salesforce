/**
 * @description Covers ALT_CLS_CategoryLookup and its thin controller AXF_CLS_CTRL_CategoryLookup.
 */
@IsTest
private class AXF_CLS_CTRL_CategoryLookupTest {
  private static final String USER_KEY = 'catlookup';

  @TestSetup
  static void setupData() {
    AXF_CLS_AccountCardTestFactory.createUser(USER_KEY, false);

    AXF_OBJ_Category__c housing = AXF_CLS_AccountCardTestFactory.newCategory(
      'Moradia',
      'AXF_CAT_RT_Expense',
      null
    );
    AXF_OBJ_Category__c leisure = AXF_CLS_AccountCardTestFactory.newCategory(
      'Lazer',
      'AXF_CAT_RT_Expense',
      null
    );
    AXF_OBJ_Category__c salary = AXF_CLS_AccountCardTestFactory.newCategory(
      'Salário',
      'AXF_CAT_RT_Revenue',
      null
    );
    insert new List<AXF_OBJ_Category__c>{ housing, leisure, salary };
    insert new List<AXF_OBJ_Category__c>{
      AXF_CLS_AccountCardTestFactory.newCategory(
        'Aluguel',
        'AXF_CAT_RT_Expense',
        housing.Id
      ),
      AXF_CLS_AccountCardTestFactory.newCategory(
        'Condomínio',
        'AXF_CAT_RT_Expense',
        housing.Id
      )
    };
  }

  private static User testUser() {
    return AXF_CLS_AccountCardTestFactory.getUser(USER_KEY);
  }

  private static AXF_CLS_CTRL_CategoryLookup.CategoryCreationDTO dto(
    String name,
    String parentId,
    String recordType
  ) {
    AXF_CLS_CTRL_CategoryLookup.CategoryCreationDTO dto = new AXF_CLS_CTRL_CategoryLookup.CategoryCreationDTO();
    dto.name = name;
    dto.parentId = parentId;
    dto.recordTypeDeveloperName = recordType;
    return dto;
  }

  private static String serviceError(
    ALT_CLS_CategoryLookup.CategoryCreationRequest req
  ) {
    try {
      new ALT_CLS_CategoryLookup().createCategory(req);
    } catch (IllegalArgumentException e) {
      return e.getMessage();
    }
    return null;
  }

  private static ALT_CLS_CategoryLookup.CategoryCreationRequest request(
    String name,
    String parentId,
    String recordType
  ) {
    ALT_CLS_CategoryLookup.CategoryCreationRequest req = new ALT_CLS_CategoryLookup.CategoryCreationRequest();
    req.name = name;
    req.parentId = parentId;
    req.recordTypeDeveloperName = recordType;
    return req;
  }

  @IsTest
  static void optionsExposeOnlyLeafCategoriesWithCombinedLabel() {
    List<AXF_CLS_CTRL_CategoryLookup.CategoryOptionDTO> options;
    List<AXF_CLS_CTRL_CategoryLookup.CategoryOptionDTO> topLevel;
    System.runAs(testUser()) {
      Test.startTest();
      options = AXF_CLS_CTRL_CategoryLookup.getCategoryOptions(
        'AXF_CAT_RT_Expense'
      );
      topLevel = AXF_CLS_CTRL_CategoryLookup.getTopLevelCategoryOptions(
        'AXF_CAT_RT_Expense'
      );
      Test.stopTest();
    }

    List<String> labels = new List<String>();
    for (AXF_CLS_CTRL_CategoryLookup.CategoryOptionDTO option : options) {
      labels.add(option.displayLabel);
    }
    Assert.areEqual(
      new List<String>{ 'Lazer', 'Moradia > Aluguel', 'Moradia > Condomínio' },
      labels
    );
    Assert.areEqual(2, topLevel.size());
    Assert.areEqual('Lazer', topLevel[0].displayLabel);
    Assert.areEqual('Moradia', topLevel[1].displayLabel);
    Assert.isNotNull(topLevel[0].id);
  }

  @IsTest
  static void serviceGetCategoriesMapsAliases() {
    ALT_CLS_CategoryLookup service = new ALT_CLS_CategoryLookup();
    List<AXF_OBJ_Category__c> expense;
    List<AXF_OBJ_Category__c> revenue;
    List<AXF_OBJ_Category__c> explicitRt;
    System.runAs(testUser()) {
      Test.startTest();
      expense = service.getCategories('Expense');
      revenue = service.getCategories('RECEITA');
      explicitRt = service.getCategories('AXF_CAT_RT_Revenue');
      Test.stopTest();
    }

    Assert.areEqual(4, expense.size());
    Assert.areEqual(1, revenue.size());
    Assert.areEqual('Salário', revenue[0].Name);
    Assert.areEqual(1, explicitRt.size());
  }

  @IsTest
  static void controllerCreatesCategoryUnderParent() {
    AXF_OBJ_Category__c parent = [
      SELECT Id
      FROM AXF_OBJ_Category__c
      WHERE Name = 'Moradia'
    ];
    AXF_CLS_CTRL_CategoryLookup.CategoryOptionDTO withParent;
    AXF_CLS_CTRL_CategoryLookup.CategoryOptionDTO revenue;
    System.runAs(testUser()) {
      Test.startTest();
      withParent = AXF_CLS_CTRL_CategoryLookup.createCategory(
        dto(' Internet ', parent.Id, 'DESPESA')
      );
      revenue = AXF_CLS_CTRL_CategoryLookup.createCategory(
        dto('Bônus', null, 'Revenue')
      );
      Test.stopTest();
    }

    Assert.areEqual('Moradia > Internet', withParent.displayLabel);
    Assert.areEqual('Bônus', revenue.displayLabel);
    AXF_OBJ_Category__c created = [
      SELECT RecordType.DeveloperName, AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE Id = :withParent.id
    ];
    Assert.areEqual('AXF_CAT_RT_Expense', created.RecordType.DeveloperName);
    Assert.areEqual(parent.Id, created.AXF_CAT_LKP_Parent__c);
    Assert.areEqual(
      'AXF_CAT_RT_Revenue',
      [
        SELECT RecordType.DeveloperName
        FROM AXF_OBJ_Category__c
        WHERE Id = :revenue.id
      ]
      .RecordType.DeveloperName
    );
  }

  @IsTest
  static void controllerWrapsValidationErrors() {
    Integer failures = 0;
    System.runAs(testUser()) {
      Test.startTest();
      for (
        AXF_CLS_CTRL_CategoryLookup.CategoryCreationDTO invalid : new List<AXF_CLS_CTRL_CategoryLookup.CategoryCreationDTO>{
          null,
          dto(' ', null, 'Expense'),
          dto('Categoria', null, 'INEXISTENTE')
        }
      ) {
        try {
          AXF_CLS_CTRL_CategoryLookup.createCategory(invalid);
        } catch (AuraHandledException e) {
          failures++;
        }
      }
      Test.stopTest();
    }

    Assert.areEqual(
      3,
      failures,
      'Invalid input must surface as AuraHandledException'
    );
  }

  @IsTest
  static void serviceRejectsInvalidRequests() {
    Id accountId;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account acc = AXF_CLS_AccountCardTestFactory.newAccount('Conta Qualquer');
      insert acc;
      accountId = acc.Id;
    }
    List<String> messages = new List<String>();
    System.runAs(testUser()) {
      Test.startTest();
      messages.add(serviceError(null));
      messages.add(serviceError(request('', null, 'Expense')));
      messages.add(serviceError(request('Categoria', null, 'INEXISTENTE')));
      messages.add(serviceError(request('Categoria', 'not-an-id', 'Expense')));
      messages.add(serviceError(request('Categoria', accountId, 'Expense')));
      Test.stopTest();
    }

    Assert.areEqual('Category name is required.', messages[0]);
    Assert.areEqual('Category name is required.', messages[1]);
    Assert.areEqual('Invalid Category Record Type.', messages[2]);
    Assert.areEqual('Invalid Parent Category.', messages[3]);
    Assert.areEqual('Invalid Parent Category.', messages[4]);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AXF_OBJ_Category__c WHERE Name = 'Categoria']
    );
  }
}
