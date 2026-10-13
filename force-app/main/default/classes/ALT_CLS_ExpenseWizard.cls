/**
 * @description Behind the expense wizard (EP05-H19): the options of the holder (expense categories,
 * bank accounts and cards) and the creation of a standalone expense, a single entry. Sharing and
 * FLS apply (user mode), so the entry validation rules are the same as the standard form.
 */
public with sharing class ALT_CLS_ExpenseWizard {
  public class Option {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String label;
  }

  public class Options {
    @AuraEnabled
    public List<Option> categories = new List<Option>();
    @AuraEnabled
    public List<Option> accounts = new List<Option>();
    @AuraEnabled
    public List<Option> cards = new List<Option>();
  }

  public class Request {
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Id categoryId;
    // Pending or Realized
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date paymentDate;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public Id cardId;
  }

  public Options options(Id holderId) {
    Options result = new Options();
    for (AXF_OBJ_Category__c category : [
      SELECT Id, Name
      FROM AXF_OBJ_Category__c
      WHERE AXF_CAT_PKL_Type__c IN ('Expense', 'Both')
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      result.categories.add(option(category.Id, category.Name));
    }
    if (holderId == null) {
      return result;
    }
    for (AXF_OBJ_BankAccount__c account : [
      SELECT Id, Name
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_MD_Holder__c = :holderId
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      result.accounts.add(option(account.Id, account.Name));
    }
    for (AXF_OBJ_CreditCard__c card : [
      SELECT Id, Name
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_MD_Holder__c = :holderId
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      result.cards.add(option(card.Id, card.Name));
    }
    return result;
  }

  public Id createStandalone(Request request) {
    if (request == null || request.holderId == null) {
      throw new ExpenseWizardException('Informe o titular.');
    }
    if (String.isBlank(request.description)) {
      throw new ExpenseWizardException('Informe a descrição.');
    }
    if (request.amount == null || request.amount <= 0) {
      throw new ExpenseWizardException('O valor deve ser maior que zero.');
    }
    if (request.dueDate == null) {
      throw new ExpenseWizardException('Informe o vencimento.');
    }
    Boolean realized = request.status == 'Realized';
    if (request.status != 'Pending' && !realized) {
      throw new ExpenseWizardException('Situação inválida.');
    }
    if (realized && request.paymentDate == null) {
      throw new ExpenseWizardException('Informe a data de pagamento.');
    }
    if (request.accountId != null && request.cardId != null) {
      throw new ExpenseWizardException(
        'Escolha a conta ou o cartão, não os dois.'
      );
    }
    assertOwnership(request);
    AXF_OBJ_Entry__c entry = new AXF_OBJ_Entry__c(
      Name = request.description.trim().left(80),
      AXF_ENT_MD_Holder__c = request.holderId,
      AXF_ENT_CUR_Amount__c = request.amount,
      AXF_ENT_DAT_DueDate__c = request.dueDate,
      AXF_ENT_LKP_Category__c = request.categoryId,
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = request.status,
      AXF_ENT_DAT_PaymentDate__c = realized ? request.paymentDate : null,
      AXF_ENT_LKP_BankAccount__c = request.accountId,
      AXF_ENT_LKP_CreditCard__c = request.cardId
    );
    insert as user entry;
    return entry.Id;
  }

  // The UI only offers the holder's own records; a crafted request must not get around it.
  private static void assertOwnership(Request request) {
    if (
      request.accountId != null &&
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE
          Id = :request.accountId
          AND AXF_BA_MD_Holder__c = :request.holderId
        WITH USER_MODE
      ] == 0
    ) {
      throw new ExpenseWizardException('A conta não pertence ao titular.');
    }
    if (
      request.cardId != null &&
      [
        SELECT COUNT()
        FROM AXF_OBJ_CreditCard__c
        WHERE Id = :request.cardId AND AXF_CC_MD_Holder__c = :request.holderId
        WITH USER_MODE
      ] == 0
    ) {
      throw new ExpenseWizardException('O cartão não pertence ao titular.');
    }
    if (
      request.categoryId != null &&
      [
        SELECT COUNT()
        FROM AXF_OBJ_Category__c
        WHERE
          Id = :request.categoryId
          AND AXF_CAT_PKL_Type__c IN ('Expense', 'Both')
        WITH USER_MODE
      ] == 0
    ) {
      throw new ExpenseWizardException('A categoria não é de despesa.');
    }
  }

  private static Option option(Id id, String label) {
    Option result = new Option();
    result.id = id;
    result.label = label;
    return result;
  }

  public class ExpenseWizardException extends Exception {
  }
}
