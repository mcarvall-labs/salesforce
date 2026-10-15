/**
 * @description Plans which Pending entries of a contract take each edited contract field, per
 * the scope the user chose for that field (ALL, FUTURE, FROM, MONTH, OVERDUE, NONE). Pure
 * calculation: no DML. The desired value of every entry comes from the contract's own schedule
 * (ALT_CLS_ContractGeneration), so the last fixed installment keeps absorbing the rounding
 * residue. Realized, reconciled and canceled entries are never part of the plan.
 */
public with sharing class ALT_CLS_ContractScope {
  public static final String SCOPE_ALL = 'ALL';
  public static final String SCOPE_FUTURE = 'FUTURE';
  public static final String SCOPE_FROM = 'FROM';
  public static final String SCOPE_MONTH = 'MONTH';
  public static final String SCOPE_OVERDUE = 'OVERDUE';
  public static final String SCOPE_NONE = 'NONE';

  public static final String FIELD_NAME = 'NAME';
  public static final String FIELD_AMOUNT = 'AMOUNT';
  public static final String FIELD_DUE = 'DUE';
  public static final String FIELD_CATEGORY = 'CATEGORY';
  public static final String FIELD_ACCOUNT = 'ACCOUNT';

  public static final String OUTCOME_UPDATE = 'UPDATE';
  public static final String OUTCOME_KEEP = 'KEEP';
  public static final String OUTCOME_PRESERVED = 'PRESERVED';

  public class ScopeException extends Exception {
  }

  public class Choice {
    public String scope;
    // Only for FROM: the first installment (or position, when recurring) that is included.
    public Integer fromNumber;

    public Choice(String scope, Integer fromNumber) {
      this.scope = scope;
      this.fromNumber = fromNumber;
    }
  }

  public class Row {
    public Id entryId;
    public Integer ordinal;
    public String status;
    public String outcome;
    public String name;
    public String newName;
    public Date dueDate;
    public Date newDueDate;
    public Decimal amount;
    public Decimal newAmount;
    // PT-BR labels of the Category / Account-Card changes (shown in the preview).
    public List<String> changedFields = new List<String>();
  }

  public class Plan {
    public List<Row> rows = new List<Row>();
    // Entries (only the changed fields) to update.
    public List<AXF_OBJ_Entry__c> toUpdate = new List<AXF_OBJ_Entry__c>();
    public Integer updated = 0;
    public Integer kept = 0;
    public Integer preserved = 0;
    // Installments the contract now has that no entry covers yet (created on save).
    public Integer missing = 0;
  }

  @TestVisible
  private Date today = Date.today();

  public ALT_CLS_ContractScope() {
  }

  public ALT_CLS_ContractScope(Date referenceDate) {
    this.today = referenceDate;
  }

  // `proposed` is the contract as it will be saved (RecordType.DeveloperName loaded).
  public Plan plan(AXF_OBJ_Contract__c proposed, Map<String, Choice> choices) {
    Plan result = new Plan();
    Boolean recurring =
      proposed.RecordType.DeveloperName ==
      ALT_CLS_ContractGeneration.RT_RECURRING;
    List<AXF_OBJ_Entry__c> entries = existing(proposed.Id);
    Map<String, AXF_OBJ_Entry__c> desired = new Map<String, AXF_OBJ_Entry__c>();
    if (
      proposed.AXF_CTR_PKL_Status__c == ALT_CLS_ContractGeneration.STATUS_ACTIVE
    ) {
      String problem = ALT_CLS_ContractGeneration.problem(proposed);
      if (problem != null) {
        throw new ScopeException(problem);
      }
      desired = new ALT_CLS_ContractGeneration(today).desiredEntries(proposed);
    }
    Set<String> seen = new Set<String>();
    Integer position = 0;
    for (AXF_OBJ_Entry__c entry : entries) {
      position++;
      Row row = new Row();
      row.entryId = entry.Id;
      row.status = entry.AXF_ENT_PKL_Status__c;
      row.name = entry.Name;
      row.newName = entry.Name;
      row.dueDate = entry.AXF_ENT_DAT_DueDate__c;
      row.newDueDate = entry.AXF_ENT_DAT_DueDate__c;
      row.amount = entry.AXF_ENT_CUR_Amount__c;
      row.newAmount = entry.AXF_ENT_CUR_Amount__c;
      row.ordinal = recurring
        ? position
        : entry.AXF_ENT_NUM_InstallmentNumber__c?.intValue();
      result.rows.add(row);
      Boolean keyed = recurring
        ? entry.AXF_ENT_DAT_Competence__c != null
        : entry.AXF_ENT_NUM_InstallmentNumber__c != null;
      String key = keyed
        ? ALT_CLS_ContractGeneration.entryKey(recurring, entry)
        : null;
      if (key != null) {
        seen.add(key);
      }
      if (
        entry.AXF_ENT_PKL_Status__c != ALT_CLS_ContractGeneration.ENTRY_PENDING
      ) {
        row.outcome = OUTCOME_PRESERVED;
        result.preserved++;
        continue;
      }
      AXF_OBJ_Entry__c want = key == null ? null : desired.get(key);
      AXF_OBJ_Entry__c change = new AXF_OBJ_Entry__c(Id = entry.Id);
      Boolean changed = false;
      if (want != null) {
        if (
          included(FIELD_NAME, choices, row, entry) &&
          !want.Name.equals(entry.Name)
        ) {
          change.Name = want.Name;
          row.newName = want.Name;
          changed = true;
        }
        if (
          included(FIELD_AMOUNT, choices, row, entry) &&
          want.AXF_ENT_CUR_Amount__c != entry.AXF_ENT_CUR_Amount__c
        ) {
          change.AXF_ENT_CUR_Amount__c = want.AXF_ENT_CUR_Amount__c;
          row.newAmount = want.AXF_ENT_CUR_Amount__c;
          changed = true;
        }
        if (
          included(FIELD_DUE, choices, row, entry) &&
          (want.AXF_ENT_DAT_DueDate__c != entry.AXF_ENT_DAT_DueDate__c ||
          want.AXF_ENT_DAT_Competence__c != entry.AXF_ENT_DAT_Competence__c)
        ) {
          change.AXF_ENT_DAT_DueDate__c = want.AXF_ENT_DAT_DueDate__c;
          change.AXF_ENT_DAT_Competence__c = want.AXF_ENT_DAT_Competence__c;
          row.newDueDate = want.AXF_ENT_DAT_DueDate__c;
          changed = true;
        }
        if (
          included(FIELD_CATEGORY, choices, row, entry) &&
          want.AXF_ENT_LKP_Category__c != entry.AXF_ENT_LKP_Category__c
        ) {
          change.AXF_ENT_LKP_Category__c = want.AXF_ENT_LKP_Category__c;
          row.changedFields.add('Categoria');
          changed = true;
        }
        if (
          included(FIELD_ACCOUNT, choices, row, entry) &&
          (want.AXF_ENT_LKP_BankAccount__c !=
          entry.AXF_ENT_LKP_BankAccount__c ||
          want.AXF_ENT_LKP_CreditCard__c != entry.AXF_ENT_LKP_CreditCard__c)
        ) {
          change.AXF_ENT_LKP_BankAccount__c = want.AXF_ENT_LKP_BankAccount__c;
          change.AXF_ENT_LKP_CreditCard__c = want.AXF_ENT_LKP_CreditCard__c;
          row.changedFields.add('Conta/Cartão');
          changed = true;
        }
      }
      if (changed) {
        row.outcome = OUTCOME_UPDATE;
        result.updated++;
        result.toUpdate.add(change);
      } else {
        row.outcome = OUTCOME_KEEP;
        result.kept++;
      }
    }
    for (String key : desired.keySet()) {
      if (!seen.contains(key)) {
        result.missing++;
      }
    }
    return result;
  }

  private Boolean included(
    String field,
    Map<String, Choice> choices,
    Row row,
    AXF_OBJ_Entry__c entry
  ) {
    Choice choice = choices?.get(field);
    if (choice == null || choice.scope == null) {
      return false;
    }
    Date due = entry.AXF_ENT_DAT_DueDate__c;
    if (choice.scope == SCOPE_ALL) {
      return true;
    }
    if (due == null) {
      return false;
    }
    if (choice.scope == SCOPE_FUTURE) {
      return due > today;
    }
    if (choice.scope == SCOPE_OVERDUE) {
      return due < today;
    }
    if (choice.scope == SCOPE_MONTH) {
      return due.year() == today.year() && due.month() == today.month();
    }
    if (choice.scope == SCOPE_FROM) {
      return row.ordinal != null &&
        choice.fromNumber != null &&
        row.ordinal >= choice.fromNumber;
    }
    return false;
  }

  private static List<AXF_OBJ_Entry__c> existing(Id contractId) {
    return [
      SELECT
        Id,
        Name,
        AXF_ENT_DAT_Competence__c,
        AXF_ENT_NUM_InstallmentNumber__c,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_PKL_Status__c,
        AXF_ENT_LKP_Category__c,
        AXF_ENT_LKP_BankAccount__c,
        AXF_ENT_LKP_CreditCard__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :contractId
      WITH USER_MODE
      ORDER BY AXF_ENT_DAT_DueDate__c ASC, Id ASC
    ];
  }
}
