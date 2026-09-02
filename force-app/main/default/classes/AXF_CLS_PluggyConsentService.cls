/**
 * @description Captures and revalidates the consent behind an AXF_OBJ_PluggyConnection__c
 * from the Pluggy API, and drives AXF_CON_PKL_ConsentState__c (ACTIVE|STALE|REVOKED).
 * AXF-11 AC3/AC4, Fechamento G4-5.
 *
 * Rules honoured:
 *  - identity/ownership come from the API response (GET /items/<id>), never from the id;
 *  - the two Item IDs are preserved separately, never assumed equal (D-85);
 *  - expiresAt == null is stored as null and treated as "no expiry set", not "eternal"
 *    and not an error; a query error / missing consent is NOT "no expiry";
 *  - never invents purpose, term version or an account list that the API did not return;
 *  - STALE/REVOKED block new collection but keep collected data visible (marked stale).
 */
public with sharing class AXF_CLS_PluggyConsentService {
  private final AXF_CLS_PluggyHttpClient client;

  public AXF_CLS_PluggyConsentService() {
    this(new AXF_CLS_PluggyHttpClient());
  }

  @TestVisible
  private AXF_CLS_PluggyConsentService(AXF_CLS_PluggyHttpClient client) {
    this.client = client;
  }

  public class ConsentSnapshot {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public String consentState;
    @AuraEnabled
    public String institution;
    @AuraEnabled
    public String scope;
    @AuraEnabled
    public Datetime givenAt;
    @AuraEnabled
    public Datetime expiresAt;
    @AuraEnabled
    public Boolean collectionAllowed;
    @AuraEnabled
    public String message;
  }

  /**
   * @description Revalidates a single connection and persists the result. Returns a
   * sanitized snapshot for the UI. Never throws for an expected "consent gone" outcome —
   * that is a valid state transition, not an error.
   */
  public ConsentSnapshot refresh(Id connectionId) {
    AXF_OBJ_PluggyConnection__c conn = [
      SELECT
        Id,
        AXF_CON_EXI_PluggyItemId__c,
        AXF_CON_TXT_ObservedItemId__c,
        AXF_CON_PKL_ConsentState__c,
        AXF_CON_PKL_CollectionState__c,
        AXF_CON_TXT_InstitutionName__c,
        AXF_CON_TXT_ConnectorId__c,
        AXF_CON_TXT_ConsentId__c,
        AXF_CON_TXT_ConsentObservedItemId__c,
        AXF_CON_TAL_ConsentScope__c,
        AXF_CON_TXT_ConsentPurpose__c,
        AXF_CON_DT_ConsentGivenAt__c,
        AXF_CON_DT_ConsentExpiresAt__c,
        AXF_CON_TXT_ConsentVersion__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
      WITH USER_MODE
      LIMIT 1
    ];
    ConsentSnapshot out = applyRefresh(conn);
    update as user conn;
    return out;
  }

  /**
   * @description Revalidates every connection tied to any of the given observed Pluggy
   * Item IDs. Runs ALL callouts first and persists with a SINGLE DML at the end, so a
   * batch (a platform-event trigger delivering several webhooks) never trips a
   * callout-after-DML. Idempotent. Throws only on an unknown/transient integration
   * result, so the caller can ask the event bus for a retry.
   */
  public void refreshByItemIds(Set<String> pluggyItemIds) {
    if (pluggyItemIds == null || pluggyItemIds.isEmpty()) {
      return;
    }
    List<AXF_OBJ_PluggyConnection__c> conns = [
      SELECT
        Id,
        AXF_CON_EXI_PluggyItemId__c,
        AXF_CON_TXT_ObservedItemId__c,
        AXF_CON_PKL_ConsentState__c,
        AXF_CON_PKL_CollectionState__c,
        AXF_CON_TXT_InstitutionName__c,
        AXF_CON_TXT_ConnectorId__c,
        AXF_CON_TXT_ConsentId__c,
        AXF_CON_TXT_ConsentObservedItemId__c,
        AXF_CON_TAL_ConsentScope__c,
        AXF_CON_TXT_ConsentPurpose__c,
        AXF_CON_DT_ConsentGivenAt__c,
        AXF_CON_DT_ConsentExpiresAt__c,
        AXF_CON_TXT_ConsentVersion__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE
        AXF_CON_EXI_PluggyItemId__c IN :pluggyItemIds
        OR AXF_CON_TXT_ObservedItemId__c IN :pluggyItemIds
      WITH USER_MODE
    ];
    if (conns.isEmpty()) {
      return;
    }
    for (AXF_OBJ_PluggyConnection__c c : conns) {
      applyRefresh(c); // callouts + in-memory mutation, NO DML
    }
    update as user conns; // single DML, after every callout
  }

  /** @description Revalidates the connection(s) tied to one observed Pluggy Item ID. */
  public void refreshByItemId(String pluggyItemId) {
    refreshByItemIds(new Set<String>{ pluggyItemId });
  }

  /**
   * @description Runs the /items + /consents callouts for one connection and mutates it
   * in memory (consent fields, state, checkedAt). Does NO DML — the caller persists — so
   * a batch can finish every callout before the first update.
   */
  @TestVisible
  private ConsentSnapshot applyRefresh(AXF_OBJ_PluggyConnection__c conn) {
    String itemId = conn.AXF_CON_EXI_PluggyItemId__c;
    String newState = conn.AXF_CON_PKL_ConsentState__c;
    String message;

    // 1. Item — identity/ownership/status always from the response.
    AXF_CLS_PluggyHttpClient.PluggyResponse itemRes = client.getJson(
      '/items/' + itemId
    );
    if (itemRes.statusCode == 404) {
      newState = 'REVOKED';
      message = 'Conexao nao encontrada na Pluggy (404). Reautorize no provedor.';
    } else if (!itemRes.isSuccess) {
      // Unknown / transient: do not downgrade a previously ACTIVE consent on a blip.
      message = AXF_CLS_PluggyHttpClient.sanitizedError(
        'GET /items',
        itemRes.statusCode,
        itemRes.correlationId
      );
    } else {
      Map<String, Object> item = itemRes.body;
      String observed = str(item.get('id'));
      if (String.isNotBlank(observed)) {
        conn.AXF_CON_TXT_ObservedItemId__c = observed; // never becomes the key
      }
      Map<String, Object> connector = (Map<String, Object>) item.get(
        'connector'
      );
      if (connector != null) {
        conn.AXF_CON_TXT_InstitutionName__c = str(connector.get('name'));
        conn.AXF_CON_TXT_ConnectorId__c = str(connector.get('id'));
      }
      String itemStatus = str(item.get('status'));
      if (isLoginOrConsentError(itemStatus)) {
        newState = 'REVOKED';
        message = 'A instituicao reportou erro de login/consentimento. Reautorize no provedor.';
      } else if (isOutdated(itemStatus)) {
        newState = 'STALE';
        message = 'Dados desatualizados na origem. Nova coleta bloqueada ate reautorizar.';
      }
    }

    // 2. Consent details (best-effort; a 403 on the free plan is not proof of revocation).
    AXF_CLS_PluggyHttpClient.PluggyResponse consentRes = client.getJson(
      '/consents?itemId=' + itemId
    );
    if (consentRes.isSuccess && consentRes.body != null) {
      List<Object> results = (List<Object>) consentRes.body.get('results');
      Map<String, Object> consent = pickApplicableConsent(results);
      if (consent != null) {
        conn.AXF_CON_TXT_ConsentId__c = str(consent.get('id'));
        // Consent.itemId may be the origin item, distinct from the operation item (D-85).
        conn.AXF_CON_TXT_ConsentObservedItemId__c = str(consent.get('itemId'));
        conn.AXF_CON_TAL_ConsentScope__c = describeScope(consent);
        conn.AXF_CON_DT_ConsentGivenAt__c = parseDt(consent.get('createdAt'));
        conn.AXF_CON_DT_ConsentExpiresAt__c = parseDt(consent.get('expiresAt')); // null stays null
        Datetime revokedAt = parseDt(consent.get('revokedAt'));

        if (revokedAt != null) {
          newState = 'REVOKED';
          message =
            'Consentimento revogado na origem em ' +
            revokedAt.format() +
            '.';
        } else if (
          conn.AXF_CON_DT_ConsentExpiresAt__c != null &&
          conn.AXF_CON_DT_ConsentExpiresAt__c < Datetime.now()
        ) {
          newState = 'STALE';
          message = 'Consentimento expirado. Reautorize para retomar a coleta.';
        } else if (newState != 'REVOKED' && newState != 'STALE') {
          newState = 'ACTIVE';
        }
      }
    }

    conn.AXF_CON_PKL_ConsentState__c = newState;
    conn.AXF_CON_DT_ConsentCheckedAt__c = Datetime.now();

    ConsentSnapshot out = new ConsentSnapshot();
    out.connectionId = conn.Id;
    out.consentState = newState;
    out.institution = conn.AXF_CON_TXT_InstitutionName__c;
    out.scope = conn.AXF_CON_TAL_ConsentScope__c;
    out.givenAt = conn.AXF_CON_DT_ConsentGivenAt__c;
    out.expiresAt = conn.AXF_CON_DT_ConsentExpiresAt__c;
    out.collectionAllowed =
      (newState == 'ACTIVE') &&
      conn.AXF_CON_PKL_CollectionState__c == 'ACTIVE' &&
      !AXF_CLS_PluggySettings.collectionGloballyPaused();
    out.message = message;
    return out;
  }

  private static Map<String, Object> pickApplicableConsent(
    List<Object> results
  ) {
    if (results == null || results.isEmpty()) {
      return null;
    }
    // Prefer a non-revoked consent; never just take the first one blindly.
    Map<String, Object> fallback;
    for (Object o : results) {
      Map<String, Object> c = (Map<String, Object>) o;
      if (fallback == null) {
        fallback = c;
      }
      if (c.get('revokedAt') == null) {
        return c;
      }
    }
    return fallback;
  }

  private static String describeScope(Map<String, Object> consent) {
    List<String> parts = new List<String>();
    Object products = consent.get('products');
    if (products instanceof List<Object>) {
      List<String> items = new List<String>();
      for (Object p : (List<Object>) products) {
        items.add(String.valueOf(p));
      }
      if (!items.isEmpty()) {
        parts.add('products: ' + String.join(items, ', '));
      }
    }
    Object ofp = consent.get('openFinancePermissionsGranted');
    if (ofp instanceof List<Object>) {
      List<String> items = new List<String>();
      for (Object p : (List<Object>) ofp) {
        items.add(String.valueOf(p));
      }
      if (!items.isEmpty()) {
        parts.add('openFinance: ' + String.join(items, ', '));
      }
    }
    return parts.isEmpty() ? null : String.join(parts, '\n');
  }

  private static Boolean isLoginOrConsentError(String status) {
    if (String.isBlank(status)) {
      return false;
    }
    String s = status.toUpperCase();
    return s == 'LOGIN_ERROR' ||
      s.contains('CONSENT') ||
      s == 'INVALID_CREDENTIALS';
  }

  private static Boolean isOutdated(String status) {
    if (String.isBlank(status)) {
      return false;
    }
    String s = status.toUpperCase();
    return s == 'OUTDATED' || s == 'WAITING_USER_ACTION' || s == 'ERROR';
  }

  private static String str(Object o) {
    return o == null ? null : String.valueOf(o);
  }

  private static Datetime parseDt(Object o) {
    if (o == null) {
      return null;
    }
    try {
      return (Datetime) JSON.deserialize(
        '"' + String.valueOf(o) + '"',
        Datetime.class
      );
    } catch (Exception e) {
      return null;
    }
  }
}
