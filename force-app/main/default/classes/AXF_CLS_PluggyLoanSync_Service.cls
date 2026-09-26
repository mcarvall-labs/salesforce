public with sharing class AXF_CLS_PluggyLoanSync_Service {

    private static final String LOANS_ENDPOINT = 'callout:AXF_NC_Pluggy_API/loans?itemId=';

    public static List<AXF_OBJ_Loan__c> fetchLoansForConnection(Id connectionId, String pluggyItemId, String apiKey) {
        List<AXF_OBJ_Loan__c> loans = new List<AXF_OBJ_Loan__c>();

        if (String.isBlank(pluggyItemId)) {
            return loans;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(LOANS_ENDPOINT + EncodingUtil.urlEncode(pluggyItemId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('X-API-KEY', apiKey);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            loans = parseLoans(res.getBody(), connectionId);
        }

        return loans;
    }

    public static void upsertLoans(List<AXF_OBJ_Loan__c> loans) {
        if (!loans.isEmpty()) {
            Database.upsert(loans, AXF_OBJ_Loan__c.AXF_LOA_EXI_PluggyLoanId__c, false);
        }
    }

    private static List<AXF_OBJ_Loan__c> parseLoans(String responseBody, Id connectionId) {
        List<AXF_OBJ_Loan__c> loans = new List<AXF_OBJ_Loan__c>();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> results = (List<Object>) body.get('results');
        if (results == null) {
            return loans;
        }

        for (Object item : results) {
            Map<String, Object> data = (Map<String, Object>) item;

            AXF_OBJ_Loan__c loan = new AXF_OBJ_Loan__c();
            loan.AXF_LOA_EXI_PluggyLoanId__c = (String) data.get('id');
            loan.AXF_LOA_LKP_PluggyConnection__c = connectionId;
            loan.AXF_LOA_PKL_Type__c = (String) data.get('type');
            loan.AXF_LOA_CUR_ContractedAmount__c = toDecimal(data.get('contractedAmount'));
            loan.AXF_LOA_CUR_OutstandingBalance__c = toDecimal(data.get('outstandingBalance'));
            loan.AXF_LOA_NUM_InterestRate__c = toDecimal(data.get('interestRate'));
            loan.AXF_LOA_NUM_TotalInstallments__c = toDecimal(data.get('totalInstallments'));
            loan.AXF_LOA_NUM_PaidInstallments__c = toDecimal(data.get('paidInstallments'));
            loan.Name = (String) data.get('id');

            loans.add(loan);
        }

        return loans;
    }

    private static Decimal toDecimal(Object value) {
        return value != null ? (Decimal) value : null;
    }
}