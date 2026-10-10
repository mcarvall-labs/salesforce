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

  // filter: null = every entry of the month, OVERDUE or DUE_SOON (clicking the indicators).
  @AuraEnabled
  public static ALT_CLS_Dashboard.EntryList getEntries(
    Id holderId,
    Date month,
    String filter
  ) {
    try {
      return new ALT_CLS_Dashboard().entries(holderId, month, filter);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // A conciliar preview: count and the 3 most recent open transactions of the month.
  @AuraEnabled
  public static ALT_CLS_DashboardPreview.Pending getPending(
    Id holderId,
    Date month
  ) {
    try {
      return new ALT_CLS_DashboardPreview().pending(holderId, month);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // Contas e cartões preview: balance of the accounts and available limit of the cards.
  @AuraEnabled
  public static ALT_CLS_DashboardPreview.Sources getSources(Id holderId) {
    try {
      return new ALT_CLS_DashboardPreview().sources(holderId);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // Expenses of the month by category against the goals (E7-5); same filters as getSummary.
  @AuraEnabled
  public static ALT_CLS_DashboardBudget.View getBudget(
    Id holderId,
    Date month
  ) {
    try {
      return new ALT_CLS_DashboardBudget().build(holderId, month);
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
