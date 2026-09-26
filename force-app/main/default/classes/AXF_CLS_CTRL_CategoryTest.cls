/**
 * @description Covers AXF_CLS_CTRL_Category. Runs as a Standard User with AXF_PS_User because the
 * controller queries WITH USER_MODE and needs FLS on the Category custom fields.
 */
@IsTest
private class AXF_CLS_CTRL_CategoryTest {
  private static final String USER_KEY = 'category';

  @TestSetup
  static void setupData() {
    AXF_CLS_AccountCardTestFactory.createUser(USER_KEY, false);

    AXF_OBJ_Category__c housing = AXF_CLS_AccountCardTestFactory.newCategory(
      'Moradia',
      'AXF_CAT_RT_Expense',
      null
    );
    AXF_OBJ_Category__c food = AXF_CLS_AccountCardTestFactory.newCategory(
      'Alimentação RT',
      'AXF_CAT_RT_Expense',
      null
    );
    AXF_OBJ_Category__c salary = AXF_CLS_AccountCardTestFactory.newCategory(
      'Salário RT',
      'AXF_CAT_RT_Revenue',
      null
    );
    insert new List<AXF_OBJ_Category__c>{ housing, food, salary };
    insert AXF_CLS_AccountCardTestFactory.newCategory(
      'Aluguel',
      'AXF_CAT_RT_Expense',
      housing.Id
    );
  }

  private static User testUser() {
    return AXF_CLS_AccountCardTestFactory.getUser(USER_KEY);
  }

  private static AXF_CLS_CTRL_Category.CategoryCreationDTO dto(
    String name,
    String parentId,
    String recordType
  ) {
    AXF_CLS_CTRL_Category.CategoryCreationDTO dto = new AXF_CLS_CTRL_Category.CategoryCreationDTO();
    dto.name = name;
    dto.parentId = parentId;
    dto.recordTypeDeveloperName = recordType;
    return dto;
  }

  private static Boolean createThrows(
    AXF_CLS_CTRL_Category.CategoryCreationDTO dto
  ) {
    try {
      AXF_CLS_CTRL_Category.createCategory(dto);
    } catch (AuraHandledException e) {
      return true;
    }
    return false;
  }

  @IsTest
  static void testGetCategories() {
    List<AXF_OBJ_Category__c> expenseCats;
    List<AXF_OBJ_Category__c> revenueCats;
    List<AXF_OBJ_Category__c> byRecordTypeName;
    System.runAs(testUser()) {
      Test.startTest();
      expenseCats = AXF_CLS_CTRL_Category.getCategories('DESPESA');
      revenueCats = AXF_CLS_CTRL_Category.getCategories('Revenue');
      byRecordTypeName = AXF_CLS_CTRL_Category.getCategories(
        'AXF_CAT_RT_Expense'
      );
      Test.stopTest();
    }

    Assert.areEqual(
      3,
      expenseCats.size(),
      'Deveria retornar as categorias de despesa'
    );
    Assert.areEqual(
      1,
      revenueCats.size(),
      'Deveria retornar as categorias de receita'
    );
    Assert.areEqual('Salário RT', revenueCats[0].Name);
    Assert.areEqual(
      3,
      byRecordTypeName.size(),
      'DeveloperName do RecordType também deve ser aceito'
    );
  }

  @IsTest
  static void testGetCategoryOptions() {
    List<AXF_CLS_CTRL_Category.CategoryOptionDTO> options;
    System.runAs(testUser()) {
      Test.startTest();
      options = AXF_CLS_CTRL_Category.getCategoryOptions('AXF_CAT_RT_Expense');
      Test.stopTest();
    }

    Set<String> labels = new Set<String>();
    for (AXF_CLS_CTRL_Category.CategoryOptionDTO option : options) {
      labels.add(option.displayLabel);
    }
    Assert.areEqual(
      new Set<String>{ 'Alimentação RT', 'Moradia > Aluguel' },
      labels,
      'Categorias-pai com filhas não são selecionáveis'
    );
  }

