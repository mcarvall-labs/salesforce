public with sharing class AXF_CLS_PluggyAuthService {

    private static final String NAMED_CREDENTIAL_ENDPOINT = 'callout:AXF_NC_Pluggy_API/auth';
    // Platform Cache partition to reuse 2h Pluggy JWT token (US-021)
    private static final String CACHE_PARTITION = 'local.AXFPluggyCache';
    private static final String CACHE_KEY = 'PluggyApiKey';
    private static final Integer CACHE_TTL_SECONDS = 7200;

    public static String getValidApiKey() {
        String cachedApiKey = getFromCache();
        if (String.isNotBlank(cachedApiKey)) {
            return cachedApiKey;
        }

        String apiKey = requestNewApiKey();
        storeInCache(apiKey);
        return apiKey;
    }

    private static String requestNewApiKey() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Cache-Control', 'no-cache');
        req.setBody('{"clientId":"{!$Credential.AXF_EXC_Pluggy.clientId}",' + '"clientSecret":"{!$Credential.AXF_EXC_Pluggy.clientSecret}"}');

        // === DEBUG DA REQUISIÇÃO ===
        System.debug('=== DEBUG DA REQUISIÇÃO ===');
        System.debug('Endpoint: ' + req.getEndpoint());
        System.debug('Método: ' + req.getMethod());
        System.debug('Header Content-Type: ' + req.getHeader('Content-Type'));
        System.debug('Header Cache-Control: ' + req.getHeader('Cache-Control'));
        System.debug('Corpo (Body): ' + req.getBody());
        System.debug('============================');

        HttpResponse res = new Http().send(req);

        // === DEBUG DA RESPOSTA ===
        System.debug('=== DEBUG DA RESPOSTA ===');
        System.debug('Status Code: ' + res.getStatusCode());
        System.debug('Status: ' + res.getStatus());
        System.debug('Corpo da Resposta (Body): ' + res.getBody());
        System.debug('==========================');

        if (res.getStatusCode() != 200) {
            String details = res.getBody();
            if (details.contains('client keys are invalid')) {
                throw new AXF_CLS_PluggyAuthException(
                    'As chaves de cliente (Client ID e Client Secret) registradas na Credencial Externa do Salesforce são inválidas ou expiraram na Pluggy (HTTP 401: client keys are invalid).'
                );
            }
            throw new AXF_CLS_PluggyAuthException('Falha ao autenticar na API da Pluggy (HTTP ' + res.getStatusCode() + '): ' + details);
        }

        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String apiKey = (String) responseBody.get('apiKey');

        // Debug adicional para garantir que a chave foi extraída com sucesso do JSON
        System.debug('ApiKey Extraída: ' + apiKey);

        if (String.isBlank(apiKey)) {
            throw new AXF_CLS_PluggyAuthException('A resposta de autenticação da Pluggy não contém um apiKey.');
        }

        return apiKey;
    }

    private static String getFromCache() {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition.contains(CACHE_KEY)) {
                return (String) partition.get(CACHE_KEY);
            }
        } catch (Cache.Org.OrgCacheException e) {
            // Partição de cache indisponível ou sem capacidade alocada: segue sem cache.
        }
        return null;
    }

    private static void storeInCache(String apiKey) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            partition.put(CACHE_KEY, apiKey, CACHE_TTL_SECONDS);
        } catch (Cache.Org.OrgCacheException e) {
            // Partição de cache indisponível ou sem capacidade alocada: apiKey será obtido novamente na próxima chamada.
        }
    }
}