/**
 * @description Computes the external identity of an ingested Pluggy fact (AXF-13,
 * Fechamento G6-1). A fact is identified by EXACTLY ONE of:
 *  - the Pluggy transaction/record UUID  → used verbatim as the idempotent upsert key;
 *  - a fallback key (no provider id — manual/CSV, connector without id)
 *      = sha256Hex(frame('fbk-v1', parentExternalId, bookingDate, signedAmount,
 *                         normalizedDescription))
 *    the PARENT external id is inside the hash, so an id that is only unique within a
 *    parent never collides across parents (D-61), and it is never stored in the field that
 *    holds the Pluggy id.
 *
 * Pure/deterministic: the same fact always yields the same key (replay-safe). No SOQL/DML.
 */
public inherited sharing class AXF_CLS_PluggyFactIdentity {
  @TestVisible
  private static final String FALLBACK_TAG = 'fbk-v1';

  public enum KeyKind {
    PLUGGY_ID,
    FALLBACK
  }

  public class Result {
    public KeyKind kind;
    /** @description Value for AXF_<ACR>_EXI_PluggyTransactionId__c (null for FALLBACK). */
    public String pluggyId;
    /** @description Value for AXF_<ACR>_EXI_FallbackKey__c (null for PLUGGY_ID). */
    public String fallbackKey;
  }

  private AXF_CLS_PluggyFactIdentity() {
  }

  /**
   * @description Identity when the provider supplied a stable id.
   */
  public static Result fromProviderId(String pluggyTransactionId) {
    if (String.isBlank(pluggyTransactionId)) {
      throw new AXF_CLS_IdentityException(
        'A Pluggy transaction id is required.'
      );
    }
    Result r = new Result();
    r.kind = KeyKind.PLUGGY_ID;
    r.pluggyId = pluggyTransactionId.trim();
    return r;
  }

  /**
   * @description Identity when there is no provider id. All four inputs are required —
   * an absent input would let unrelated facts collide.
   */
  public static Result fallback(
    String parentExternalId,
    Date bookingDate,
    Decimal signedAmount,
    String description
  ) {
    if (
      String.isBlank(parentExternalId) ||
      bookingDate == null ||
      signedAmount == null
    ) {
      throw new AXF_CLS_IdentityException(
        'Fallback identity needs parentExternalId, bookingDate and signedAmount.'
      );
    }
    Result r = new Result();
    r.kind = KeyKind.FALLBACK;
    r.fallbackKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        FALLBACK_TAG,
        parentExternalId.trim(),
        isoDate(bookingDate),
        signedAmount.setScale(2, System.RoundingMode.HALF_UP).toPlainString(),
        AXF_CLS_TextNormalization.POLICY_VERSION,
        AXF_CLS_TextNormalization.normalize(description)
      }
    );
    return r;
  }

  @TestVisible
  private static String isoDate(Date d) {
    String mm = String.valueOf(d.month()).leftPad(2, '0');
    String dd = String.valueOf(d.day()).leftPad(2, '0');
    return d.year() + '-' + mm + '-' + dd;
  }
}
