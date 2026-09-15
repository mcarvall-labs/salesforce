/**
 * @description AXF-109 — revision integrity for transaction observations. Observations are
 * owned by the holder's owner (OWD Private); an authorized observer who is not that owner must
 * still see the latest revision, or replaying the same fact would collide on the unique
 * observation key. Returns ids, revision numbers and content hashes only — no business content.
 */
public without sharing class ALT_CLS_TransactionObservationIntegrity {
  public class Latest {
    public Id id;
    public Integer revision;
    public String fingerprint;
    public String eligibility;
  }

  /** Latest revision per source identity. */
  public static Map<String, Latest> latest(Set<String> identities) {
    Map<String, Latest> result = new Map<String, Latest>();
    if (identities == null || identities.isEmpty()) {
      return result;
    }
    for (AXF_OBJ_TransactionObservation__c row : [
      SELECT
        Id,
        AXF_TOB_TXT_SourceIdentity__c,
        AXF_TOB_NUM_Revision__c,
        AXF_TOB_TXT_ContentFingerprint__c,
        AXF_TOB_PKL_Eligibility__c
      FROM AXF_OBJ_TransactionObservation__c
      WHERE AXF_TOB_TXT_SourceIdentity__c IN :identities
      WITH SYSTEM_MODE
      ORDER BY AXF_TOB_NUM_Revision__c ASC
    ]) {
      Latest entry = new Latest();
      entry.id = row.Id;
      entry.revision = Integer.valueOf(row.AXF_TOB_NUM_Revision__c);
      entry.fingerprint = row.AXF_TOB_TXT_ContentFingerprint__c;
      entry.eligibility = row.AXF_TOB_PKL_Eligibility__c;
      result.put(row.AXF_TOB_TXT_SourceIdentity__c, entry);
    }
    return result;
  }
}
