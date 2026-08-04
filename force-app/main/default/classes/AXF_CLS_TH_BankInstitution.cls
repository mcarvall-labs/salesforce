public with sharing class AXF_CLS_TH_BankInstitution {
  public static void handleBeforeInsert(
    List<AXF_OBJ_BankInstitution__c> newRecords
  ) {
    applyNameFormat(newRecords);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_BankInstitution__c> newRecords
  ) {
    applyNameFormat(newRecords);
  }

  private static void applyNameFormat(
    List<AXF_OBJ_BankInstitution__c> records
  ) {
    for (AXF_OBJ_BankInstitution__c bi : records) {
      String bankName = bi.AXF_BI_PKL_BankName__c;
      String bankNumber = bi.AXF_BI_EXI_Bank_Number__c;

      if (String.isBlank(bankName)) {
        continue;
      }

      bi.Name = String.isBlank(bankNumber)
        ? bankName
        : bankName + ' (' + bankNumber + ')';
    }
  }
}
