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

  // One transaction: creates the recurring Contract and its Pending entries.
  @AuraEnabled
  public static Id createRecurring(
    ALT_CLS_ExpenseWizard.RecurringRequest request
  ) {
    try {
      return new ALT_CLS_ExpenseWizard().createRecurring(request);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // The entries the Contract would generate, for the review step.
  @AuraEnabled
  public static List<ALT_CLS_ExpenseWizard.PreviewItem> previewRecurring(
    ALT_CLS_ExpenseWizard.RecurringRequest request
  ) {
    try {
      return new ALT_CLS_ExpenseWizard().previewRecurring(request);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // One transaction: creates the installment Contract and its Pending entries.
  @AuraEnabled
  public static Id createInstallment(
    ALT_CLS_ExpenseWizard.InstallmentRequest request
  ) {
    try {
      return new ALT_CLS_ExpenseWizard().createInstallment(request);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // The installments the Contract would generate, for the review step.
  @AuraEnabled
  public static List<ALT_CLS_ExpenseWizard.PreviewItem> previewInstallment(
    ALT_CLS_ExpenseWizard.InstallmentRequest request
  ) {
    try {
      return new ALT_CLS_ExpenseWizard().previewInstallment(request);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  private static AuraHandledException aura(Exception e) {
    String message = e.getMessage();
    if (e instanceof DmlException && ((DmlException) e).getNumDml() > 0) {
      message = ((DmlException) e).getDmlMessage(0);
    }
    AuraHandledException result = new AuraHandledException(message);
    result.setMessage(message);
    return result;
  }
}
