// Massa de dados - Issue #211 (US-088)
// Cria um conjunto de Categorias e Subcategorias (hierarquia via AXF_CAT_LKP_Parent__c)
// para os Record Types de Despesa (AXF_CAT_RT_Expense) e Receita (AXF_CAT_RT_Revenue),
// para popular o novo lookup combinado de Categoria/Subcategoria (aXF_LWC_categoryLookup).
// Idempotente: só insere o que ainda não existir (casando por Name + RecordTypeId).

Map<String, Id> rtIdByDevName = new Map<String, Id>();
for (Schema.RecordTypeInfo rti : AXF_OBJ_Category__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().values()) {
    rtIdByDevName.put(rti.getDeveloperName(), rti.getRecordTypeId());
}
Id expenseRtId = rtIdByDevName.get('AXF_CAT_RT_Expense');
Id revenueRtId = rtIdByDevName.get('AXF_CAT_RT_Revenue');

Map<String, List<String>> expenseTree = new Map<String, List<String>>{
    'Moradia' => new List<String>{ 'Aluguel', 'Energia', 'Água', 'Condomínio', 'Internet/TV' },
    'Transporte' => new List<String>{ 'Combustível', 'Uber/Transporte por App', 'Transporte Público', 'Manutenção Veículo' },
    'Alimentação' => new List<String>{ 'Supermercado', 'Restaurante', 'Delivery' },
    'Saúde' => new List<String>{ 'Plano de Saúde', 'Farmácia', 'Consultas/Exames' },
    'Lazer' => new List<String>{ 'Streaming', 'Viagem', 'Cinema/Shows' },
    'Educação' => new List<String>{ 'Cursos', 'Material Didático' },
    'Cartão de Crédito' => new List<String>{ 'Fatura Cartão' }
};

Map<String, List<String>> revenueTree = new Map<String, List<String>>{
    'Salário' => new List<String>{ 'Salário CLT', '13º/Férias' },
    'Renda Extra' => new List<String>{ 'Freelance', 'Aluguel Recebido' },
    'Investimentos' => new List<String>{ 'Dividendos', 'Rendimento' }
};

List<AXF_OBJ_Category__c> toInsertParents = new List<AXF_OBJ_Category__c>();
List<AXF_OBJ_Category__c> toInsertChildren = new List<AXF_OBJ_Category__c>();

Map<String, AXF_OBJ_Category__c> existingByKey = new Map<String, AXF_OBJ_Category__c>();
for (AXF_OBJ_Category__c cat : [SELECT Id, Name, RecordTypeId, AXF_CAT_LKP_Parent__c FROM AXF_OBJ_Category__c]) {
    existingByKey.put(cat.RecordTypeId + '::' + cat.Name, cat);
}

Map<String, Map<String, List<String>>> trees = new Map<String, Map<String, List<String>>>{
    'AXF_CAT_RT_Expense' => expenseTree,
    'AXF_CAT_RT_Revenue' => revenueTree
};
Map<String, Id> rtIdByTreeKey = new Map<String, Id>{
    'AXF_CAT_RT_Expense' => expenseRtId,
    'AXF_CAT_RT_Revenue' => revenueRtId
};

for (String treeKey : trees.keySet()) {
    Id rtId = rtIdByTreeKey.get(treeKey);
    Map<String, List<String>> tree = trees.get(treeKey);
    for (String parentName : tree.keySet()) {
        String key = rtId + '::' + parentName;
        if (!existingByKey.containsKey(key)) {
            AXF_OBJ_Category__c parent = new AXF_OBJ_Category__c(Name = parentName, RecordTypeId = rtId);
            toInsertParents.add(parent);
        }
    }
}

if (!toInsertParents.isEmpty()) {
    insert toInsertParents;
    for (AXF_OBJ_Category__c parent : toInsertParents) {
        existingByKey.put(parent.RecordTypeId + '::' + parent.Name, parent);
    }
}

for (String treeKey : trees.keySet()) {
    Id rtId = rtIdByTreeKey.get(treeKey);
    Map<String, List<String>> tree = trees.get(treeKey);
    for (String parentName : tree.keySet()) {
        AXF_OBJ_Category__c parent = existingByKey.get(rtId + '::' + parentName);
        for (String childName : tree.get(parentName)) {
            String childKey = rtId + '::' + childName;
            if (!existingByKey.containsKey(childKey)) {
                AXF_OBJ_Category__c child = new AXF_OBJ_Category__c(
                    Name = childName,
                    RecordTypeId = rtId,
                    AXF_CAT_LKP_Parent__c = parent.Id
                );
                toInsertChildren.add(child);
                existingByKey.put(childKey, child);
            }
        }
    }
}

if (!toInsertChildren.isEmpty()) {
    insert toInsertChildren;
}

System.debug('Categorias pai criadas: ' + toInsertParents.size());
System.debug('Subcategorias criadas: ' + toInsertChildren.size());
