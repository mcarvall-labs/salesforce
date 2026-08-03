public with sharing class AXF_CLS_TH_CreditCardInvoice {

    public static void handleBeforeInsert(List<AXF_OBJ_CreditCardInvoice__c> newRecords) {
        populateExternalId(newRecords);
    }

    public static void handleBeforeUpdate(List<AXF_OBJ_CreditCardInvoice__c> newRecords, Map<Id, AXF_OBJ_CreditCardInvoice__c> oldMap) {
        populateExternalId(newRecords);
    }

    private static void populateExternalId(List<AXF_OBJ_CreditCardInvoice__c> records) {
        Set<Id> cardIds = new Set<Id>();
        for (AXF_OBJ_CreditCardInvoice__c inv : records) {
            if (inv.AXF_CCI_LKP_CreditCard__c != null) {
                cardIds.add(inv.AXF_CCI_LKP_CreditCard__c);
            }
        }

        Map<Id, AXF_OBJ_CreditCard__c> cardMap = new Map<Id, AXF_OBJ_CreditCard__c>();
        if (!cardIds.isEmpty()) {
            cardMap = new Map<Id, AXF_OBJ_CreditCard__c>([
                SELECT Id, AXF_CC_TXT_LastFourDigits__c 
                FROM AXF_OBJ_CreditCard__c 
                WHERE Id IN :cardIds
                WITH USER_MODE
            ]);
        }

        for (AXF_OBJ_CreditCardInvoice__c inv : records) {
            String lastFour = '';
            if (inv.AXF_CCI_LKP_CreditCard__c != null && cardMap.containsKey(inv.AXF_CCI_LKP_CreditCard__c)) {
                lastFour = cardMap.get(inv.AXF_CCI_LKP_CreditCard__c).AXF_CC_TXT_LastFourDigits__c;
            }

            String formattedPeriod = formatPeriodToYearMonth(inv.AXF_CCI_TXT_Period__c);
            if (String.isNotBlank(lastFour) && String.isNotBlank(formattedPeriod)) {
                inv.AXF_CCI_EXT_ExternalId__c = lastFour + '_' + formattedPeriod;
            }
        }
    }

    private static String formatPeriodToYearMonth(String period) {
        if (String.isBlank(period)) return '';
        period = period.trim();
        if (period.contains('/')) {
            String[] parts = period.split('/');
            if (parts.size() == 2) {
                String month = parts[0].padStart(2, '0');
                String year = parts[1];
                return year + '-' + month;
            }
        }
        return period;
    }
}
