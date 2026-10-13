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

  // "+ Nova categoria": creates an expense category (top level or under parentId).
  @AuraEnabled
  public static ALT_CLS_ExpenseWizard.Option createCategory(
    String name,
    Id parentId
  ) {
    try {
      return new ALT_CLS_ExpenseWizard().createCategory(name, parentId);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // One transaction: creates the standalone expense entry and returns its id. The request is a
  // JSON string because Aura does not fill the fields of an Apex object parameter reliably.
  @AuraEnabled
  public static Id createStandalone(String requestJson) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .createStandalone(
          (ALT_CLS_ExpenseWizard.Request) JSON.deserialize(
            requestJson,
            ALT_CLS_ExpenseWizard.Request.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // One transaction: creates the recurring Contract and its Pending entries.
  @AuraEnabled
  public static Id createRecurring(String requestJson) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .createRecurring(
          (ALT_CLS_ExpenseWizard.RecurringRequest) JSON.deserialize(
            requestJson,
            ALT_CLS_ExpenseWizard.RecurringRequest.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // The entries the Contract would generate, for the review step.
  @AuraEnabled
  public static List<ALT_CLS_ExpenseWizard.PreviewItem> previewRecurring(
    String requestJson
  ) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .previewRecurring(
          (ALT_CLS_ExpenseWizard.RecurringRequest) JSON.deserialize(
            requestJson,
            ALT_CLS_ExpenseWizard.RecurringRequest.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // One transaction: creates the installment Contract and its Pending entries.
  @AuraEnabled
  public static Id createInstallment(String requestJson) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .createInstallment(
          (ALT_CLS_ExpenseWizard.InstallmentRequest) JSON.deserialize(
            requestJson,
            ALT_CLS_ExpenseWizard.InstallmentRequest.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // The installments the Contract would generate, for the review step.
  @AuraEnabled
  public static List<ALT_CLS_ExpenseWizard.PreviewItem> previewInstallment(
    String requestJson
  ) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .previewInstallment(
          (ALT_CLS_ExpenseWizard.InstallmentRequest) JSON.deserialize(
            requestJson,
            ALT_CLS_ExpenseWizard.InstallmentRequest.class
          )
        );
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
