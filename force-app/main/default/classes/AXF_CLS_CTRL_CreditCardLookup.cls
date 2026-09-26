/**
 * @description Dedicated controller for aXF_LWC_creditCardLookup LWC.
 */
public with sharing class AXF_CLS_CTRL_CreditCardLookup {

    public class CreditCardOptionDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String displayLabel;
        @AuraEnabled public String accountId;
    }

    @AuraEnabled(cacheable=true)
    public static List<CreditCardOptionDTO> getCreditCardOptions() {
        List<AXF_OBJ_CreditCard__c> creditCards = [
            SELECT Id, Name, AXF_CC_LKP_Account__c, AXF_CC_LKP_Account__r.Name
            FROM AXF_OBJ_CreditCard__c
            WITH USER_MODE
            ORDER BY Name ASC
        ];

        List<CreditCardOptionDTO> dtos = new List<CreditCardOptionDTO>();
        for (AXF_OBJ_CreditCard__c cc : creditCards) {
            CreditCardOptionDTO dto = new CreditCardOptionDTO();
            dto.id = cc.Id;
            dto.accountId = cc.AXF_CC_LKP_Account__c;
            dto.displayLabel = String.isNotBlank(cc.AXF_CC_LKP_Account__r.Name) 
                ? cc.Name + ' (' + cc.AXF_CC_LKP_Account__r.Name + ')' 
                : cc.Name;
            dtos.add(dto);
        }
        return dtos;
    }
}