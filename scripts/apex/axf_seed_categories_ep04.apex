// Dado inicial - EP04-H1 (AXF-198): 7 categorias iniciais.
// Idempotente: só insere o que ainda não existir (casando por Name).

Map<String, String> typeByName = new Map<String, String>{
    'Moradia' => 'Expense',
    'Alimentação' => 'Expense',
    'Transporte' => 'Expense',
    'Saúde' => 'Expense',
    'Lazer' => 'Expense',
    'Salário' => 'Income',
    'Serviços' => 'Expense'
};

Set<String> existing = new Set<String>();
for (AXF_OBJ_Category__c c : [SELECT Name FROM AXF_OBJ_Category__c WHERE Name IN :typeByName.keySet()]) {
    existing.add(c.Name);
}

List<AXF_OBJ_Category__c> toInsert = new List<AXF_OBJ_Category__c>();
for (String name : typeByName.keySet()) {
    if (!existing.contains(name)) {
        toInsert.add(new AXF_OBJ_Category__c(Name = name, AXF_CAT_PKL_Type__c = typeByName.get(name)));
    }
}
insert toInsert;
System.debug('Categorias inseridas: ' + toInsert.size());
