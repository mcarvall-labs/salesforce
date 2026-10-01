/**
 * @description Validates a Pluggy Item Id against the Pluggy API and registers it as a
 * PluggyConnection of a holder.
 */
public with sharing class ALT_CLS_PluggyConnection {
  public class Result {
    public Boolean success = false;
    public String message;
    public Id connectionId;
  }

  private static final String ITEM_ENDPOINT = 'callout:AXF_NC_Pluggy_API/items/';

  public Result create(Id holderId, String institution, String itemId) {
    Result r = new Result();
    if (
      holderId == null ||
      String.isBlank(institution) ||
      String.isBlank(itemId)
    ) {
      r.message = 'Informe o titular, a instituição e o Item Id.';
      return r;
    }
    String trimmedItemId = itemId.trim();
    try {
      validateItem(trimmedItemId);
    } catch (ALT_CLS_PluggyCredential.PluggyException e) {
      r.message = e.getMessage();
      return r;
    }
    AXF_OBJ_PluggyConnection__c connection = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_MD_Holder__c = holderId,
      AXF_CON_PKL_Institution__c = institution,
      AXF_CON_EXI_PluggyItemId__c = trimmedItemId,
      AXF_CON_PKL_Status__c = 'Active'
    );
    try {
      insert as user connection;
      r.success = true;
      r.connectionId = connection.Id;
      r.message = 'Conexão criada.';
    } catch (DmlException e) {
      r.message = e.getDmlType(0) == StatusCode.DUPLICATE_VALUE
        ? 'Este Item Id já está cadastrado.'
        : 'Não foi possível criar a conexão: ' + e.getDmlMessage(0);
    }
    return r;
  }

  public Integer countConnections() {
    return [SELECT COUNT() FROM AXF_OBJ_PluggyConnection__c WITH USER_MODE];
  }

  private void validateItem(String itemId) {
    String apiKey = new ALT_CLS_PluggyCredential().requestApiKey();
    HttpRequest req = new HttpRequest();
    req.setEndpoint(ITEM_ENDPOINT + EncodingUtil.urlEncode(itemId, 'UTF-8'));
    req.setMethod('GET');
    req.setHeader('X-API-KEY', apiKey);
    HttpResponse res;
    try {
      res = new Http().send(req);
    } catch (Exception e) {
      throw new ALT_CLS_PluggyCredential.PluggyException(
        'Não foi possível contatar o Pluggy (' + e.getTypeName() + ').'
      );
    }
    if (res.getStatusCode() == 404 || res.getStatusCode() == 400) {
      throw new ALT_CLS_PluggyCredential.PluggyException(
        'Item Id não encontrado no Pluggy.'
      );
    }
    if (res.getStatusCode() != 200) {
      throw new ALT_CLS_PluggyCredential.PluggyException(
        'O Pluggy respondeu com erro (HTTP ' + res.getStatusCode() + ').'
      );
    }
  }
}
