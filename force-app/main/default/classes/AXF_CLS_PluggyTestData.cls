/**
 * @description Shared builders for the AXF-11 Pluggy tests. Grants the running user the
 * integration permission set so the services' USER_MODE queries/DML pass FLS on the
 * freshly deployed AXF_OBJ_PluggyConnection__c fields.
 */
@IsTest
public class AXF_CLS_PluggyTestData {
  public static void grantIntegrationAccess() {
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_PluggyIntegration'
      LIMIT 1
    ];
    Id uid = UserInfo.getUserId();
    Integer existing = [
      SELECT COUNT()
      FROM PermissionSetAssignment
      WHERE AssigneeId = :uid AND PermissionSetId = :ps.Id
    ];
    if (existing > 0) {
      return;
    }
    User u = new User(Id = uid);
    System.runAs(u) {
      insert new PermissionSetAssignment(
        AssigneeId = uid,
        PermissionSetId = ps.Id
      );
    }
  }

  public static AXF_OBJ_PluggyConnection__c connection(String itemId) {
    grantIntegrationAccess();
    AXF_OBJ_PluggyConnection__c c = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_EXI_PluggyItemId__c = itemId,
      AXF_CON_PKL_ConsentState__c = 'ACTIVE',
      AXF_CON_PKL_CollectionState__c = 'ACTIVE',
      AXF_CON_TXT_InstitutionName__c = 'Test Bank'
    );
    insert c;
    return c;
  }

  public static void config(
    Boolean globalPaused,
    String activeSlot,
    String rotationState
  ) {
    insert new AXF_PluggyIntegrationConfig__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      AXF_PIC_BOL_CollectionGloballyPaused__c = globalPaused,
      AXF_PIC_BOL_WebhookEnabled__c = true,
      AXF_PIC_TXT_ActiveSlot__c = activeSlot,
      AXF_PIC_TXT_RotationState__c = rotationState
    );
  }

  // --- AXF-12 sync helpers ---

  /** @description The approved sync policy, for AXF_CLS_PluggySyncPolicy.overrideRecord. */
  public static AXF_PluggySyncPolicy__mdt syncPolicy(
    Integer pageSize,
    Integer checkpointEveryPages,
    Integer maxAttempts
  ) {
    return new AXF_PluggySyncPolicy__mdt(
      AXF_PSP_NUM_PageSize__c = pageSize,
      AXF_PSP_NUM_CheckpointEveryPages__c = checkpointEveryPages,
      AXF_PSP_NUM_BackoffSeconds__c = 30,
      AXF_PSP_NUM_MaxAttempts__c = maxAttempts,
      AXF_PSP_NUM_MaxActiveRunsPerScope__c = 1,
      AXF_PSP_NUM_DailyScheduleHour__c = 3,
      AXF_PSP_NUM_InactivityMinutesToTerminal__c = 15,
      AXF_PSP_TXT_ScheduleTimeZone__c = 'America/Sao_Paulo'
    );
  }

  public static AXF_OBJ_BankAccount__c bankAccount(
    Id connectionId,
    String pluggyAccountId,
    Boolean available
  ) {
    AXF_OBJ_BankAccount__c b = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Connection__c = connectionId,
      AXF_BA_EXI_PluggyAccountId__c = pluggyAccountId,
      AXF_BA_PKL_AvailabilityState__c = available ? 'AVAILABLE' : 'CUSTODY',
      AXF_BA_TXT_InstitutionName__c = 'Banco Exemplo',
      AXF_BA_TXT_NumberMasked__c = '****0001',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_NUM_Version__c = 0
    );
    Database.insert(b, AccessLevel.SYSTEM_MODE);
    return b;
  }

  public static AXF_OBJ_CreditCard__c creditCard(
    Id connectionId,
    String pluggyAccountId,
    Boolean available
  ) {
    AXF_OBJ_CreditCard__c c = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Connection__c = connectionId,
      AXF_CC_EXI_PluggyAccountId__c = pluggyAccountId,
      AXF_CC_PKL_AvailabilityState__c = available ? 'AVAILABLE' : 'CUSTODY',
      AXF_CC_TXT_InstitutionName__c = 'Banco Exemplo',
      AXF_CC_TXT_LastFourMasked__c = '0002',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_NUM_Version__c = 0
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    return c;
  }

  /**
   * @description One page body for the /v2/transactions mock: fictitious rows only, no real
   * counterparties. `nextCursor` null => last page. Each row: {id, amount, type}.
   */
  public static String txPage(
    List<Map<String, Object>> rows,
    String nextCursor
  ) {
    List<String> objs = new List<String>();
    for (Map<String, Object> r : rows) {
      String id = (String) r.get('id');
      Object amount = r.get('amount');
      String type = (String) r.get('type');
      String txDate = r.containsKey('date')
        ? (String) r.get('date')
        : '2026-09-04T12:00:00.000Z';
      String status = r.containsKey('status')
        ? (String) r.get('status')
        : 'POSTED';
      String extra = '';
      if (r.get('billId') != null) {
        extra =
          ',"creditCardMetadata":{"billId":"' +
          (String) r.get('billId') +
          '","billForecastDate":"2026-09-15T00:00:00.000Z"}';
      }
      objs.add(
        '{"id":"' +
          id +
          '","description":"COMPRA EXEMPLO","descriptionRaw":"COMPRA EXEMPLO LTDA",' +
          '"currencyCode":"BRL","amount":' +
          String.valueOf(amount) +
          ',"date":"' +
          txDate +
          '","status":"' +
          status +
          '","type":"' +
          type +
          '","operationType":"PIX","order":1' +
          extra +
          '}'
      );
    }
    String next = (nextCursor == null) ? 'null' : '"' + nextCursor + '"';
    return '{"results":[' + String.join(objs, ',') + '],"next":' + next + '}';
  }
}
