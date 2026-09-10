/** @description Dedicated manual-review UI boundary; common DTOs are serialized explicitly. */
public with sharing class AXF_CLS_CTRL_ManualReview {
  @AuraEnabled
  public static String listPending() {
    try {
      return JSON.serialize(new ALT_CLS_ManualReviewService().listPending());
    } catch (Exception failure) {
      throw new AuraHandledException('MANUAL_REVIEW_UNAVAILABLE');
    }
  }
  @AuraEnabled
  public static String confirm(Id itemId, Decimal version, String note) {
    try {
      return JSON.serialize(
        new ALT_CLS_ManualReviewService().confirm(itemId, version, note)
      );
    } catch (Exception failure) {
      throw new AuraHandledException('MANUAL_REVIEW_UNAVAILABLE');
    }
  }
}
