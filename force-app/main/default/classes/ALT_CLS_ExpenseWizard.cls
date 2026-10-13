/**
 * @description Behind the expense wizard (EP05-H19): the options of the holder (expense categories,
 * bank accounts and cards) and the creation of a standalone expense, a single entry. Sharing and
 * FLS apply (user mode), so the entry validation rules are the same as the standard form.
 */
public with sharing class ALT_CLS_ExpenseWizard {
  // Currency fields hold up to 18 digits, 2 of them decimals.
  private static final Decimal MAX_TOTAL = 1000000000000000.00;

  public class Option {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String label;
    // Only for categories: the parent in the hierarchy.
    @AuraEnabled
    public Id parentId;
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

  // Recurring only (EP05-H20): base.dueDate is the first due date, base.amount the monthly (or estimated) value.
  public class RecurringRequest {
    @AuraEnabled
    public Request base;
    @AuraEnabled
    public Boolean variableAmount = false;
    @AuraEnabled
    public Integer dueDay;
    @AuraEnabled
    public Date endDate;
  }

  public class PreviewItem {
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
  }

  // Installments only (EP05-H21): base.amount is the total or the installment value
  // (amountIsTotal), base.dueDate the first due date.
  public class InstallmentRequest {
    @AuraEnabled
    public Request base;
    @AuraEnabled
    public Boolean amountIsTotal = true;
    @AuraEnabled
    public Integer count;
  }

  // Consortium only (EP05-H22): base.amount is the installment value, base.dueDate the first
  // due date; administrator becomes the Contract counterparty.
  public class ConsortiumRequest {
    @AuraEnabled
    public Request base;
    @AuraEnabled
    public Integer count;
    @AuraEnabled
    public String administrator;
    @AuraEnabled
    public Date awardedOn;
  }

  public Options options(Id holderId) {
    Options result = new Options();
    for (AXF_OBJ_Category__c category : [
      SELECT Id, Name, AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE AXF_CAT_PKL_Type__c IN ('Expense', 'Both')
      WITH USER_MODE
      ORDER BY Name
      LIMIT 500
    ]) {
      Option item = option(category.Id, category.Name);
      item.parentId = category.AXF_CAT_LKP_Parent__c;
      result.categories.add(item);
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

  // "+ Nova categoria" of the wizard: a new expense category, optionally under a parent.
  public Option createCategory(String name, Id parentId) {
    if (String.isBlank(name)) {
      throw new ExpenseWizardException('Informe o nome da categoria.');
    }
    String clean = name.trim().left(80);
    if (parentId != null) {
      // The parent must be visible to the user and usable for expenses.
      if (
        [
          SELECT COUNT()
          FROM AXF_OBJ_Category__c
          WHERE Id = :parentId AND AXF_CAT_PKL_Type__c IN ('Expense', 'Both')
          WITH USER_MODE
        ] == 0
      ) {
        throw new ExpenseWizardException('A categoria pai não é de despesa.');
      }
    }
    // Same name under the same parent: reuse it instead of creating a duplicate.
    for (AXF_OBJ_Category__c existing : [
      SELECT Id, Name, AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE
        Name = :clean
        AND AXF_CAT_LKP_Parent__c = :parentId
        AND AXF_CAT_PKL_Type__c IN ('Expense', 'Both')
      WITH USER_MODE
      LIMIT 1
    ]) {
      Option reused = option(existing.Id, existing.Name);
      reused.parentId = existing.AXF_CAT_LKP_Parent__c;
      return reused;
    }
    AXF_OBJ_Category__c category = new AXF_OBJ_Category__c(
      Name = clean,
      AXF_CAT_PKL_Type__c = 'Expense',
      AXF_CAT_LKP_Parent__c = parentId
    );
    insert as user category;
    Option created = option(category.Id, category.Name);
    created.parentId = parentId;
    return created;
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

  // Creates the recurring Contract and its Pending entries in one transaction: a failed
  // generation throws, so nothing stays saved.
  public Id createRecurring(RecurringRequest request) {
    validateRecurring(request);
    Request base = request.base;
    Schema.RecordTypeInfo recordType = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
      .get(ALT_CLS_ContractGeneration.RT_RECURRING);
    if (recordType == null) {
      throw new ExpenseWizardException(
        'O tipo de contrato Recorrente não está disponível.'
      );
    }
    AXF_OBJ_Contract__c contract = new AXF_OBJ_Contract__c(
      Name = base.description.trim().left(80),
      RecordTypeId = recordType.getRecordTypeId(),
      AXF_CTR_MD_Holder__c = base.holderId,
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = ALT_CLS_ContractGeneration.STATUS_ACTIVE,
      AXF_CTR_CUR_Amount__c = base.amount,
      AXF_CTR_DAT_FirstDueDate__c = base.dueDate,
      AXF_CTR_NUM_DueDay__c = request.dueDay != null
        ? request.dueDay
        : base.dueDate.day(),
      AXF_CTR_DAT_EndDate__c = request.endDate,
      AXF_CTR_BOL_VariableAmount__c = request.variableAmount == true,
      AXF_CTR_LKP_Category__c = base.categoryId,
      AXF_CTR_LKP_BankAccount__c = base.accountId,
      AXF_CTR_LKP_CreditCard__c = base.cardId
    );
    Savepoint savepoint = Database.setSavepoint();
    try {
      insert as user contract;
      ALT_CLS_ContractGeneration.Result result = new ALT_CLS_ContractGeneration()
        .generate(new Set<Id>{ contract.Id }, false);
      // A contract without entries (or with some that failed) is not what the user asked for.
      if (!result.messages.isEmpty() || result.created == 0) {
        throw new ExpenseWizardException(
          result.messages.isEmpty()
            ? 'Nenhum lançamento seria gerado para este período.'
            : String.join(result.messages, ' ')
        );
      }
    } catch (Exception e) {
      // Nothing stays saved, even for a caller that catches the exception.
      Database.rollback(savepoint);
      throw e;
    }
    return contract.Id;
  }

  public List<PreviewItem> previewRecurring(RecurringRequest request) {
    validateRecurring(request);
    List<PreviewItem> items = new List<PreviewItem>();
    for (
      ALT_CLS_ContractSchedule.Item item : ALT_CLS_ContractSchedule.recurring(
        request.base.dueDate,
        request.dueDay,
        request.endDate,
        Date.today(),
        request.base.amount
      )
    ) {
      PreviewItem preview = new PreviewItem();
      preview.dueDate = item.dueDate;
      preview.amount = item.amount;
      items.add(preview);
    }
    if (items.isEmpty()) {
      throw new ExpenseWizardException(
        'Nenhum lançamento seria gerado para este período.'
      );
    }
    return items;
  }

  private static void validateRecurring(RecurringRequest request) {
    Request base = request?.base;
    if (base == null || base.holderId == null) {
      throw new ExpenseWizardException('Informe o titular.');
    }
    if (String.isBlank(base.description)) {
      throw new ExpenseWizardException('Informe a descrição.');
    }
    if (base.amount == null || base.amount <= 0) {
      throw new ExpenseWizardException('O valor deve ser maior que zero.');
    }
    if (base.dueDate == null) {
      throw new ExpenseWizardException('Informe o primeiro vencimento.');
    }
    if (request.dueDay != null && (request.dueDay < 1 || request.dueDay > 31)) {
      throw new ExpenseWizardException(
        'O dia do vencimento deve ser de 1 a 31.'
      );
    }
    if (request.endDate != null && request.endDate < base.dueDate) {
      throw new ExpenseWizardException(
        'A data de fim não pode ser anterior ao primeiro vencimento.'
      );
    }
    if (base.accountId != null && base.cardId != null) {
      throw new ExpenseWizardException(
        'Escolha a conta ou o cartão, não os dois.'
      );
    }
    assertOwnership(base);
  }

  // Creates the installment Contract and its Pending entries in one transaction. The installment
  // is the total divided by the count (2 decimals); the rounding residue goes to the last entry
  // so the entries always add up to the total.
  public Id createInstallment(InstallmentRequest request) {
    List<PreviewItem> plan = plan(request);
    Request base = request.base;
    Decimal installment = plan[0].amount;
    AXF_OBJ_Contract__c contract = new AXF_OBJ_Contract__c(
      Name = base.description.trim().left(80),
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get(ALT_CLS_ContractGeneration.RT_INSTALLMENT)
        .getRecordTypeId(),
      AXF_CTR_MD_Holder__c = base.holderId,
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = ALT_CLS_ContractGeneration.STATUS_ACTIVE,
      AXF_CTR_CUR_Amount__c = installment,
      AXF_CTR_NUM_InstallmentCount__c = request.count,
      AXF_CTR_DAT_FirstDueDate__c = base.dueDate,
      AXF_CTR_LKP_Category__c = base.categoryId,
      AXF_CTR_LKP_BankAccount__c = base.accountId,
      AXF_CTR_LKP_CreditCard__c = base.cardId
    );
    Savepoint savepoint = Database.setSavepoint();
    try {
      insert as user contract;
      ALT_CLS_ContractGeneration.Result result = new ALT_CLS_ContractGeneration()
        .generate(new Set<Id>{ contract.Id }, false);
      if (!result.messages.isEmpty() || result.created != request.count) {
        throw new ExpenseWizardException(
          result.messages.isEmpty()
            ? 'Não foi possível gerar todas as parcelas.'
            : String.join(result.messages, ' ')
        );
      }
      adjustLastInstallment(
        contract.Id,
        request.count,
        plan[plan.size() - 1].amount,
        installment
      );
    } catch (Exception e) {
      // Nothing stays saved: no Contract without every installment.
      Database.rollback(savepoint);
      throw e;
    }
    return contract.Id;
  }

  // The rounding residue goes to the last entry so the entries add up to the total.
  private static void adjustLastInstallment(
    Id contractId,
    Integer count,
    Decimal lastAmount,
    Decimal installment
  ) {
    if (lastAmount == installment) {
      return;
    }
    List<AXF_OBJ_Entry__c> rows = [
      SELECT Id
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_LKP_Contract__c = :contractId
        AND AXF_ENT_NUM_InstallmentNumber__c = :count
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new ExpenseWizardException(
        'Não foi possível ajustar a última parcela.'
      );
    }
    rows[0].AXF_ENT_CUR_Amount__c = lastAmount;
    update as user rows;
  }

  public List<PreviewItem> previewInstallment(InstallmentRequest request) {
    return plan(request);
  }

  private static List<PreviewItem> plan(InstallmentRequest request) {
    Request base = request?.base;
    if (base == null || base.holderId == null) {
      throw new ExpenseWizardException('Informe o titular.');
    }
    if (String.isBlank(base.description)) {
      throw new ExpenseWizardException('Informe a descrição.');
    }
    if (base.amount == null || base.amount <= 0) {
      throw new ExpenseWizardException('O valor deve ser maior que zero.');
    }
    if (request.count == null || request.count < 2 || request.count > 120) {
      throw new ExpenseWizardException(
        'O número de parcelas deve ser de 2 a 120.'
      );
    }
    if (base.dueDate == null) {
      throw new ExpenseWizardException('Informe o primeiro vencimento.');
    }
    if (base.accountId != null && base.cardId != null) {
      throw new ExpenseWizardException(
        'Escolha a conta ou o cartão, não os dois.'
      );
    }
    assertOwnership(base);
    // Both modes round the installment the same way; the total of "parcela" mode is that
    // installment times the count, so the entries always add up to what the user saw.
    Boolean informsTotal = request.amountIsTotal != false;
    Decimal installment = informsTotal
      ? (base.amount.setScale(2, RoundingMode.HALF_UP) / request.count)
          .setScale(2, RoundingMode.HALF_UP)
      : base.amount.setScale(2, RoundingMode.HALF_UP);
    Decimal total = informsTotal
      ? base.amount.setScale(2, RoundingMode.HALF_UP)
      : installment * request.count;
    if (total >= MAX_TOTAL) {
      throw new ExpenseWizardException('O valor total está acima do limite.');
    }
    if (installment <= 0) {
      throw new ExpenseWizardException(
        'O valor da parcela deve ser maior que zero.'
      );
    }
    // Rounding up can leave nothing (or less) for the last installment on tiny totals.
    if (total - installment * (request.count - 1) <= 0) {
      throw new ExpenseWizardException(
        'O valor total é pequeno demais para este número de parcelas.'
      );
    }
    List<PreviewItem> items = new List<PreviewItem>();
    for (
      ALT_CLS_ContractSchedule.Item item : ALT_CLS_ContractSchedule.fixedInstallments(
        base.dueDate,
        request.count,
        installment
      )
    ) {
      PreviewItem preview = new PreviewItem();
      preview.dueDate = item.dueDate;
      preview.amount = item.amount;
      items.add(preview);
    }
    items[items.size() - 1].amount = total - installment * (request.count - 1);
    return items;
  }

  // Creates the consortium Contract and its Pending entries in one transaction.
  public Id createConsortium(ConsortiumRequest request) {
    List<PreviewItem> plan = planConsortium(request);
    Request base = request.base;
    Schema.RecordTypeInfo recordType = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
      .get(ALT_CLS_ContractGeneration.RT_CONSORTIUM);
    if (recordType == null) {
      throw new ExpenseWizardException(
        'O tipo de contrato Consórcio não está disponível.'
      );
    }
    AXF_OBJ_Contract__c contract = new AXF_OBJ_Contract__c(
      Name = base.description.trim().left(80),
      RecordTypeId = recordType.getRecordTypeId(),
      AXF_CTR_MD_Holder__c = base.holderId,
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = ALT_CLS_ContractGeneration.STATUS_ACTIVE,
      AXF_CTR_CUR_Amount__c = plan[0].amount,
      AXF_CTR_NUM_InstallmentCount__c = request.count,
      AXF_CTR_DAT_FirstDueDate__c = base.dueDate,
      AXF_CTR_TXT_Counterparty__c = String.isBlank(request.administrator)
        ? null
        : request.administrator.trim(),
      AXF_CTR_DAT_AwardedOn__c = request.awardedOn,
      AXF_CTR_LKP_Category__c = base.categoryId,
      AXF_CTR_LKP_BankAccount__c = base.accountId,
      AXF_CTR_LKP_CreditCard__c = base.cardId
    );
    Savepoint savepoint = Database.setSavepoint();
    try {
      insert as user contract;
      ALT_CLS_ContractGeneration.Result result = new ALT_CLS_ContractGeneration()
        .generate(new Set<Id>{ contract.Id }, false);
      requireComplete(result, request.count);
    } catch (Exception e) {
      // Nothing stays saved: no Contract without every installment.
      Database.rollback(savepoint);
      throw e;
    }
    return contract.Id;
  }

  // Generation must create every installment; anything else undoes the Contract.
  @TestVisible
  private static void requireComplete(
    ALT_CLS_ContractGeneration.Result result,
    Integer expected
  ) {
    if (!result.messages.isEmpty() || result.created != expected) {
      throw new ExpenseWizardException(
        result.messages.isEmpty()
          ? 'Não foi possível gerar todas as parcelas.'
          : String.join(result.messages, ' ')
      );
    }
  }

  public List<PreviewItem> previewConsortium(ConsortiumRequest request) {
    return planConsortium(request);
  }

  private static List<PreviewItem> planConsortium(ConsortiumRequest request) {
    Request base = request?.base;
    if (base == null || base.holderId == null) {
      throw new ExpenseWizardException('Informe o titular.');
    }
    if (String.isBlank(base.description)) {
      throw new ExpenseWizardException('Informe a descrição.');
    }
    if (base.amount == null || base.amount <= 0) {
      throw new ExpenseWizardException('O valor deve ser maior que zero.');
    }
    if (request.count == null || request.count < 2 || request.count > 240) {
      throw new ExpenseWizardException(
        'O número de parcelas deve ser de 2 a 240.'
      );
    }
    if (base.dueDate == null) {
      throw new ExpenseWizardException('Informe o primeiro vencimento.');
    }
    if (
      request.administrator != null &&
      request.administrator.trim().length() > 120
    ) {
      throw new ExpenseWizardException(
        'O nome da administradora deve ter até 120 caracteres.'
      );
    }
    if (base.accountId != null && base.cardId != null) {
      throw new ExpenseWizardException(
        'Escolha a conta ou o cartão, não os dois.'
      );
    }
    assertOwnership(base);
    Decimal installment = base.amount.setScale(2, RoundingMode.HALF_UP);
    if (installment <= 0) {
      throw new ExpenseWizardException(
        'O valor da parcela deve ser maior que zero.'
      );
    }
    if (installment * request.count >= MAX_TOTAL) {
      throw new ExpenseWizardException('O valor total está acima do limite.');
    }
    List<PreviewItem> items = new List<PreviewItem>();
    for (
      ALT_CLS_ContractSchedule.Item item : ALT_CLS_ContractSchedule.fixedInstallments(
        base.dueDate,
        request.count,
        installment
      )
    ) {
      PreviewItem preview = new PreviewItem();
      preview.dueDate = item.dueDate;
      preview.amount = item.amount;
      items.add(preview);
    }
    return items;
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
