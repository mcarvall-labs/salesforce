public with sharing class AXF_TH_CreditCardInvoice {
    
    public static void handleBeforeInsert(List<AXF_OBJ_CreditCardInvoice__c> newInvoices) {
        populateExternalId(newInvoices);
    }

    public static void handleBeforeUpdate(List<AXF_OBJ_CreditCardInvoice__c> newInvoices, Map<Id, AXF_OBJ_CreditCardInvoice__c> oldMap) {
        populateExternalId(newInvoices);
    }

    private static void populateExternalId(List<AXF_OBJ_CreditCardInvoice__c> invoices) {
        Set<Id> creditCardIdsToQuery = new Set<Id>();

        for (AXF_OBJ_CreditCardInvoice__c inv : invoices) {
            if (inv.AXF_CCI_MD_CreditCard__c != null) {
                if (inv.AXF_CCI_MD_CreditCard__r == null || String.isBlank(inv.AXF_CCI_MD_CreditCard__r.AXF_CC_TXT_LastFourDigits__c)) {
                    creditCardIdsToQuery.add(inv.AXF_CCI_MD_CreditCard__c);
                }
            }
        }

        Map<Id, AXF_OBJ_CreditCard__c> cardMap = new Map<Id, AXF_OBJ_CreditCard__c>();
        if (!creditCardIdsToQuery.isEmpty()) {
            cardMap = new Map<Id, AXF_OBJ_CreditCard__c>([
                SELECT Id, AXF_CC_TXT_LastFourDigits__c 
                FROM AXF_OBJ_CreditCard__c 
                WHERE Id IN :creditCardIdsToQuery
            ]);
        }

        for (AXF_OBJ_CreditCardInvoice__c inv : invoices) {
            String lastFourDigits = null;

            if (inv.AXF_CCI_MD_CreditCard__r != null && String.isNotBlank(inv.AXF_CCI_MD_CreditCard__r.AXF_CC_TXT_LastFourDigits__c)) {
                lastFourDigits = inv.AXF_CCI_MD_CreditCard__r.AXF_CC_TXT_LastFourDigits__c;
            } else if (inv.AXF_CCI_MD_CreditCard__c != null && cardMap.containsKey(inv.AXF_CCI_MD_CreditCard__c)) {
                lastFourDigits = cardMap.get(inv.AXF_CCI_MD_CreditCard__c).AXF_CC_TXT_LastFourDigits__c;
            }

            String formattedPeriod = formatPeriod(inv.AXF_CCI_TXT_Period__c);

            if (String.isNotBlank(formattedPeriod)) {
                inv.Name = formattedPeriod;
            } else if (String.isNotBlank(inv.AXF_CCI_TXT_Period__c)) {
                inv.Name = inv.AXF_CCI_TXT_Period__c;
            }

            if (String.isNotBlank(lastFourDigits) && String.isNotBlank(formattedPeriod)) {
                inv.AXF_CCI_EXT_ExternalId__c = lastFourDigits + '_' + formattedPeriod;
            }
        }
    }

    private static String formatPeriod(String rawPeriod) {
        if (String.isBlank(rawPeriod)) {
            return null;
        }

        rawPeriod = rawPeriod.trim();

        // MM/YYYY format check (e.g. "06/2027" or "6/2027")
        if (rawPeriod.contains('/')) {
            List<String> parts = rawPeriod.split('/');
            if (parts.size() == 2) {
                String monthStr = parts[0].trim();
                String yearStr = parts[1].trim();

                if (monthStr.length() == 1) {
                    monthStr = '0' + monthStr;
                }

                if (monthStr.length() == 2 && yearStr.length() == 4) {
                    return yearStr + '-' + monthStr;
                }
            }
        }

        // YYYY-MM format check (e.g. "2027-06")
        if (rawPeriod.contains('-')) {
            List<String> parts = rawPeriod.split('-');
            if (parts.size() == 2) {
                String yearStr = parts[0].trim();
                String monthStr = parts[1].trim();

                if (monthStr.length() == 1) {
                    monthStr = '0' + monthStr;
                }

                if (yearStr.length() == 4 && monthStr.length() == 2) {
                    return yearStr + '-' + monthStr;
                }
            }
        }

        return rawPeriod;
    }
}