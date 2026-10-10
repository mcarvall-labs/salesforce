public with sharing class AXF_CLS_CTRL_Dashboard {
  @AuraEnabled
  public static List<ALT_CLS_Dashboard.Holder> getHolders() {
    try {
      return new ALT_CLS_Dashboard().holders();
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // holderId null = all holders the user can see; month is any date inside the month.
  @AuraEnabled
  public static ALT_CLS_Dashboard.Summary getSummary(Id holderId, Date month) {
    try {
      return new ALT_CLS_Dashboard().summarize(holderId, month);
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
