/**
 * @description Typed access to the org-default AXF_PluggyIntegrationConfig__c hierarchy
 * custom setting, with code defaults so the capability behaves deterministically before an
 * admin ever opens the config screen. Holds NO secrets. AXF-11.
 *
 * A single working row is cached per transaction so repeated read/mutate/save cycles in one
 * request never try to insert a second org-default row.
 */
public with sharing class AXF_CLS_PluggySettings {
  @TestVisible
  static final String SLOT_PRIMARY = 'PRIMARY';
  @TestVisible
  static final String SLOT_CANDIDATE = 'CANDIDATE';

  public static final String NC_PRIMARY = 'AXF_NC_Pluggy_API';
  public static final String NC_CANDIDATE = 'AXF_NC_Pluggy_API_Candidate';

  static final Integer DEFAULT_CACHE_TTL_SECONDS = 5400;

  @TestVisible
  private static AXF_PluggyIntegrationConfig__c overrideForTests;

  private static AXF_PluggyIntegrationConfig__c working;
  private static Boolean persisted = false;

  private AXF_CLS_PluggySettings() {
  }

  private static AXF_PluggyIntegrationConfig__c record() {
    if (overrideForTests != null) {
      return overrideForTests;
    }
    if (working == null) {
      List<AXF_PluggyIntegrationConfig__c> rows = [
        SELECT
          Id,
          AXF_PIC_TXT_ActiveSlot__c,
          AXF_PIC_NUM_ApiKeyCacheTtlSeconds__c,
          AXF_PIC_BOL_CollectionGloballyPaused__c,
          AXF_PIC_DT_GlobalPauseAt__c,
          AXF_PIC_BOL_WebhookEnabled__c,
          AXF_PIC_TXT_RotationState__c,
          AXF_PIC_DT_RotationStartedAt__c,
          AXF_PIC_TXT_PrimarySlotTestResult__c,
          AXF_PIC_DT_PrimarySlotTestedAt__c,
          AXF_PIC_TXT_CandidateSlotTestResult__c,
          AXF_PIC_DT_CandidateSlotTestedAt__c
        FROM AXF_PluggyIntegrationConfig__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        working = new AXF_PluggyIntegrationConfig__c(
          SetupOwnerId = UserInfo.getOrganizationId()
        );
        persisted = false;
      } else {
        working = rows[0];
        persisted = true;
      }
    }
    return working;
  }

  /**
   * @description Named Credential the auth service must use right now, resolved from the
   * active slot pointer. Never returns a raw secret.
   */
  public static String activeNamedCredential() {
    return SLOT_CANDIDATE.equalsIgnoreCase(record().AXF_PIC_TXT_ActiveSlot__c)
      ? NC_CANDIDATE
      : NC_PRIMARY;
  }

  public static String activeSlot() {
    String s = record().AXF_PIC_TXT_ActiveSlot__c;
    return SLOT_CANDIDATE.equalsIgnoreCase(s) ? SLOT_CANDIDATE : SLOT_PRIMARY;
  }

  public static Integer apiKeyCacheTtlSeconds() {
    Decimal ttl = record().AXF_PIC_NUM_ApiKeyCacheTtlSeconds__c;
    if (ttl == null || ttl <= 0) {
      return DEFAULT_CACHE_TTL_SECONDS;
    }
    return (Integer) ttl;
  }

  public static Boolean collectionGloballyPaused() {
    return record().AXF_PIC_BOL_CollectionGloballyPaused__c == true;
  }

  public static Boolean webhookEnabled() {
    // Absent setting => enabled (safe default: still validates signature before acting).
    AXF_PluggyIntegrationConfig__c r = record();
    if (r.Id == null && !persisted && overrideForTests == null) {
      return true;
    }
    return r.AXF_PIC_BOL_WebhookEnabled__c == true;
  }

  public static String rotationState() {
    String s = record().AXF_PIC_TXT_RotationState__c;
    return String.isBlank(s) ? 'NONE' : s;
  }

  /**
   * @description The transaction's working row, ready to mutate and pass back to save().
   */
  public static AXF_PluggyIntegrationConfig__c currentOrgDefaultForUpdate() {
    return record();
  }

  /**
   * @description Persists the working row. Caller is responsible for the authority check.
   */
  public static void save(AXF_PluggyIntegrationConfig__c mutated) {
    upsert mutated;
    working = mutated;
    persisted = true;
    overrideForTests = null;
  }
}
