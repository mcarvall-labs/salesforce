@IsTest
private class AXF_CLS_CTRL_CategoryTest {

    @TestSetup
    static void setupData() {
        Map<String, Schema.RecordTypeInfo> catRtMap = Schema.SObjectType.AXF_OBJ_Category__c.getRecordTypeInfosByDeveloperName();
        Id expenseRtId = catRtMap.containsKey('AXF_CAT_RT_Expense') ? catRtMap.get('AXF_CAT_RT_Expense').getRecordTypeId() : null;
        Id revenueRtId = catRtMap.containsKey('AXF_CAT_RT_Revenue') ? catRtMap.get('AXF_CAT_RT_Revenue').getRecordTypeId() : null;

        List<AXF_OBJ_Category__c> categories = new List<AXF_OBJ_Category__c>();

        if (expenseRtId != null) {
            categories.add(new AXF_OBJ_Category__c(
                Name = 'Alimentação RT',
                RecordTypeId = expenseRtId
            ));
        } else {
            categories.add(new AXF_OBJ_Category__c(
                Name = 'Alimentação Picklist',
                AXF_CAT_PKL_Type__c = 'DESPESA'
            ));
        }

        if (revenueRtId != null) {
            categories.add(new AXF_OBJ_Category__c(
                Name = 'Salário RT',
                RecordTypeId = revenueRtId
            ));
        } else {
            categories.add(new AXF_OBJ_Category__c(
                Name = 'Salário Picklist',
                AXF_CAT_PKL_Type__c = 'RECEITA'
            ));
        }

        insert categories;
    }

    @IsTest
    static void testGetCategories() {
        Test.startTest();
        List<AXF_OBJ_Category__c> expenseCats = AXF_CLS_CTRL_Category.getCategories('DESPESA');
        List<AXF_OBJ_Category__c> revenueCats = AXF_CLS_CTRL_Category.getCategories('RECEITA');
        Test.stopTest();

        System.assertNotEquals(0, expenseCats.size(), 'Deveria retornar categorias de despesa');
        System.assertNotEquals(0, revenueCats.size(), 'Deveria retornar categorias de receita');
    }

    @IsTest
    static void testGetCategoryOptions() {
        Test.startTest();
        List<AXF_CLS_CTRL_Category.CategoryOptionDTO> options = AXF_CLS_CTRL_Category.getCategoryOptions('AXF_CAT_RT_Expense');
        Test.stopTest();

        System.assertNotEquals(null, options, 'Lista de opções de categoria não deve ser nula');
    }

    @IsTest
    static void testGetTopLevelCategoryOptions() {
        Test.startTest();
        List<AXF_CLS_CTRL_Category.CategoryOptionDTO> expenseOptions =
            AXF_CLS_CTRL_Category.getTopLevelCategoryOptions('AXF_CAT_RT_Expense');
        List<AXF_CLS_CTRL_Category.CategoryOptionDTO> revenueOptions =
            AXF_CLS_CTRL_Category.getTopLevelCategoryOptions('AXF_CAT_RT_Revenue');
        Test.stopTest();

        System.assertNotEquals(null, expenseOptions, 'Lista de categorias-pai de despesa não deve ser nula');
        System.assertNotEquals(null, revenueOptions, 'Lista de categorias-pai de receita não deve ser nula');
    }

    @IsTest
    static void testCreateCategoryExpenseWithoutParent() {
        AXF_CLS_CTRL_Category.CategoryCreationDTO dto = new AXF_CLS_CTRL_Category.CategoryCreationDTO();
        dto.name = 'Assinaturas';
        dto.recordTypeDeveloperName = 'AXF_CAT_RT_Expense';

        Test.startTest();
        AXF_CLS_CTRL_Category.CategoryOptionDTO result = AXF_CLS_CTRL_Category.createCategory(dto);
        Test.stopTest();

        System.assertNotEquals(null, result.id, 'Deveria retornar o Id da categoria criada');
        System.assertEquals('Assinaturas', result.displayLabel, 'Rótulo deveria ser apenas o nome quando não há categoria pai');

        AXF_OBJ_Category__c inserted = [SELECT Id, Name, RecordType.DeveloperName, AXF_CAT_LKP_Parent__c FROM AXF_OBJ_Category__c WHERE Id = :result.id];
        System.assertEquals('AXF_CAT_RT_Expense', inserted.RecordType.DeveloperName, 'RecordType deveria ser de Despesa');
        System.assertEquals(null, inserted.AXF_CAT_LKP_Parent__c, 'Não deveria ter categoria pai');
    }

    @IsTest
    static void testCreateCategoryRevenueWithParent() {
        AXF_OBJ_Category__c parent = [SELECT Id, Name FROM AXF_OBJ_Category__c WHERE RecordType.DeveloperName = 'AXF_CAT_RT_Revenue' LIMIT 1];

        AXF_CLS_CTRL_Category.CategoryCreationDTO dto = new AXF_CLS_CTRL_Category.CategoryCreationDTO();
        dto.name = 'Freelance';
        dto.parentId = parent.Id;
        dto.recordTypeDeveloperName = 'AXF_CAT_RT_Revenue';

        Test.startTest();
        AXF_CLS_CTRL_Category.CategoryOptionDTO result = AXF_CLS_CTRL_Category.createCategory(dto);
        Test.stopTest();

        System.assertNotEquals(null, result.id, 'Deveria retornar o Id da categoria criada');
        System.assertEquals(parent.Name + ' > Freelance', result.displayLabel, 'Rótulo deveria combinar categoria pai e filha');

        AXF_OBJ_Category__c inserted = [SELECT Id, RecordType.DeveloperName, AXF_CAT_LKP_Parent__c FROM AXF_OBJ_Category__c WHERE Id = :result.id];
        System.assertEquals('AXF_CAT_RT_Revenue', inserted.RecordType.DeveloperName, 'RecordType deveria ser de Receita');
        System.assertEquals(parent.Id, inserted.AXF_CAT_LKP_Parent__c, 'Deveria referenciar a categoria pai informada');
    }

    @IsTest
    static void testCreateCategoryBlankNameThrows() {
        AXF_CLS_CTRL_Category.CategoryCreationDTO dto = new AXF_CLS_CTRL_Category.CategoryCreationDTO();
        dto.name = '';
        dto.recordTypeDeveloperName = 'AXF_CAT_RT_Expense';

        Boolean threw = false;
        Test.startTest();
        try {
            AXF_CLS_CTRL_Category.createCategory(dto);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Deveria lançar exceção quando o nome da categoria está em branco');
    }

    @IsTest
    static void testCreateCategoryInvalidParentThrows() {
        AXF_CLS_CTRL_Category.CategoryCreationDTO dto = new AXF_CLS_CTRL_Category.CategoryCreationDTO();
        dto.name = 'Categoria Inválida';
        dto.parentId = 'not-a-valid-id';
        dto.recordTypeDeveloperName = 'AXF_CAT_RT_Expense';

        Boolean threw = false;
        Test.startTest();
        try {
            AXF_CLS_CTRL_Category.createCategory(dto);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Deveria lançar exceção quando o Id da categoria pai é inválido');
    }
}