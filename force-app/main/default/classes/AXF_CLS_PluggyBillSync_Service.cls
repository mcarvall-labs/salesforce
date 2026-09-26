public with sharing class AXF_CLS_PluggyBillSync_Service {

    private static final String BILLS_ENDPOINT = 'callout:AXF_NC_Pluggy_API/bills?accountId=';

    public static List<AXF_OBJ_CreditCardInvoice__c> fetchBillsForCreditCard(
        Id creditCardId,
        String pluggyCreditCardId,
        String apiKey
    ) {
        List<AXF_OBJ_CreditCardInvoice__c> invoices = new List<AXF_OBJ_CreditCardInvoice__c>();

        if (String.isBlank(pluggyCreditCardId)) {
            return invoices;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BILLS_ENDPOINT + EncodingUtil.urlEncode(pluggyCreditCardId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('X-API-KEY', apiKey);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            invoices = parseBills(res.getBody(), creditCardId);
        }

        return invoices;
    }

    public static void upsertBills(List<AXF_OBJ_CreditCardInvoice__c> invoices) {
        if (!invoices.isEmpty()) {
            Database.upsert(invoices, AXF_OBJ_CreditCardInvoice__c.AXF_CCI_EXI_PluggyInvoiceId__c, false);
        }
    }

    private static List<AXF_OBJ_CreditCardInvoice__c> parseBills(String responseBody, Id creditCardId) {
        List<AXF_OBJ_CreditCardInvoice__c> invoices = new List<AXF_OBJ_CreditCardInvoice__c>();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> results = (List<Object>) body.get('results');
        if (results == null) {
            return invoices;
        }

        for (Object item : results) {
            Map<String, Object> data = (Map<String, Object>) item;

            AXF_OBJ_CreditCardInvoice__c invoice = new AXF_OBJ_CreditCardInvoice__c();
            invoice.AXF_CCI_EXI_PluggyInvoiceId__c = (String) data.get('id');
            invoice.AXF_CCI_MD_CreditCard__c = creditCardId;
            invoice.AXF_CCI_DAT_DueDate__c = parseDate((String) data.get('dueDate'));

            // API field is 'billClosingDate' (not 'closingDate'). It commonly comes null.
            // Business rule: when null, calculate as dueDate - 10 days.
            Date closingDate = parseDate((String) data.get('billClosingDate'));
            if (closingDate == null && invoice.AXF_CCI_DAT_DueDate__c != null) {
                closingDate = invoice.AXF_CCI_DAT_DueDate__c.addDays(-10);
            }
            invoice.AXF_CCI_DAT_ClosingDate__c = closingDate;

            // API field is 'totalAmount' (not 'total')
            invoice.AXF_CCI_CUR_TotalAmount__c = data.get('totalAmount') != null
                ? (Decimal) data.get('totalAmount')
                : null;

            // 'status' is not returned by Pluggy Bills API — field omitted intentionally

            if (invoice.AXF_CCI_DAT_DueDate__c != null) {
                Integer m = invoice.AXF_CCI_DAT_DueDate__c.month();
                Integer y = invoice.AXF_CCI_DAT_DueDate__c.year();
                String monthStr = m < 10 ? '0' + m : String.valueOf(m);
                invoice.AXF_CCI_TXT_Period__c = monthStr + '/' + y;
                invoice.Name = invoice.AXF_CCI_TXT_Period__c;
            }

            invoices.add(invoice);
        }

        return invoices;
    }

    private static Date parseDate(String isoDate) {
        if (String.isBlank(isoDate)) {
            return null;
        }
        Datetime parsed = (Datetime) JSON.deserialize('"' + isoDate + '"', Datetime.class);
        return Date.newInstance(parsed.yearGmt(), parsed.monthGmt(), parsed.dayGmt());
    }
}