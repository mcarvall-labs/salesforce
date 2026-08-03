public with sharing class AXF_CLS_TH_BankInstitution {
    
    public static void handleBeforeInsertUpdate(List<AXF_OBJ_BankInstitution__c> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        for (AXF_OBJ_BankInstitution__c bi : newList) {
            String bankName = String.isNotBlank(bi.AXF_BI_PKL_BankName__c) ? bi.AXF_BI_PKL_BankName__c : bi.Name;
            String bankNumber = bi.AXF_BI_EXI_Bank_Number__c;

            if (String.isNotBlank(bankName)) {
                if (String.isNotBlank(bankNumber)) {
                    bi.Name = bankName + ' (' + bankNumber.trim() + ')';
                } else {
                    bi.Name = bankName;
                }
            }
        }
    }
}
