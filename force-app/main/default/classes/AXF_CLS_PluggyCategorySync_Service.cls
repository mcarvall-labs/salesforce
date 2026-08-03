public with sharing class AXF_CLS_PluggyCategorySync_Service {

    private static final String CATEGORIES_ENDPOINT = 'callout:AXF_NC_Pluggy_API/categories';

    public static void syncCategories() {
        String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(CATEGORIES_ENDPOINT);
        req.setMethod('GET');
        req.setHeader('X-API-KEY', apiKey);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            return;
        }

        upsertCategoryHierarchy(parseCategoriesJson(res.getBody()));
    }

    public static void upsertCategoryHierarchy(List<Map<String, Object>> categoriesJson) {
        List<Map<String, Object>> rootCategories = new List<Map<String, Object>>();
        List<Map<String, Object>> childCategories = new List<Map<String, Object>>();

        for (Map<String, Object> data : categoriesJson) {
            if (data.get('parentId') == null) {
                rootCategories.add(data);
            } else {
                childCategories.add(data);
            }
        }

        upsertBatch(rootCategories, null);

        if (!childCategories.isEmpty()) {
            upsertBatch(childCategories, queryExistingCategoryIds());
        }
    }

    private static List<Map<String, Object>> parseCategoriesJson(String responseBody) {
        List<Map<String, Object>> categories = new List<Map<String, Object>>();

        Object parsed = JSON.deserializeUntyped(responseBody);
        List<Object> results = parsed instanceof List<Object>
            ? (List<Object>) parsed
            : (List<Object>) ((Map<String, Object>) parsed).get('results');

        if (results == null) {
            return categories;
        }

        for (Object item : results) {
            categories.add((Map<String, Object>) item);
        }

        return categories;
    }

    private static void upsertBatch(List<Map<String, Object>> categoriesJson, Map<String, Id> categoryIdByPluggyId) {
        if (categoriesJson.isEmpty()) {
            return;
        }

        List<AXF_OBJ_Category__c> categoriesToUpsert = new List<AXF_OBJ_Category__c>();
        for (Map<String, Object> data : categoriesJson) {
            AXF_OBJ_Category__c category = new AXF_OBJ_Category__c();
            category.AXF_CAT_EXI_PluggyCategoryId__c = (String) data.get('id');
            category.Name = (String) data.get('descriptionTranslated');

            if (categoryIdByPluggyId != null) {
                String parentPluggyId = (String) data.get('parentId');
                if (parentPluggyId != null && categoryIdByPluggyId.containsKey(parentPluggyId)) {
                    category.AXF_CAT_LKP_Parent__c = categoryIdByPluggyId.get(parentPluggyId);
                }
            }

            categoriesToUpsert.add(category);
        }

        Database.upsert(categoriesToUpsert, AXF_OBJ_Category__c.AXF_CAT_EXI_PluggyCategoryId__c, false);
    }

    private static Map<String, Id> queryExistingCategoryIds() {
        Map<String, Id> categoryIdByPluggyId = new Map<String, Id>();

        for (AXF_OBJ_Category__c category : [
            SELECT Id, AXF_CAT_EXI_PluggyCategoryId__c
            FROM AXF_OBJ_Category__c
            WHERE AXF_CAT_EXI_PluggyCategoryId__c != null
        ]) {
            categoryIdByPluggyId.put(category.AXF_CAT_EXI_PluggyCategoryId__c, category.Id);
        }

        return categoryIdByPluggyId;
    }
}