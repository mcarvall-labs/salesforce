/**
 * @description AXF-95 test double for ALT_CLS_ArchiveStore: Big Object DML is immediate and
 * never rolled back in tests, so the services are exercised against an in-memory map keyed by
 * the immutable index (AccountKey, BookingDate, ArchiveKey) with the same upsert and
 * index-order semantics (date DESC, key ASC).
 */
@IsTest
public class ALT_CLS_ArchiveTestStore implements ALT_CLS_ArchiveStore.Store {
  public Map<String, AXF_OBJ_TransactionArchive__b> rows = new Map<String, AXF_OBJ_TransactionArchive__b>();
  public Integer writes = 0;
  public Integer written = 0;
  /** Fails the n-th write (1-based) once, to exercise checkpoint/resume. */
  public Integer failAtWrite;

  public void write(List<AXF_OBJ_TransactionArchive__b> incoming) {
    writes++;
    if (failAtWrite != null && writes == failAtWrite) {
      failAtWrite = null;
      throw new ALT_CLS_ArchiveRunService.ArchiveRunException(
        'SIMULATED_WRITE_FAILURE'
      );
    }
    for (AXF_OBJ_TransactionArchive__b row : incoming) {
      rows.put(keyOf(row), row.clone(false, true, false, false));
      written++;
    }
  }

  public List<AXF_OBJ_TransactionArchive__b> sameDay(
    String accountKey,
    Datetime bookingDate,
    String afterKey,
    Integer max
  ) {
    List<AXF_OBJ_TransactionArchive__b> result = new List<AXF_OBJ_TransactionArchive__b>();
    max = cap(max);
    for (AXF_OBJ_TransactionArchive__b row : ordered(accountKey)) {
      if (
        row.AXF_ARC_DT_BookingDate__c == bookingDate &&
        row.AXF_ARC_TXT_ArchiveKey__c > afterKey
      ) {
        result.add(row);
        if (result.size() == max) {
          break;
        }
      }
    }
    return result;
  }

  public List<AXF_OBJ_TransactionArchive__b> before(
    String accountKey,
    Datetime beforeDate,
    Datetime fromDate,
    Integer max
  ) {
    List<AXF_OBJ_TransactionArchive__b> result = new List<AXF_OBJ_TransactionArchive__b>();
    max = cap(max);
    for (AXF_OBJ_TransactionArchive__b row : ordered(accountKey)) {
      if (
        row.AXF_ARC_DT_BookingDate__c < beforeDate &&
        row.AXF_ARC_DT_BookingDate__c >= fromDate
      ) {
        result.add(row);
        if (result.size() == max) {
          break;
        }
      }
    }
    return result;
  }

  public List<AXF_OBJ_TransactionArchive__b> range(
    String accountKey,
    Datetime fromDate,
    Datetime toDate,
    Integer max
  ) {
    List<AXF_OBJ_TransactionArchive__b> result = new List<AXF_OBJ_TransactionArchive__b>();
    max = cap(max);
    for (AXF_OBJ_TransactionArchive__b row : ordered(accountKey)) {
      if (
        row.AXF_ARC_DT_BookingDate__c <= toDate &&
        row.AXF_ARC_DT_BookingDate__c >= fromDate
      ) {
        result.add(row);
        if (result.size() == max) {
          break;
        }
      }
    }
    return result;
  }

  /** Same page ceiling as the live store. */
  private static Integer cap(Integer max) {
    return max == null ||
      max < 1 ||
      max > ALT_CLS_ArchiveStore.MAX_PAGE
      ? ALT_CLS_ArchiveStore.MAX_PAGE
      : max;
  }

  /** Index order: BookingDate DESC, ArchiveKey ASC. */
  private List<AXF_OBJ_TransactionArchive__b> ordered(String accountKey) {
    List<String> keys = new List<String>();
    for (AXF_OBJ_TransactionArchive__b row : rows.values()) {
      if (row.AXF_ARC_TXT_AccountKey__c == accountKey) {
        keys.add(sortKey(row));
      }
    }
    keys.sort();
    List<AXF_OBJ_TransactionArchive__b> result = new List<AXF_OBJ_TransactionArchive__b>();
    for (String key : keys) {
      result.add(rows.get(key.substringAfter('#')));
    }
    return result;
  }

  private static String sortKey(AXF_OBJ_TransactionArchive__b row) {
    // Descending date: subtract from a far-future epoch so ascending sort yields newest first.
    Long inverted = 9999999999999L - row.AXF_ARC_DT_BookingDate__c.getTime();
    return String.valueOf(inverted).leftPad(13, '0') +
      '|' +
      row.AXF_ARC_TXT_ArchiveKey__c +
      '#' +
      keyOf(row);
  }

  public static String keyOf(AXF_OBJ_TransactionArchive__b row) {
    return row.AXF_ARC_TXT_AccountKey__c +
      '|' +
      row.AXF_ARC_DT_BookingDate__c.getTime() +
      '|' +
      row.AXF_ARC_TXT_ArchiveKey__c;
  }
}
