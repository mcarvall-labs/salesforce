/**
 * @description Dedicated controller for aXF_LWC_bankAccountLookup LWC.
 */
public with sharing class AXF_CLS_CTRL_BankAccountLookup {

    public class BankAccountOptionDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String displayLabel;
        @AuraEnabled public String accountId;
    }

    @AuraEnabled(cacheable=true)
    public static List<BankAccountOptionDTO> getBankAccountOptions() {
        List<AXF_OBJ_BankAccount__c> bankAccounts = [
            SELECT Id, Name, AXF_BA_LKP_Account__c, AXF_BA_LKP_Account__r.Name
            FROM AXF_OBJ_BankAccount__c
            WITH USER_MODE
            ORDER BY Name ASC
        ];

        List<BankAccountOptionDTO> dtos = new List<BankAccountOptionDTO>();
        for (AXF_OBJ_BankAccount__c ba : bankAccounts) {
            BankAccountOptionDTO dto = new BankAccountOptionDTO();
            dto.id = ba.Id;
            dto.accountId = ba.AXF_BA_LKP_Account__c;
            dto.displayLabel = String.isNotBlank(ba.AXF_BA_LKP_Account__r.Name) 
                ? ba.Name + ' (' + ba.AXF_BA_LKP_Account__r.Name + ')' 
                : ba.Name;
            dtos.add(dto);
        }
        return dtos;
    }
}