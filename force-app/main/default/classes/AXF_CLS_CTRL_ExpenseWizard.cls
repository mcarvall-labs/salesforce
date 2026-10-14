public with sharing class AXF_CLS_CTRL_ExpenseWizard {
  // Categories of the entry type (Expense by default) and the accounts and cards of the holder.
  @AuraEnabled
  public static ALT_CLS_ExpenseWizard.Options getOptions(
    Id holderId,
    String entryType
  ) {
    try {
      return new ALT_CLS_ExpenseWizard().options(holderId, entryType);
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // "+ Nova categoria": creates an expense category (top level or under parentId). The parent
  // is a String because Aura rejects any non-Id value of an Id parameter before this runs;
  // blank means top level.
  @AuraEnabled
  public static ALT_CLS_ExpenseWizard.Option createCategory(
    String name,
    String parentId,
    String entryType
  ) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .createCategory(name, toParentId(parentId), entryType);
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
          (ALT_CLS_ExpenseWizard.Request) parse(
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
          (ALT_CLS_ExpenseWizard.RecurringRequest) parse(
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
          (ALT_CLS_ExpenseWizard.RecurringRequest) parse(
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
          (ALT_CLS_ExpenseWizard.InstallmentRequest) parse(
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
          (ALT_CLS_ExpenseWizard.InstallmentRequest) parse(
            requestJson,
            ALT_CLS_ExpenseWizard.InstallmentRequest.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // One transaction: creates the consortium Contract and its Pending entries.
  @AuraEnabled
  public static Id createConsortium(String requestJson) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .createConsortium(
          (ALT_CLS_ExpenseWizard.ConsortiumRequest) parse(
            requestJson,
            ALT_CLS_ExpenseWizard.ConsortiumRequest.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // The installments the Contract would generate, for the review step.
  @AuraEnabled
  public static List<ALT_CLS_ExpenseWizard.PreviewItem> previewConsortium(
    String requestJson
  ) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .previewConsortium(
          (ALT_CLS_ExpenseWizard.ConsortiumRequest) parse(
            requestJson,
            ALT_CLS_ExpenseWizard.ConsortiumRequest.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // One transaction: creates the financing Contract and its Pending entries.
  @AuraEnabled
  public static Id createFinancing(String requestJson) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .createFinancing(
          (ALT_CLS_ExpenseWizard.FinancingRequest) parse(
            requestJson,
            ALT_CLS_ExpenseWizard.FinancingRequest.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  // The schedule the Contract would generate, with the interest of each installment.
  @AuraEnabled
  public static List<ALT_CLS_ExpenseWizard.PreviewItem> previewFinancing(
    String requestJson
  ) {
    try {
      return new ALT_CLS_ExpenseWizard()
        .previewFinancing(
          (ALT_CLS_ExpenseWizard.FinancingRequest) parse(
            requestJson,
            ALT_CLS_ExpenseWizard.FinancingRequest.class
          )
        );
    } catch (Exception e) {
      throw aura(e);
    }
  }

  private static Id toParentId(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Id.valueOf(value.trim());
    } catch (StringException e) {
      throw new ALT_CLS_ExpenseWizard.ExpenseWizardException(
        'A categoria pai é inválida.'
      );
    }
  }

  // A blank or malformed JSON gets a readable message instead of the parser's.
  private static Object parse(String requestJson, Type target) {
    if (String.isBlank(requestJson) || requestJson.trim() == 'null') {
      throw new ALT_CLS_ExpenseWizard.ExpenseWizardException(
        'Pedido não informado.'
      );
    }
    try {
      return JSON.deserialize(requestJson, target);
    } catch (JSONException e) {
      throw new ALT_CLS_ExpenseWizard.ExpenseWizardException(
        'Pedido inválido.'
      );
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
