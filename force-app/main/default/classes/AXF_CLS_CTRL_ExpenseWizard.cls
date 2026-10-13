public with sharing class AXF_CLS_CTRL_ExpenseWizard {
  // Expense categories and the accounts and cards of the holder.
  @AuraEnabled
  public static ALT_CLS_ExpenseWizard.Options getOptions(Id holderId) {
    try {
      return new ALT_CLS_ExpenseWizard().options(holderId);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // One transaction: creates the standalone expense entry and returns its id.
  @AuraEnabled
  public static Id createStandalone(ALT_CLS_ExpenseWizard.Request request) {
    try {
      return new ALT_CLS_ExpenseWizard().createStandalone(request);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  private static AuraHandledException aura(Exception e) {
    String message = e.getMessage();
    if (e instanceof DmlException) {
      message = ((DmlException) e).getDmlMessage(0);
    }
    AuraHandledException result = new AuraHandledException(message);
    result.setMessage(message);
    return result;
  }
}
