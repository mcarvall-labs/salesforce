public with sharing class AXF_CLS_PluggyInvSync_Service {

    private static final String INVESTMENTS_ENDPOINT = 'callout:AXF_NC_Pluggy_API/investments?itemId=';
    private static final String INVESTMENT_TX_ENDPOINT = 'callout:AXF_NC_Pluggy_API/investments/';

    public static List<AXF_OBJ_Investment__c> fetchInvestmentsForConnection(Id connectionId, String pluggyItemId, String apiKey) {
        List<AXF_OBJ_Investment__c> investments = new List<AXF_OBJ_Investment__c>();

        if (String.isBlank(pluggyItemId)) {
            return investments;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(INVESTMENTS_ENDPOINT + EncodingUtil.urlEncode(pluggyItemId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('X-API-KEY', apiKey);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            investments = parseInvestments(res.getBody(), connectionId);
        }

        return investments;
    }

    public static void upsertInvestments(List<AXF_OBJ_Investment__c> investments) {
        if (!investments.isEmpty()) {
            Database.upsert(investments, AXF_OBJ_Investment__c.AXF_INV_EXI_PluggyInvestmentId__c, false);
        }
    }

    private static List<AXF_OBJ_Investment__c> parseInvestments(String responseBody, Id connectionId) {
        List<AXF_OBJ_Investment__c> investments = new List<AXF_OBJ_Investment__c>();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> results = (List<Object>) body.get('results');
        if (results == null) {
            return investments;
        }

        for (Object item : results) {
            Map<String, Object> data = (Map<String, Object>) item;

            AXF_OBJ_Investment__c investment = new AXF_OBJ_Investment__c();
            investment.AXF_INV_EXI_PluggyInvestmentId__c = (String) data.get('id');
            investment.AXF_INV_LKP_PluggyConnection__c = connectionId;
            investment.AXF_INV_PKL_Type__c = (String) data.get('type');
            investment.AXF_INV_PKL_Currency__c = (String) data.get('currencyCode');
            investment.AXF_INV_CUR_Balance__c = data.get('balance') != null ? (Decimal) data.get('balance') : null;
            investment.Name = data.get('name') != null ? String.valueOf(data.get('name')) : (String) data.get('id');

            investments.add(investment);
        }

        return investments;
    }
}