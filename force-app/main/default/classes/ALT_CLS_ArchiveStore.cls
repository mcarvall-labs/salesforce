/**
 * @description AXF-95 — the only gateway to AXF_OBJ_TransactionArchive__b. Big Object DML is
 * immediate (never rolled back) and rows are addressed by the immutable index
 * (AccountKey, BookingDate DESC, ArchiveKey), so writes are idempotent upserts and reads are
 * always bounded by the index plus a LIMIT. Ordinary sharing does not exist for big objects:
 * callers (ALT_CLS_ArchiveRunService / ALT_CLS_ArchiveReadService) revalidate the holder before
 * and after every call. Tests replace the store through `storeOverride` (DML would persist).
 */
public without sharing class ALT_CLS_ArchiveStore {
  public static final Integer MAX_PAGE = 200;

  public interface Store {
    void write(List<AXF_OBJ_TransactionArchive__b> rows);
    List<AXF_OBJ_TransactionArchive__b> sameDay(
      String accountKey,
      Datetime bookingDate,
      String afterKey,
      Integer max
    );
    List<AXF_OBJ_TransactionArchive__b> before(
      String accountKey,
      Datetime beforeDate,
      Datetime fromDate,
      Integer max
    );
    List<AXF_OBJ_TransactionArchive__b> range(
      String accountKey,
      Datetime fromDate,
      Datetime toDate,
      Integer max
    );
  }

  @TestVisible
  private static Store storeOverride;

  public static Store instance() {
    return storeOverride == null ? new Live() : storeOverride;
  }

  /** Accounting day as the archive stores it: midnight UTC, no timezone shift. */
  public static Datetime bookingKey(Date day) {
    return Datetime.newInstanceGmt(day.year(), day.month(), day.day(), 0, 0, 0);
  }

  public static Date bookingDay(Datetime stored) {
    return stored == null ? null : stored.dateGmt();
  }

  public static String sha256(String value) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value))
    );
  }

  private class Live implements Store {
    public void write(List<AXF_OBJ_TransactionArchive__b> rows) {
      if (rows.isEmpty()) {
        return;
      }
      Database.insertImmediate(rows);
    }

    public List<AXF_OBJ_TransactionArchive__b> sameDay(
      String accountKey,
      Datetime bookingDate,
      String afterKey,
      Integer max
    ) {
      Integer top = bound(max);
      return [
        SELECT
          AXF_ARC_TXT_AccountKey__c,
          AXF_ARC_DT_BookingDate__c,
          AXF_ARC_TXT_ArchiveKey__c,
          AXF_ARC_TXT_SourceFamily__c,
          AXF_ARC_TXT_SourceKey__c,
          AXF_ARC_TXT_SourceRecordId__c,
          AXF_ARC_TXT_SourceId__c,
          AXF_ARC_NUM_Magnitude__c,
          AXF_ARC_TXT_Direction__c,
          AXF_ARC_TXT_CurrencyIsoCode__c,
          AXF_ARC_TXT_Status__c,
          AXF_ARC_TXT_Description__c,
          AXF_ARC_TXT_InstitutionKey__c,
          AXF_ARC_TXT_InstitutionLabel__c,
          AXF_ARC_TXT_PolicyVersion__c,
          AXF_ARC_TXT_RunKey__c,
          AXF_ARC_TXT_ContentHash__c,
          AXF_ARC_DT_ArchivedAt__c
        FROM AXF_OBJ_TransactionArchive__b
        WHERE
          AXF_ARC_TXT_AccountKey__c = :accountKey
          AND AXF_ARC_DT_BookingDate__c = :bookingDate
          AND AXF_ARC_TXT_ArchiveKey__c > :afterKey
        LIMIT :top
      ];
    }

    public List<AXF_OBJ_TransactionArchive__b> before(
      String accountKey,
      Datetime beforeDate,
      Datetime fromDate,
      Integer max
    ) {
      Integer top = bound(max);
      return [
        SELECT
          AXF_ARC_TXT_AccountKey__c,
          AXF_ARC_DT_BookingDate__c,
          AXF_ARC_TXT_ArchiveKey__c,
          AXF_ARC_TXT_SourceFamily__c,
          AXF_ARC_TXT_SourceKey__c,
          AXF_ARC_TXT_SourceRecordId__c,
          AXF_ARC_TXT_SourceId__c,
          AXF_ARC_NUM_Magnitude__c,
          AXF_ARC_TXT_Direction__c,
          AXF_ARC_TXT_CurrencyIsoCode__c,
          AXF_ARC_TXT_Status__c,
          AXF_ARC_TXT_Description__c,
          AXF_ARC_TXT_InstitutionKey__c,
          AXF_ARC_TXT_InstitutionLabel__c,
          AXF_ARC_TXT_PolicyVersion__c,
          AXF_ARC_TXT_RunKey__c,
          AXF_ARC_TXT_ContentHash__c,
          AXF_ARC_DT_ArchivedAt__c
        FROM AXF_OBJ_TransactionArchive__b
        WHERE
          AXF_ARC_TXT_AccountKey__c = :accountKey
          AND AXF_ARC_DT_BookingDate__c < :beforeDate
          AND AXF_ARC_DT_BookingDate__c >= :fromDate
        LIMIT :top
      ];
    }

    public List<AXF_OBJ_TransactionArchive__b> range(
      String accountKey,
      Datetime fromDate,
      Datetime toDate,
      Integer max
    ) {
      Integer top = bound(max);
      return [
        SELECT
          AXF_ARC_TXT_AccountKey__c,
          AXF_ARC_DT_BookingDate__c,
          AXF_ARC_TXT_ArchiveKey__c,
          AXF_ARC_TXT_SourceFamily__c,
          AXF_ARC_TXT_SourceKey__c,
          AXF_ARC_TXT_SourceRecordId__c,
          AXF_ARC_TXT_SourceId__c,
          AXF_ARC_NUM_Magnitude__c,
          AXF_ARC_TXT_Direction__c,
          AXF_ARC_TXT_CurrencyIsoCode__c,
          AXF_ARC_TXT_Status__c,
          AXF_ARC_TXT_Description__c,
          AXF_ARC_TXT_InstitutionKey__c,
          AXF_ARC_TXT_InstitutionLabel__c,
          AXF_ARC_TXT_PolicyVersion__c,
          AXF_ARC_TXT_RunKey__c,
          AXF_ARC_TXT_ContentHash__c,
          AXF_ARC_DT_ArchivedAt__c
        FROM AXF_OBJ_TransactionArchive__b
        WHERE
          AXF_ARC_TXT_AccountKey__c = :accountKey
          AND AXF_ARC_DT_BookingDate__c <= :toDate
          AND AXF_ARC_DT_BookingDate__c >= :fromDate
        LIMIT :top
      ];
    }

    private Integer bound(Integer max) {
      return max == null || max < 1 || max > MAX_PAGE ? MAX_PAGE : max;
    }
  }
}
