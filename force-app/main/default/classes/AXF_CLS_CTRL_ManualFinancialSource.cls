/** Thin LWC boundary for AXF-86. */
public with sharing class AXF_CLS_CTRL_ManualFinancialSource {
  @AuraEnabled
  public static ALT_CLS_ManualFinancialSource.SaveResult save(
    ALT_CLS_ManualFinancialSource.SaveInput input
  ) {
    return new ALT_CLS_ManualFinancialSource().save(input);
  }
}
