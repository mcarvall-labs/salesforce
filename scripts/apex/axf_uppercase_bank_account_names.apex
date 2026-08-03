// Higienização de dados - Issue #101
// Garante que o Name de todos os registros existentes de AXF_OBJ_BankAccount__c
// esteja em CAIXA ALTA (UPPERCASE), alinhado com a nova lógica de sincronização
// em AXF_CLS_PluggyAccountSync_Service.

List<AXF_OBJ_BankAccount__c> accountsToUpdate = new List<AXF_OBJ_BankAccount__c>();

for (AXF_OBJ_BankAccount__c acc : [SELECT Id, Name FROM AXF_OBJ_BankAccount__c WHERE Name != null]) {
    String upperName = acc.Name.toUpperCase();
    if (!upperName.equals(acc.Name)) {
        acc.Name = upperName;
        accountsToUpdate.add(acc);
    }
}

if (!accountsToUpdate.isEmpty()) {
    update accountsToUpdate;
    System.debug('Registros atualizados para CAIXA ALTA: ' + accountsToUpdate.size());
} else {
    System.debug('Nenhum registro precisava de atualização.');
}
