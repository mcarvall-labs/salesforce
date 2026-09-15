/**
 * @description AXF-95 — read-only, bounded access to the transaction archive. Every request
 * names one holder; authorization is checked when the request arrives (holder visible with the
 * caller's effective access and an Axon record type) and again before rows are returned (holder
 * still visible, every row keyed to that holder). Rows are never rehydrated into hot objects.
 *
 * Pagination follows the immutable index (AccountKey, BookingDate DESC, ArchiveKey): a page ends
 * at (date, key); the next page reads the rest of that same day (`ArchiveKey > key`) and then
 * older days, so many rows on one date are neither skipped nor repeated.
 */
public with sharing class ALT_CLS_ArchiveReadService {
  public static final String CP_READ = 'AXF_CanReadArchive';
  public static final Integer DEFAULT_PAGE = 50;

  public class ArchiveReadException extends Exception {
    public String code;
  }

  public class ReadInput {
    public Id accountId;
    public Date fromDate;
    public Date toDate;
    public Date cursorDate;
    public String cursorKey;
    public Integer pageSize;
  }

  public class ArchivedRow {
    @AuraEnabled
    public String archiveKey;
    @AuraEnabled
    public String family;
    @AuraEnabled
    public Date bookingDate;
    @AuraEnabled
    public Decimal magnitude;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String institutionLabel;
    @AuraEnabled
    public String sourceId;
    @AuraEnabled
    public Datetime archivedAt;
    @AuraEnabled
    public Boolean archived = true;
  }

  public class ReadResult {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public Date fromDate;
    @AuraEnabled
    public Date toDate;
    @AuraEnabled
    public Date hotWindowStart;
    @AuraEnabled
    public List<ArchivedRow> rows = new List<ArchivedRow>();
    @AuraEnabled
    public Boolean hasMore = false;
    @AuraEnabled
    public Date nextCursorDate;
    @AuraEnabled
    public String nextCursorKey;
  }

  public ReadResult read(ReadInput input) {
    if (!FeatureManagement.checkPermission(CP_READ)) {
      throw failure('FORBIDDEN');
    }
    if (input == null || input.accountId == null) {
      throw failure('INVALID_INPUT');
    }
    if (
      input.fromDate != null &&
      input.toDate != null &&
      input.fromDate > input.toDate
    ) {
      throw failure('INVALID_INPUT');
    }
    if ((input.cursorDate == null) != (String.isBlank(input.cursorKey))) {
      throw failure('INVALID_INPUT');
    }
    requireHolder(input.accountId);
    ALT_CLS_ArchivePolicy.Resolved policy = ALT_CLS_ArchivePolicy.resolve();

    ReadResult result = new ReadResult();
    result.accountId = input.accountId;
    result.hotWindowStart = policy.hotWindowStart;
    result.toDate = input.toDate == null ||
      input.toDate >= policy.hotWindowStart
      ? policy.hotWindowStart.addDays(-1)
      : input.toDate;
    result.fromDate = input.fromDate == null
      ? Date.newInstance(1700, 1, 1)
      : input.fromDate;
    if (result.fromDate > result.toDate) {
      return result; // the requested period lies inside the hot window: nothing archived
    }
    Integer size = input.pageSize == null ||
      input.pageSize < 1 ||
      input.pageSize > ALT_CLS_ArchiveStore.MAX_PAGE
      ? DEFAULT_PAGE
      : input.pageSize;
    List<AXF_OBJ_TransactionArchive__b> page = page(
      String.valueOf(input.accountId),
      result.fromDate,
      result.toDate,
      input.cursorDate,
      input.cursorKey,
      size
    );
    // Authorization is re-checked before anything leaves the service.
    requireHolder(input.accountId);
    String expectedKey = String.valueOf(input.accountId);
    for (AXF_OBJ_TransactionArchive__b row : page) {
      if (row.AXF_ARC_TXT_AccountKey__c != expectedKey) {
        continue;
      }
      result.rows.add(toView(row));
    }
    if (page.size() == size) {
      AXF_OBJ_TransactionArchive__b last = page[page.size() - 1];
      result.hasMore = true;
      result.nextCursorDate = ALT_CLS_ArchiveStore.bookingDay(
        last.AXF_ARC_DT_BookingDate__c
      );
      result.nextCursorKey = last.AXF_ARC_TXT_ArchiveKey__c;
    }
    return result;
  }

  /** One page in index order; shared with the run verifier. */
  public static List<AXF_OBJ_TransactionArchive__b> page(
    String accountKey,
    Date fromDate,
    Date toDate,
    Date cursorDate,
    String cursorKey,
    Integer size
  ) {
    ALT_CLS_ArchiveStore.Store store = ALT_CLS_ArchiveStore.instance();
    Datetime lower = ALT_CLS_ArchiveStore.bookingKey(fromDate);
    List<AXF_OBJ_TransactionArchive__b> rows = new List<AXF_OBJ_TransactionArchive__b>();
    if (cursorDate == null) {
      rows.addAll(
        store.range(
          accountKey,
          lower,
          ALT_CLS_ArchiveStore.bookingKey(toDate),
          size
        )
      );
      return rows;
    }
    Datetime day = ALT_CLS_ArchiveStore.bookingKey(cursorDate);
    rows.addAll(store.sameDay(accountKey, day, cursorKey, size));
    if (rows.size() < size && cursorDate > fromDate) {
      rows.addAll(store.before(accountKey, day, lower, size - rows.size()));
    }
    return rows;
  }

  private static void requireHolder(Id accountId) {
    List<Account> rows = [
      SELECT Id
      FROM Account
      WHERE
        Id = :accountId
        AND RecordType.DeveloperName IN (
          :ALT_CLS_AxonHolder.RT_PERSON,
          :ALT_CLS_AxonHolder.RT_BUSINESS
        )
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      // Same answer whether the holder does not exist, is private or was revoked meanwhile.
      throw failure('NOT_ACCESSIBLE');
    }
  }

  private static ArchivedRow toView(AXF_OBJ_TransactionArchive__b row) {
    ArchivedRow view = new ArchivedRow();
    view.archiveKey = row.AXF_ARC_TXT_ArchiveKey__c;
    view.family = row.AXF_ARC_TXT_SourceFamily__c;
    view.bookingDate = ALT_CLS_ArchiveStore.bookingDay(
      row.AXF_ARC_DT_BookingDate__c
    );
    view.magnitude = row.AXF_ARC_NUM_Magnitude__c;
    view.direction = row.AXF_ARC_TXT_Direction__c;
    view.currencyIso = row.AXF_ARC_TXT_CurrencyIsoCode__c;
    view.status = row.AXF_ARC_TXT_Status__c;
    view.description = row.AXF_ARC_TXT_Description__c;
    view.institutionLabel = row.AXF_ARC_TXT_InstitutionLabel__c;
    view.sourceId = row.AXF_ARC_TXT_SourceId__c;
    view.archivedAt = row.AXF_ARC_DT_ArchivedAt__c;
    return view;
  }

  private static ArchiveReadException failure(String code) {
    ArchiveReadException result = new ArchiveReadException(code);
    result.code = code;
    return result;
  }
}
