public with sharing class AXF_CLS_CTRL_PluggyWizard {
  public class WizardState {
    @AuraEnabled
    public Boolean hasCredentials;
    @AuraEnabled
    public Integer connectionCount;
    @AuraEnabled
    public Id latestConnectionId;
  }

  public class StepResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id connectionId;
  }

  public class LinkedItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String detail;
  }

  public class SyncResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<LinkedItem> items;
  }

  @AuraEnabled(cacheable=false)
  public static WizardState getState() {
    WizardState state = new WizardState();
    state.hasCredentials = new ALT_CLS_PluggyCredential().hasCredentials();
    state.connectionCount = new ALT_CLS_PluggyConnection().countConnections();
    state.latestConnectionId = new ALT_CLS_PluggyConnection()
      .latestConnectionId();
    return state;
  }

  @AuraEnabled
  public static StepResult saveCredentials(
    String clientId,
    String clientSecret
  ) {
    return toStepResult(
      new ALT_CLS_PluggyCredential().save(clientId, clientSecret)
    );
  }

  @AuraEnabled
  public static StepResult testCredentials() {
    return toStepResult(new ALT_CLS_PluggyCredential().testAuthentication());
  }

  @AuraEnabled
  public static StepResult createConnection(
    Id holderId,
    String institution,
    String itemId
  ) {
    ALT_CLS_PluggyConnection.Result result = new ALT_CLS_PluggyConnection()
      .create(holderId, institution, itemId);
    StepResult stepResult = new StepResult();
    stepResult.success = result.success;
    stepResult.message = result.message;
    stepResult.connectionId = result.connectionId;
    return stepResult;
  }

  @AuraEnabled
  public static SyncResult syncConnection(Id connectionId) {
    if (connectionId == null) {
      throw new AuraHandledException('Informe a conexão.');
    }
    ALT_CLS_PluggyAccountSync.Result result = new ALT_CLS_PluggyAccountSync()
      .sync(connectionId);
    SyncResult syncResult = new SyncResult();
    syncResult.success = result.success;
    syncResult.message = result.message;
    syncResult.items = getLinked(connectionId);
    return syncResult;
  }

  @AuraEnabled
  public static List<LinkedItem> getLinked(Id connectionId) {
    List<LinkedItem> items = new List<LinkedItem>();
    if (connectionId == null) {
      return items;
    }
    for (
      ALT_CLS_PluggyAccountSync.Linked linked : new ALT_CLS_PluggyAccountSync()
        .linked(connectionId)
    ) {
      LinkedItem item = new LinkedItem();
      item.id = linked.id;
      item.kind = linked.kind;
      item.name = linked.name;
      item.detail = linked.detail;
      items.add(item);
    }
    return items;
  }

  private static StepResult toStepResult(
    ALT_CLS_PluggyCredential.Result result
  ) {
    StepResult stepResult = new StepResult();
    stepResult.success = result.success;
    stepResult.message = result.message;
    return stepResult;
  }
}
