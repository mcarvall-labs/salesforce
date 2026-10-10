public with sharing class AXF_CLS_CTRL_Dashboard {
  @AuraEnabled
  public static List<ALT_CLS_Dashboard.Holder> getHolders() {
    try {
      return new ALT_CLS_Dashboard().holders();
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // holderId null = all holders the user can see; month is any date inside the month.
  @AuraEnabled
  public static ALT_CLS_Dashboard.Summary getSummary(Id holderId, Date month) {
    try {
      return new ALT_CLS_Dashboard().summarize(holderId, month);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // setMessage is what the LWC reads; the constructor message alone arrives as a generic error.
  private static AuraHandledException aura(Exception e) {
    AuraHandledException result = new AuraHandledException(e.getMessage());
    result.setMessage(e.getMessage());
    return result;
  }
}
