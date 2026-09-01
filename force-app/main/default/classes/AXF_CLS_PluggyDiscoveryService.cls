/**
 * @description Discovers the bank accounts and credit cards behind a configured Pluggy
 * connection (AXF-84, Fechamento G5). Uses only the Item ID stored on the connection and
 * that application's credentials — no MeuPluggy link, no global GET /items list.
 *
 * Contract honoured:
 *  - discovery is a confirmable step distinct from transaction sync (AC1/AC7);
 *  - identity/origin/currency come from the API response and AXF-13 (AC2); replay upserts
 *    the same records, never duplicates;
 *  - a discovered account/card enters CUSTODY and is unavailable until a holder is
 *    confirmed by AXF-85 (AC3);
 *  - zero sources after processing all informed connections => an explicit "none found",
 *    never confused with an error or a partial result (AC4);
 *  - interruption / partial pagination / revocation => the run state reflects it and a
 *    partial catalogue is never presented as complete (AC5);
 *  - callers without authority are denied; names/numbers/existence are not revealed (AC6);
 *  - no full history import, no holder choice, no final-balance claim (AC7).
 *
 * Ordering: all reads, then all callouts, then all DML — so a callout is never blocked by
 * pending uncommitted work.
 */
public with sharing class AXF_CLS_PluggyDiscoveryService {
  @TestVisible
  private static Boolean canDiscoverOverride;

  @TestVisible
  private AXF_CLS_PluggyHttpClient clientForTests;

  @TestVisible
  private AXF_CLS_PluggyConsentService consentServiceForTests;

  private static final Integer MAX_PAGES_PER_RUN = 10;
  private static final Integer PAGE_SIZE = 200;

  public class DiscoveryResult {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Integer accountsFound;
    @AuraEnabled
    public Integer cardsFound;
    @AuraEnabled
    public Boolean complete;
    @AuraEnabled
    public String message;
  }

  public class DiscoveredSourceDTO {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String kind; // BANK | CARD
    @AuraEnabled
    public String institution;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public String availability; // CUSTODY | AVAILABLE
    @AuraEnabled
    public Boolean hasHolder;
  }

  private Boolean callerCanDiscover() {
    if (canDiscoverOverride != null) {
      return canDiscoverOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  private AXF_CLS_PluggyHttpClient client() {
    return clientForTests != null
      ? clientForTests
      : new AXF_CLS_PluggyHttpClient();
  }

  private AXF_CLS_PluggyConsentService consentService() {
    return consentServiceForTests != null
      ? consentServiceForTests
      : new AXF_CLS_PluggyConsentService();
  }

  /**
   * @description Runs (or resumes) discovery for one connection. Bounded to MAX_PAGES_PER_RUN
   * callouts; if more pages remain the run is left FAILED_RETRYABLE with a cursor for a
   * follow-up (a Queueable or a re-invocation).
   */
  public DiscoveryResult startOrResume(Id connectionId) {
    if (!callerCanDiscover()) {
      throw new AXF_CLS_PluggyDiscoveryException(
        'Voce nao tem autorizacao para descobrir fontes.'
      );
    }

    // ---- reads ----
    AXF_OBJ_PluggyConnection__c conn = [
      SELECT
        Id,
        AXF_CON_EXI_PluggyItemId__c,
        AXF_CON_PKL_ConsentState__c,
        AXF_CON_PKL_CollectionState__c,
        AXF_CON_TXT_InstitutionName__c,
        AXF_CON_TXT_ConnectorId__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
      WITH USER_MODE
      LIMIT 1
    ];

    new AXF_CLS_PluggyCollectionControlService()
      .assertCollectionAllowed(connectionId);

    String runKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'inr-v1', connectionId, 'ACCOUNTS' }
    );
    List<AXF_OBJ_IntegrationRun__c> runs = [
      SELECT
        Id,
        AXF_INR_PKL_State__c,
        AXF_INR_NUM_Cursor__c,
        AXF_INR_NUM_Attempt__c,
        AXF_INR_NUM_AccountsFound__c,
        AXF_INR_NUM_CardsFound__c,
        AXF_INR_NUM_Version__c,
        AXF_INR_DT_Watermark__c
      FROM AXF_OBJ_IntegrationRun__c
      WHERE AXF_INR_EXI_RunKey__c = :runKey
      WITH USER_MODE
      LIMIT 1
    ];
    AXF_OBJ_IntegrationRun__c run = runs.isEmpty() ? null : runs[0];

    if (
      run != null &&
      run.AXF_INR_PKL_State__c == 'RUNNING' &&
      run.AXF_INR_DT_Watermark__c != null &&
      run.AXF_INR_DT_Watermark__c > Datetime.now().addMinutes(-15)
    ) {
      throw new AXF_CLS_PluggyDiscoveryException(
        'CONFLICT: ja existe uma descoberta em andamento para esta conexao.'
      );
    }

    Integer startPage = (run == null ||
      run.AXF_INR_NUM_Cursor__c == null)
      ? 1
      : (Integer) run.AXF_INR_NUM_Cursor__c + 1;

    // ---- callouts ----
    String correlationId = AXF_CLS_PluggyHttpClient.newCorrelationId();
    AXF_CLS_PluggyHttpClient http = client();
    String itemId = conn.AXF_CON_EXI_PluggyItemId__c;

    AXF_CLS_PluggyHttpClient.PluggyResponse itemRes = http.getJson(
      '/items/' + itemId
    );
    if (itemRes.statusCode == 404) {
      return persistFailure(
        run,
        runKey,
        connectionId,
        'FAILED_TERMINAL',
        startPage,
        'Conexao nao encontrada na Pluggy. Reautorize na aplicacao correta.',
        0,
        0
      );
    }
    if (!itemRes.isSuccess) {
      return persistFailure(
        run,
        runKey,
        connectionId,
        'RESULT_UNKNOWN',
        startPage,
        AXF_CLS_PluggyHttpClient.sanitizedError(
          'GET /items',
          itemRes.statusCode,
          correlationId
        ),
        0,
        0
      );
    }

    List<Map<String, Object>> rawAccounts = new List<Map<String, Object>>();
    Integer page = startPage;
    Integer pagesProcessed = 0;
    Integer totalPages = 1;
    Boolean transportUnknown = false;

    while (page <= totalPages && pagesProcessed < MAX_PAGES_PER_RUN) {
      AXF_CLS_PluggyHttpClient.PluggyResponse res;
      try {
        res = http.getJson(
          '/accounts?itemId=' +
            itemId +
            '&page=' +
            page +
            '&pageSize=' +
            PAGE_SIZE
        );
      } catch (AXF_CLS_PluggyIntegrationException unknown) {
        transportUnknown = true;
        break;
      }
      if (res.statusCode == 403 || res.statusCode == 401) {
        return persistFailure(
          run,
          runKey,
          connectionId,
          'FAILED_TERMINAL',
          page - 1,
          'A aplicacao nao tem autorizacao para listar as contas desta conexao. Reautorize.',
          0,
          0
        );
      }
      if (!res.isSuccess || res.body == null) {
        transportUnknown = true;
        break;
      }
      Object tp = res.body.get('totalPages');
      if (tp != null) {
        totalPages = Integer.valueOf(String.valueOf(tp));
      }
      for (Object o : (List<Object>) res.body.get('results')) {
        rawAccounts.add((Map<String, Object>) o);
      }
      page++;
      pagesProcessed++;
    }

    // Revalidate consent after discovery callouts (AC5) — first DML happens here.
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = consentService()
      .refresh(connectionId);

    // ---- DML ----
    if (transportUnknown) {
      return persistFailure(
        run,
        runKey,
        connectionId,
        'RESULT_UNKNOWN',
        page - 1,
        AXF_CLS_PluggyHttpClient.sanitizedError(
          'GET /accounts',
          null,
          correlationId
        ),
        0,
        0
      );
    }

    Map<String, Object> counts = upsertSources(conn, rawAccounts);
    Integer accountsFound = (Integer) counts.get('bank');
    Integer cardsFound = (Integer) counts.get('card');

    Boolean morePages = (page <= totalPages);
    String state;
    String message;
    if (snap.consentState != 'ACTIVE') {
      state = 'FAILED_TERMINAL';
      message = 'Consentimento deixou de estar ativo durante a descoberta. Catalogo incompleto.';
    } else if (morePages) {
      state = 'FAILED_RETRYABLE';
      message = 'Descoberta parcial: retome para processar as paginas restantes.';
    } else if (accountsFound + cardsFound == 0) {
      state = 'SUCCEEDED';
      message = 'Nenhuma conta ou cartao encontrado nas conexoes informadas. Autorize na aplicacao correta.';
    } else {
      state = 'SUCCEEDED';
      message =
        accountsFound +
        ' conta(s) e ' +
        cardsFound +
        ' cartao(oes) em custodia. Confirme os titulares.';
    }

    AXF_OBJ_IntegrationRun__c saved = persistRun(
      run,
      runKey,
      connectionId,
      state,
      morePages ? page - 1 : totalPages,
      accountsFound,
      cardsFound,
      message
    );

    DiscoveryResult r = new DiscoveryResult();
    r.connectionId = connectionId;
    r.state = state;
    r.accountsFound = accountsFound;
    r.cardsFound = cardsFound;
    r.complete = (state == 'SUCCEEDED');
    r.message = message;
    return r;
  }

  /** @description Current discovery run state for a connection (read-only). */
  public DiscoveryResult status(Id connectionId) {
    String runKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'inr-v1', connectionId, 'ACCOUNTS' }
    );
    DiscoveryResult r = new DiscoveryResult();
    r.connectionId = connectionId;
    for (AXF_OBJ_IntegrationRun__c run : [
      SELECT
        AXF_INR_PKL_State__c,
        AXF_INR_NUM_AccountsFound__c,
        AXF_INR_NUM_CardsFound__c,
        AXF_INR_TXT_Message__c
      FROM AXF_OBJ_IntegrationRun__c
      WHERE AXF_INR_EXI_RunKey__c = :runKey
      WITH USER_MODE
      LIMIT 1
    ]) {
      r.state = run.AXF_INR_PKL_State__c;
      r.accountsFound = (Integer) run.AXF_INR_NUM_AccountsFound__c;
      r.cardsFound = (Integer) run.AXF_INR_NUM_CardsFound__c;
      r.complete = (run.AXF_INR_PKL_State__c == 'SUCCEEDED');
      r.message = run.AXF_INR_TXT_Message__c;
    }
    return r;
  }

  /** @description Sources discovered for a connection, with real per-source status (AC7). */
  public List<DiscoveredSourceDTO> discovered(Id connectionId) {
    List<DiscoveredSourceDTO> out = new List<DiscoveredSourceDTO>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT
        Id,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_LKP_Account__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c = :connectionId
      WITH USER_MODE
      ORDER BY AXF_BA_TXT_InstitutionName__c NULLS LAST
    ]) {
      DiscoveredSourceDTO d = new DiscoveredSourceDTO();
      d.recordId = b.Id;
      d.kind = 'BANK';
      d.institution = b.AXF_BA_TXT_InstitutionName__c;
      d.currencyIsoCode = b.AXF_BA_TXT_CurrencyIsoCode__c;
      d.availability = b.AXF_BA_PKL_AvailabilityState__c;
      d.hasHolder = b.AXF_BA_LKP_Account__c != null;
      out.add(d);
    }
    for (AXF_OBJ_CreditCard__c c : [
      SELECT
        Id,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_LKP_Account__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Connection__c = :connectionId
      WITH USER_MODE
      ORDER BY AXF_CC_TXT_InstitutionName__c NULLS LAST
    ]) {
      DiscoveredSourceDTO d = new DiscoveredSourceDTO();
      d.recordId = c.Id;
      d.kind = 'CARD';
      d.institution = c.AXF_CC_TXT_InstitutionName__c;
      d.currencyIsoCode = c.AXF_CC_TXT_CurrencyIsoCode__c;
      d.availability = c.AXF_CC_PKL_AvailabilityState__c;
      d.hasHolder = c.AXF_CC_LKP_Account__c != null;
      out.add(d);
    }
    return out;
  }

  // ---------------------------------------------------------------------------

  private Map<String, Object> upsertSources(
    AXF_OBJ_PluggyConnection__c conn,
    List<Map<String, Object>> rawAccounts
  ) {
    List<AXF_OBJ_BankAccount__c> banks = new List<AXF_OBJ_BankAccount__c>();
    List<AXF_OBJ_CreditCard__c> cards = new List<AXF_OBJ_CreditCard__c>();

    for (Map<String, Object> a : rawAccounts) {
      String providerId = str(a.get('id'));
      if (String.isBlank(providerId)) {
        continue;
      }
      // AXF-13: the provider id is the idempotent upsert key.
      String key = AXF_CLS_PluggyFactIdentity.fromProviderId(providerId)
        .pluggyId;
      String type = str(a.get('type'));
      Boolean isCard = type == 'CREDIT';

      if (isCard) {
        Map<String, Object> cd = (Map<String, Object>) a.get('creditData');
        cards.add(
          new AXF_OBJ_CreditCard__c(
            AXF_CC_EXI_PluggyAccountId__c = key,
            AXF_CC_LKP_Connection__c = conn.Id,
            AXF_CC_PKL_AvailabilityState__c = 'CUSTODY',
            AXF_CC_TXT_InstitutionName__c = conn.AXF_CON_TXT_InstitutionName__c,
            AXF_CC_TXT_ConnectorId__c = conn.AXF_CON_TXT_ConnectorId__c,
            AXF_CC_TXT_CurrencyIsoCode__c = str(a.get('currencyCode')),
            AXF_CC_TXT_Brand__c = cd == null ? null : str(cd.get('brand')),
            AXF_CC_TXT_Level__c = cd == null ? null : str(cd.get('level')),
            AXF_CC_TXT_LastFourMasked__c = maskLast4(str(a.get('number'))),
            AXF_CC_CUR_CreditLimit__c = cd == null
              ? null
              : dec(cd.get('creditLimit')),
            AXF_CC_CUR_AvailableLimit__c = cd == null
              ? null
              : dec(cd.get('availableCreditLimit')),
            AXF_CC_DT_DiscoveredAt__c = Datetime.now()
          )
        );
      } else {
        banks.add(
          new AXF_OBJ_BankAccount__c(
            AXF_BA_EXI_PluggyAccountId__c = key,
            AXF_BA_LKP_Connection__c = conn.Id,
            AXF_BA_PKL_AvailabilityState__c = 'CUSTODY',
            AXF_BA_TXT_InstitutionName__c = conn.AXF_CON_TXT_InstitutionName__c,
            AXF_BA_TXT_ConnectorId__c = conn.AXF_CON_TXT_ConnectorId__c,
            AXF_BA_TXT_CurrencyIsoCode__c = str(a.get('currencyCode')),
            AXF_BA_CUR_CurrentBalance__c = dec(a.get('balance')),
            AXF_BA_TXT_Type__c = str(a.get('subtype')),
            AXF_BA_TXT_NumberMasked__c = maskLast4(str(a.get('number'))),
            AXF_BA_DT_DiscoveredAt__c = Datetime.now()
          )
        );
      }
    }

    if (!banks.isEmpty()) {
      upsert as user banks AXF_BA_EXI_PluggyAccountId__c;
    }
    if (!cards.isEmpty()) {
      upsert as user cards AXF_CC_EXI_PluggyAccountId__c;
    }
    return new Map<String, Object>{
      'bank' => banks.size(),
      'card' => cards.size()
    };
  }

  private AXF_OBJ_IntegrationRun__c persistRun(
    AXF_OBJ_IntegrationRun__c existing,
    String runKey,
    Id connectionId,
    String state,
    Integer cursor,
    Integer accounts,
    Integer cardsCount,
    String message
  ) {
    AXF_OBJ_IntegrationRun__c run = (existing != null)
      ? existing
      : new AXF_OBJ_IntegrationRun__c(
          AXF_INR_EXI_RunKey__c = runKey,
          AXF_INR_LKP_Connection__c = connectionId,
          AXF_INR_PKL_Product__c = 'ACCOUNTS',
          AXF_INR_NUM_Attempt__c = 0,
          AXF_INR_NUM_Version__c = 0
        );
    run.AXF_INR_PKL_State__c = state;
    run.AXF_INR_NUM_Cursor__c = cursor;
    run.AXF_INR_NUM_AccountsFound__c = accounts;
    run.AXF_INR_NUM_CardsFound__c = cardsCount;
    run.AXF_INR_TXT_Message__c = truncate(message);
    run.AXF_INR_DT_Watermark__c = Datetime.now();
    run.AXF_INR_NUM_Attempt__c =
      (run.AXF_INR_NUM_Attempt__c == null ? 0 : run.AXF_INR_NUM_Attempt__c) + 1;
    run.AXF_INR_NUM_Version__c =
      (run.AXF_INR_NUM_Version__c == null ? 0 : run.AXF_INR_NUM_Version__c) + 1;
    run.AXF_INR_TXT_ActiveToken__c = (state == 'RUNNING')
      ? AXF_CLS_PluggyHttpClient.newCorrelationId()
      : null;
    upsert as user run AXF_INR_EXI_RunKey__c;
    return run;
  }

  private DiscoveryResult persistFailure(
    AXF_OBJ_IntegrationRun__c existing,
    String runKey,
    Id connectionId,
    String state,
    Integer cursor,
    String message,
    Integer accounts,
    Integer cardsCount
  ) {
    persistRun(
      existing,
      runKey,
      connectionId,
      state,
      cursor,
      accounts,
      cardsCount,
      message
    );
    DiscoveryResult r = new DiscoveryResult();
    r.connectionId = connectionId;
    r.state = state;
    r.accountsFound = accounts;
    r.cardsFound = cardsCount;
    r.complete = false;
    r.message = message;
    return r;
  }

  private static String maskLast4(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String digits = raw.replaceAll('[^0-9]', '');
    if (digits.length() <= 4) {
      return '****' + digits;
    }
    return '****' + digits.substring(digits.length() - 4);
  }

  private static String str(Object o) {
    return o == null ? null : String.valueOf(o);
  }

  private static Decimal dec(Object o) {
    if (o == null) {
      return null;
    }
    try {
      return Decimal.valueOf(String.valueOf(o));
    } catch (Exception e) {
      return null;
    }
  }

  private static String truncate(String s) {
    if (s == null) {
      return null;
    }
    return s.length() > 255 ? s.substring(0, 255) : s;
  }
}
