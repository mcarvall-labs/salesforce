public with sharing class AXF_CLS_CTRL_PluggyWizard {
  public class WizardState {
    @AuraEnabled
    public Boolean hasCredentials;
    @AuraEnabled
    public Integer connectionCount;
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
    @AuraEnabled
    public String holder;
  }

  public class ConnectionOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String label;
  }

  @AuraEnabled(cacheable=false)
  public static WizardState getState() {
    WizardState state = new WizardState();
    state.hasCredentials = new ALT_CLS_PluggyCredential().hasCredentials();
    state.connectionCount = new ALT_CLS_PluggyConnection().countConnections();
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
  public static List<ConnectionOption> getConnections() {
    List<ConnectionOption> options = new List<ConnectionOption>();
    for (
      ALT_CLS_PluggyConnection.Option option : new ALT_CLS_PluggyConnection()
        .options()
    ) {
      ConnectionOption item = new ConnectionOption();
      item.id = option.id;
      item.label = option.label;
      options.add(item);
    }
    return options;
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
      item.holder = linked.holder;
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
