/**
 * @description Generates the Pending entries (AXF_OBJ_Entry__c) of a contract. Recurring: up to
 * the end date or 12 months ahead; installment, consortium and financing: every installment at
 * once. Safe to run again: an entry already linked to the contract for the same competence
 * (recurring) or installment number (the others) is never duplicated. Realized entries never
 * change; with `updatePending`, Pending entries due today or later get the contract's current
 * amount, date and source (a manual edit on them is overwritten). Service contracts are not
 * handled here: their monthly entry comes from the timesheet.
 */
public with sharing class ALT_CLS_ContractGeneration {
  public static final String RT_RECURRING = 'AXF_Recurring';
  public static final String RT_INSTALLMENT = 'AXF_Installment';
  public static final String RT_CONSORTIUM = 'AXF_Consortium';
  public static final String RT_FINANCING = 'AXF_Financing';
  public static final String STATUS_ACTIVE = 'Active';
  public static final String ENTRY_PENDING = 'Pending';

  public class Result {
    public Integer created = 0;
    public Integer updated = 0;
    // One message per contract that was skipped or per record that failed to save.
    public List<String> messages = new List<String>();
  }

  @TestVisible
  private Date today = Date.today();

  public Result generate(Set<Id> contractIds, Boolean updatePending) {
    Result result = new Result();
    List<AXF_OBJ_Contract__c> contracts = [
      SELECT
        Id,
        Name,
        CurrencyIsoCode,
        RecordType.DeveloperName,
        AXF_CTR_MD_Holder__c,
        AXF_CTR_PKL_Direction__c,
        AXF_CTR_PKL_Status__c,
        AXF_CTR_LKP_Category__c,
        AXF_CTR_LKP_BankAccount__c,
        AXF_CTR_LKP_CreditCard__c,
        AXF_CTR_DAT_FirstDueDate__c,
        AXF_CTR_NUM_DueDay__c,
        AXF_CTR_DAT_EndDate__c,
        AXF_CTR_CUR_Amount__c,
        AXF_CTR_NUM_InstallmentCount__c,
        AXF_CTR_CUR_FinancedAmount__c,
        AXF_CTR_PCT_MonthlyRate__c,
        AXF_CTR_PKL_AmortizationSystem__c
      FROM AXF_OBJ_Contract__c
      WHERE Id IN :contractIds
    ];
    Map<Id, Map<String, AXF_OBJ_Entry__c>> existing = existingEntries(
      contracts
    );
    List<AXF_OBJ_Entry__c> toInsert = new List<AXF_OBJ_Entry__c>();
    List<AXF_OBJ_Entry__c> toUpdate = new List<AXF_OBJ_Entry__c>();
    for (AXF_OBJ_Contract__c contract : contracts) {
      String problem = validate(contract);
      if (problem != null) {
        result.messages.add(contract.Name + ': ' + problem);
        continue;
      }
      Boolean recurring = contract.RecordType.DeveloperName == RT_RECURRING;
      Map<String, AXF_OBJ_Entry__c> current = existing.get(contract.Id);
      List<ALT_CLS_ContractSchedule.Item> items = schedule(contract);
      for (ALT_CLS_ContractSchedule.Item item : items) {
        AXF_OBJ_Entry__c desired = build(
          contract,
          item,
          items.size(),
          recurring
        );
        AXF_OBJ_Entry__c found = current?.get(key(recurring, desired));
        if (found == null) {
          toInsert.add(desired);
        } else if (updatePending && isPendingAndNotPast(found)) {
          if (differs(found, desired)) {
            desired.Id = found.Id;
            toUpdate.add(desired);
          }
        }
      }
    }
    save(toInsert, true, result);
    save(toUpdate, false, result);
    return result;
  }

  private static String validate(AXF_OBJ_Contract__c contract) {
    String type = contract.RecordType.DeveloperName;
    if (contract.AXF_CTR_PKL_Status__c != STATUS_ACTIVE) {
      return 'contrato encerrado, nada a gerar.';
    }
    if (
      type != RT_RECURRING &&
      type != RT_INSTALLMENT &&
      type != RT_CONSORTIUM &&
      type != RT_FINANCING
    ) {
      return 'este tipo não gera lançamentos por aqui.';
    }
    if (contract.AXF_CTR_DAT_FirstDueDate__c == null) {
      return 'informe o primeiro vencimento.';
    }
    if (type == RT_FINANCING) {
      if (
        contract.AXF_CTR_CUR_FinancedAmount__c == null ||
        contract.AXF_CTR_CUR_FinancedAmount__c <= 0 ||
        contract.AXF_CTR_PCT_MonthlyRate__c == null ||
        contract.AXF_CTR_PCT_MonthlyRate__c < 0 ||
        contract.AXF_CTR_PKL_AmortizationSystem__c == null
      ) {
        return 'informe valor financiado, taxa mensal e sistema (SAC ou PRICE).';
      }
    } else if (
      contract.AXF_CTR_CUR_Amount__c == null ||
      contract.AXF_CTR_CUR_Amount__c <= 0
    ) {
      return 'informe o valor.';
    }
    if (
      type != RT_RECURRING &&
      (contract.AXF_CTR_NUM_InstallmentCount__c == null ||
      contract.AXF_CTR_NUM_InstallmentCount__c < 1)
    ) {
      return 'informe o número de parcelas.';
    }
    return null;
  }

  private List<ALT_CLS_ContractSchedule.Item> schedule(
    AXF_OBJ_Contract__c contract
  ) {
    String type = contract.RecordType.DeveloperName;
    Date firstDue = contract.AXF_CTR_DAT_FirstDueDate__c;
    if (type == RT_RECURRING) {
      return ALT_CLS_ContractSchedule.recurring(
        firstDue,
        contract.AXF_CTR_NUM_DueDay__c?.intValue(),
        contract.AXF_CTR_DAT_EndDate__c,
        today,
        contract.AXF_CTR_CUR_Amount__c
      );
    }
    Integer count = contract.AXF_CTR_NUM_InstallmentCount__c.intValue();
    if (type == RT_FINANCING) {
      return ALT_CLS_ContractSchedule.financing(
        contract.AXF_CTR_CUR_FinancedAmount__c,
        contract.AXF_CTR_PCT_MonthlyRate__c,
        count,
        contract.AXF_CTR_PKL_AmortizationSystem__c,
        firstDue
      );
    }
    return ALT_CLS_ContractSchedule.fixedInstallments(
      firstDue,
      count,
      contract.AXF_CTR_CUR_Amount__c
    );
  }

  private static AXF_OBJ_Entry__c build(
    AXF_OBJ_Contract__c contract,
    ALT_CLS_ContractSchedule.Item item,
    Integer total,
    Boolean recurring
  ) {
    String label = recurring
      ? item.dueDate.month() + '/' + item.dueDate.year()
      : item.installmentNumber + '/' + total;
    return new AXF_OBJ_Entry__c(
      Name = (contract.Name + ' ' + label).abbreviate(80),
      AXF_ENT_MD_Holder__c = contract.AXF_CTR_MD_Holder__c,
      AXF_ENT_LKP_Contract__c = contract.Id,
      AXF_ENT_PKL_Type__c = contract.AXF_CTR_PKL_Direction__c,
      AXF_ENT_PKL_Status__c = ENTRY_PENDING,
      AXF_ENT_CUR_Amount__c = item.amount,
      AXF_ENT_DAT_DueDate__c = item.dueDate,
      AXF_ENT_DAT_Competence__c = item.dueDate.toStartOfMonth(),
      AXF_ENT_NUM_InstallmentNumber__c = recurring
        ? null
        : item.installmentNumber,
      AXF_ENT_LKP_Category__c = contract.AXF_CTR_LKP_Category__c,
      AXF_ENT_LKP_BankAccount__c = contract.AXF_CTR_LKP_BankAccount__c,
      AXF_ENT_LKP_CreditCard__c = contract.AXF_CTR_LKP_CreditCard__c,
      CurrencyIsoCode = contract.CurrencyIsoCode
    );
  }

  // Recurring entries are told apart by competence, the others by installment number.
  private static String key(Boolean recurring, AXF_OBJ_Entry__c entry) {
    return recurring
      ? 'C' + String.valueOf(entry.AXF_ENT_DAT_Competence__c)
      : 'N' +
        String.valueOf(entry.AXF_ENT_NUM_InstallmentNumber__c?.intValue());
  }

  private Boolean isPendingAndNotPast(AXF_OBJ_Entry__c entry) {
    return entry.AXF_ENT_PKL_Status__c == ENTRY_PENDING &&
      entry.AXF_ENT_DAT_DueDate__c >= today;
  }

  private static Boolean differs(
    AXF_OBJ_Entry__c found,
    AXF_OBJ_Entry__c desired
  ) {
    return found.Name != desired.Name ||
      found.AXF_ENT_CUR_Amount__c != desired.AXF_ENT_CUR_Amount__c ||
      found.AXF_ENT_DAT_DueDate__c != desired.AXF_ENT_DAT_DueDate__c ||
      found.AXF_ENT_DAT_Competence__c != desired.AXF_ENT_DAT_Competence__c ||
      found.AXF_ENT_PKL_Type__c != desired.AXF_ENT_PKL_Type__c ||
      found.AXF_ENT_LKP_Category__c != desired.AXF_ENT_LKP_Category__c ||
      found.AXF_ENT_LKP_BankAccount__c != desired.AXF_ENT_LKP_BankAccount__c ||
      found.AXF_ENT_LKP_CreditCard__c != desired.AXF_ENT_LKP_CreditCard__c ||
      found.CurrencyIsoCode != desired.CurrencyIsoCode;
  }

  private static Map<Id, Map<String, AXF_OBJ_Entry__c>> existingEntries(
    List<AXF_OBJ_Contract__c> contracts
  ) {
    Map<Id, Map<String, AXF_OBJ_Entry__c>> byContract = new Map<Id, Map<String, AXF_OBJ_Entry__c>>();
    Map<Id, Boolean> recurringContracts = new Map<Id, Boolean>();
    Set<Id> contractIds = new Set<Id>();
    for (AXF_OBJ_Contract__c c : contracts) {
      contractIds.add(c.Id);
      recurringContracts.put(c.Id, c.RecordType.DeveloperName == RT_RECURRING);
    }
    for (AXF_OBJ_Entry__c entry : [
      SELECT
        Id,
        Name,
        AXF_ENT_LKP_Contract__c,
        AXF_ENT_DAT_Competence__c,
        AXF_ENT_NUM_InstallmentNumber__c,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_PKL_Status__c,
        AXF_ENT_PKL_Type__c,
        AXF_ENT_LKP_Category__c,
        AXF_ENT_LKP_BankAccount__c,
        AXF_ENT_LKP_CreditCard__c,
        CurrencyIsoCode
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c IN :contractIds
    ]) {
      Boolean recurring = recurringContracts.get(entry.AXF_ENT_LKP_Contract__c);
      if (
        recurring
          ? entry.AXF_ENT_DAT_Competence__c == null
          : entry.AXF_ENT_NUM_InstallmentNumber__c == null
      ) {
        continue;
      }
      if (!byContract.containsKey(entry.AXF_ENT_LKP_Contract__c)) {
        byContract.put(
          entry.AXF_ENT_LKP_Contract__c,
          new Map<String, AXF_OBJ_Entry__c>()
        );
      }
      byContract.get(entry.AXF_ENT_LKP_Contract__c)
        .put(key(recurring, entry), entry);
    }
    return byContract;
  }

  private static void save(
    List<AXF_OBJ_Entry__c> entries,
    Boolean isInsert,
    Result result
  ) {
    if (entries.isEmpty()) {
      return;
    }
    List<Database.SaveResult> saves = isInsert
      ? Database.insert(entries, false)
      : Database.update(entries, false);
    for (Integer i = 0; i < saves.size(); i++) {
      if (saves[i].isSuccess()) {
        if (isInsert) {
          result.created++;
        } else {
          result.updated++;
        }
      } else {
        result.messages.add(
          entries[i].Name + ': ' + saves[i].getErrors()[0].getMessage()
        );
      }
    }
  }
}