  @IsTest
  static void testGetTopLevelCategoryOptions() {
    List<AXF_CLS_CTRL_Category.CategoryOptionDTO> expenseOptions;
    List<AXF_CLS_CTRL_Category.CategoryOptionDTO> revenueOptions;
    System.runAs(testUser()) {
      Test.startTest();
      expenseOptions = AXF_CLS_CTRL_Category.getTopLevelCategoryOptions(
        'AXF_CAT_RT_Expense'
      );
      revenueOptions = AXF_CLS_CTRL_Category.getTopLevelCategoryOptions(
        'AXF_CAT_RT_Revenue'
      );
      Test.stopTest();
    }

    Assert.areEqual(
      2,
      expenseOptions.size(),
      'Somente categorias de primeiro nível'
    );
    Assert.areEqual('Alimentação RT', expenseOptions[0].displayLabel);
    Assert.areEqual('Moradia', expenseOptions[1].displayLabel);
    Assert.areEqual(1, revenueOptions.size());
  }

  @IsTest
  static void testCreateCategoryExpenseWithoutParent() {
    AXF_CLS_CTRL_Category.CategoryOptionDTO result;
    System.runAs(testUser()) {
      Test.startTest();
      result = AXF_CLS_CTRL_Category.createCategory(
        dto(' Assinaturas ', null, 'DESPESA')
      );
      Test.stopTest();
    }

    Assert.isNotNull(result.id, 'Deveria retornar o Id da categoria criada');
    Assert.areEqual(
      'Assinaturas',
      result.displayLabel,
      'Rótulo deveria ser apenas o nome quando não há categoria pai'
    );
    AXF_OBJ_Category__c inserted = [
      SELECT Id, RecordType.DeveloperName, AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE Id = :result.id
    ];
    Assert.areEqual(
      'AXF_CAT_RT_Expense',
      inserted.RecordType.DeveloperName,
      'RecordType deveria ser de Despesa'
    );
    Assert.isNull(
      inserted.AXF_CAT_LKP_Parent__c,
      'Não deveria ter categoria pai'
    );
  }

  @IsTest
  static void testCreateCategoryRevenueWithParent() {
    AXF_OBJ_Category__c parent = [
      SELECT Id, Name
      FROM AXF_OBJ_Category__c
      WHERE Name = 'Salário RT'
    ];
    AXF_CLS_CTRL_Category.CategoryOptionDTO result;
    System.runAs(testUser()) {
      Test.startTest();
      result = AXF_CLS_CTRL_Category.createCategory(
        dto('Freelance', parent.Id, 'RECEITA')
      );
      Test.stopTest();
    }

    Assert.areEqual(
      parent.Name + ' > Freelance',
      result.displayLabel,
      'Rótulo deveria combinar categoria pai e filha'
    );
    AXF_OBJ_Category__c inserted = [
      SELECT Id, RecordType.DeveloperName, AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE Id = :result.id
    ];
    Assert.areEqual(
      'AXF_CAT_RT_Revenue',
      inserted.RecordType.DeveloperName,
      'RecordType deveria ser de Receita'
    );
    Assert.areEqual(
      parent.Id,
      inserted.AXF_CAT_LKP_Parent__c,
      'Deveria referenciar a categoria pai informada'
    );
  }

  @IsTest
  static void testCreateCategoryValidationErrors() {
    Id accountId;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account acc = AXF_CLS_AccountCardTestFactory.newAccount('Conta Qualquer');
      insert acc;
      accountId = acc.Id;
    }
    Integer failures = 0;
    System.runAs(testUser()) {
      Test.startTest();
      failures += createThrows(null) ? 1 : 0;
      failures += createThrows(dto('', null, 'AXF_CAT_RT_Expense')) ? 1 : 0;
      failures += createThrows(dto('Categoria', null, 'INEXISTENTE')) ? 1 : 0;
      failures += createThrows(dto('Categoria', 'not-a-valid-id', 'Expense'))
        ? 1
        : 0;
      failures += createThrows(dto('Categoria', accountId, 'Expense')) ? 1 : 0;
      Test.stopTest();
    }

    Assert.areEqual(
      5,
      failures,
      'Todas as entradas inválidas devem lançar AuraHandledException'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AXF_OBJ_Category__c WHERE Name = 'Categoria'],
      'Nada deve ser criado'
    );
  }
}
