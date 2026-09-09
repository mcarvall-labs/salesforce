/** @description Durable, authorized deletion hints; financial evidence is created only after provider verification. */
public with sharing class ALT_CLS_SourceDeleteInbox {
  public static final String PRODUCT = 'SOURCE_DELETIONS';
  public class Work {
    public Id runId;
    public AXF_PluggyWebhookEvent__e event;
    public List<String> ids;
    public Integer cursor;
    public Decimal version;
  }

  /** @description Persists bounded identifiers before asynchronous acknowledgement. Replays retain progress. */
  public List<Id> admit(List<AXF_PluggyWebhookEvent__e> events) {
    Set<String> itemIds = new Set<String>();
    for (AXF_PluggyWebhookEvent__e event : events)
      itemIds.add(event.AXF_PWE_TXT_ObservedItemId__c);
    Map<String, Id> connections = new Map<String, Id>();
    for (AXF_OBJ_PluggyConnection__c connection : [
      SELECT Id, AXF_CON_EXI_PluggyItemId__c, AXF_CON_TXT_ObservedItemId__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE
        AXF_CON_EXI_PluggyItemId__c IN :itemIds
        OR AXF_CON_TXT_ObservedItemId__c IN :itemIds
      WITH USER_MODE
    ]) {
      connections.put(connection.AXF_CON_EXI_PluggyItemId__c, connection.Id);
      if (String.isNotBlank(connection.AXF_CON_TXT_ObservedItemId__c))
        connections.put(
          connection.AXF_CON_TXT_ObservedItemId__c,
          connection.Id
        );
    }
    Map<String, AXF_OBJ_IntegrationRun__c> candidates = new Map<String, AXF_OBJ_IntegrationRun__c>();
    for (AXF_PluggyWebhookEvent__e event : events) {
      Id connectionId = connections.get(event.AXF_PWE_TXT_ObservedItemId__c);
      if (connectionId == null)
        continue; // No authorized local source can be affected.
      List<String> ids = identifiers(event);
      String key = AXF_CLS_IdentityFraming.key(
        new List<Object>{
          'source-deletion-inbox-v1',
          connectionId,
          PRODUCT,
          event.AXF_PWE_TXT_AccountId__c,
          JSON.serialize(ids)
        }
      );
      candidates.put(
        key,
        new AXF_OBJ_IntegrationRun__c(
          AXF_INR_EXI_RunKey__c = key,
          AXF_INR_LKP_Connection__c = connectionId,
          AXF_INR_PKL_Product__c = PRODUCT,
          AXF_INR_PKL_State__c = 'PENDING',
          AXF_INR_NUM_Cursor__c = 0,
          AXF_INR_NUM_Attempt__c = 0,
          AXF_INR_NUM_Version__c = 0,
          AXF_INR_TAL_SourceDeleteIds__c = JSON.serialize(ids),
          AXF_INR_TXT_SourceAccountId__c = event.AXF_PWE_TXT_AccountId__c,
          AXF_INR_TXT_SourceItemId__c = event.AXF_PWE_TXT_ObservedItemId__c,
          AXF_INR_TXT_CorrelationId__c = event.AXF_PWE_TXT_CorrelationId__c
        )
      );
    }
    Set<String> keys = candidates.keySet();
    List<Id> pending = new List<Id>();
    for (AXF_OBJ_IntegrationRun__c existing : [
      SELECT Id, AXF_INR_EXI_RunKey__c, AXF_INR_PKL_State__c
      FROM AXF_OBJ_IntegrationRun__c
      WHERE AXF_INR_EXI_RunKey__c IN :keys
      WITH USER_MODE
    ]) {
      candidates.remove(existing.AXF_INR_EXI_RunKey__c);
      if (
        existing.AXF_INR_PKL_State__c != 'SUCCEEDED' &&
        existing.AXF_INR_PKL_State__c != 'FAILED_TERMINAL'
      )
        pending.add(existing.Id);
    }
    List<AXF_OBJ_IntegrationRun__c> fresh = candidates.values();
    if (!fresh.isEmpty())
      insert as user fresh;
    for (AXF_OBJ_IntegrationRun__c run : fresh)
      pending.add(run.Id);
    return pending;
  }

  /** @description Read only: worker can perform all callouts before checkpoint DML. */
  public Work load(Id runId) {
    AXF_OBJ_IntegrationRun__c run = read(runId, false);
    if (run == null || run.AXF_INR_PKL_State__c == 'SUCCEEDED')
      return null;
    Work work = new Work();
    work.runId = run.Id;
    work.cursor = run.AXF_INR_NUM_Cursor__c == null
      ? 0
      : Integer.valueOf(run.AXF_INR_NUM_Cursor__c);
    work.version = run.AXF_INR_NUM_Version__c;
    work.ids = (List<String>) JSON.deserialize(
      run.AXF_INR_TAL_SourceDeleteIds__c,
      List<String>.class
    );
    work.event = new AXF_PluggyWebhookEvent__e(
      AXF_PWE_TXT_EventType__c = 'transactions/deleted',
      AXF_PWE_TXT_ObservedItemId__c = run.AXF_INR_TXT_SourceItemId__c,
      AXF_PWE_TXT_AccountId__c = run.AXF_INR_TXT_SourceAccountId__c,
      AXF_PWE_TXT_CorrelationId__c = run.AXF_INR_TXT_CorrelationId__c,
      AXF_PWE_TAL_TransactionIds__c = run.AXF_INR_TAL_SourceDeleteIds__c
    );
    return work;
  }

  /** @description Advances only the observed checkpoint; duplicate workers cannot skip identifiers. */
  public Boolean complete(Work work, Integer processedCount) {
    AXF_OBJ_IntegrationRun__c run = read(work.runId, true);
    if (run == null)
      throw new AXF_CLS_ReviewQueueException('Deletion run is unavailable.');
    if (run.AXF_INR_PKL_State__c == 'SUCCEEDED')
      return false;
    if (
      run.AXF_INR_NUM_Version__c != work.version ||
      run.AXF_INR_NUM_Cursor__c != work.cursor
    )
      return true;
    if (processedCount <= 0 || work.cursor + processedCount > work.ids.size())
      throw new AXF_CLS_ReviewQueueException('Invalid deletion checkpoint.');
    Integer nextCursor = work.cursor + processedCount;
    Boolean more = nextCursor < work.ids.size();
    update as user new AXF_OBJ_IntegrationRun__c(
      Id = run.Id,
      AXF_INR_NUM_Cursor__c = nextCursor,
      AXF_INR_NUM_Version__c = work.version + 1,
      AXF_INR_NUM_Attempt__c = 0,
      AXF_INR_PKL_State__c = more ? 'PENDING' : 'SUCCEEDED',
      AXF_INR_TXT_Message__c = more
        ? 'Deletion verification checkpoint recorded.'
        : 'Deletion verification completed.'
    );
    return more;
  }

  /** @description Records a bounded failure without discarding the original hints or later work. */
  public Boolean fail(Work work) {
    AXF_OBJ_IntegrationRun__c run = read(work.runId, true);
    if (run == null || run.AXF_INR_PKL_State__c == 'SUCCEEDED')
      return false;
    if (
      run.AXF_INR_NUM_Cursor__c != work.cursor ||
      run.AXF_INR_NUM_Version__c != work.version
    )
      return true;
    Integer attempt = run.AXF_INR_NUM_Attempt__c == null
      ? 1
      : Integer.valueOf(run.AXF_INR_NUM_Attempt__c) + 1;
    Boolean retry = attempt < AXF_CLS_PluggySyncPolicy.current().maxAttempts;
    update as user new AXF_OBJ_IntegrationRun__c(
      Id = run.Id,
      AXF_INR_NUM_Attempt__c = attempt,
      AXF_INR_NUM_Version__c = work.version + 1,
      AXF_INR_PKL_State__c = retry ? 'FAILED_RETRYABLE' : 'FAILED_TERMINAL',
      AXF_INR_TXT_Message__c = retry
        ? 'Deletion verification will retry.'
        : 'Deletion verification requires an authorized retry; original identifiers retained.'
    );
    return retry;
  }

  private AXF_OBJ_IntegrationRun__c read(Id runId, Boolean lockRow) {
    List<AXF_OBJ_IntegrationRun__c> rows = (List<AXF_OBJ_IntegrationRun__c>) Database.queryWithBinds(
      'SELECT Id, AXF_INR_LKP_Connection__c, AXF_INR_PKL_State__c, AXF_INR_NUM_Cursor__c,' +
        ' AXF_INR_NUM_Attempt__c, AXF_INR_NUM_Version__c, AXF_INR_TAL_SourceDeleteIds__c,' +
        ' AXF_INR_TXT_SourceAccountId__c, AXF_INR_TXT_SourceItemId__c, AXF_INR_TXT_CorrelationId__c' +
        ' FROM AXF_OBJ_IntegrationRun__c WHERE Id = :runId AND AXF_INR_PKL_Product__c = :product' +
        (lockRow ? ' FOR UPDATE' : ''),
      new Map<String, Object>{ 'runId' => runId, 'product' => PRODUCT },
      AccessLevel.USER_MODE
    );
    if (rows.isEmpty())
      return null;
    Id connectionId = rows[0].AXF_INR_LKP_Connection__c;
    if (
      [
        SELECT COUNT()
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :connectionId
        WITH USER_MODE
      ] != 1
    )
      return null;
    return rows[0];
  }

  private List<String> identifiers(AXF_PluggyWebhookEvent__e event) {
    if (
      event.AXF_PWE_TXT_EventType__c != 'transactions/deleted' ||
      String.isBlank(event.AXF_PWE_TXT_AccountId__c)
    )
      throw new AXF_CLS_ReviewQueueException('Invalid deletion hint.');
    List<String> raw = (List<String>) JSON.deserialize(
      event.AXF_PWE_TAL_TransactionIds__c,
      List<String>.class
    );
    if (raw == null || raw.isEmpty() || raw.size() > 500)
      throw new AXF_CLS_ReviewQueueException('Invalid deletion batch.');
    for (String identifier : raw)
      if (String.isBlank(identifier) || identifier.length() > 255)
        throw new AXF_CLS_ReviewQueueException('Invalid deletion identifier.');
    List<String> result = new List<String>(new Set<String>(raw));
    result.sort();
    if (JSON.serialize(result).length() > 131072)
      throw new AXF_CLS_ReviewQueueException(
        'Deletion batch exceeds durable capacity.'
      );
    return result;
  }
}
