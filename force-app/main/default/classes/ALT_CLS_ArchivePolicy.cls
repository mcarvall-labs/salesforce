/**
 * @description AXF-95 — resolves AXF_CMT_ArchivePolicy__mdt.Default. The hot window is
 * configuration, not code: changing the months moves the window on the next run. A missing,
 * disabled or invalid record blocks archiving instead of assuming a default.
 */
public with sharing class ALT_CLS_ArchivePolicy {
  public class PolicyException extends Exception {
    public String code;
  }

  public class Resolved {
    public String version;
    public Integer hotWindowMonths;
    public Integer batchSize;
    public Boolean allowHotRemoval;
    /** First day kept hot; everything before it is archivable. */
    public Date hotWindowStart;
  }

  /** Test seam: the CMT instance cannot be mocked. */
  @TestVisible
  private static AXF_CMT_ArchivePolicy__mdt policyOverride;
  @TestVisible
  private static Date todayOverride;
  @TestVisible
  private static Boolean simulateMissing = false;

  public static Resolved resolve() {
    AXF_CMT_ArchivePolicy__mdt row = simulateMissing
      ? null
      : (policyOverride != null
          ? policyOverride
          : AXF_CMT_ArchivePolicy__mdt.getInstance('Default'));
    if (row == null) {
      throw failure('POLICY_MISSING');
    }
    if (row.AXF_APL_BOL_Enabled__c != true) {
      throw failure('POLICY_DISABLED');
    }
    Resolved result = new Resolved();
    result.version = row.AXF_APL_TXT_PolicyVersion__c;
    result.hotWindowMonths = row.AXF_APL_NUM_HotWindowMonths__c == null
      ? null
      : row.AXF_APL_NUM_HotWindowMonths__c.intValue();
    result.batchSize = row.AXF_APL_NUM_BatchSize__c == null
      ? null
      : row.AXF_APL_NUM_BatchSize__c.intValue();
    result.allowHotRemoval = row.AXF_APL_BOL_AllowHotRemoval__c == true;
    if (
      String.isBlank(result.version) ||
      result.hotWindowMonths == null ||
      result.hotWindowMonths < 1 ||
      result.hotWindowMonths > 1200 ||
      result.batchSize == null ||
      result.batchSize < 1 ||
      result.batchSize > 200
    ) {
      throw failure('POLICY_INVALID');
    }
    Date today = todayOverride == null ? Date.today() : todayOverride;
    result.hotWindowStart = today.toStartOfMonth()
      .addMonths(-result.hotWindowMonths);
    return result;
  }

  private static PolicyException failure(String code) {
    PolicyException result = new PolicyException(code);
    result.code = code;
    return result;
  }
}
