/**
 * @description Aggregation behind the Axon home dashboard. Amounts are converted to the running
 * user's currency (BRL for Axon users) with the org rate. Sharing applies: a user only sums what the holders shared
 * with them. "All holders" (null holder) sums every holder the user can see.
 *
 * Overdue = pending entries that affect cash, due before today, of any month.
 * Due soon = pending entries that affect cash, due from today to the end of the selected month.
 * Income/expense of the month = entries that affect cash, due in the selected month (any status).
 * Projected balance = current balance of the bank accounts + pending cash income - pending cash
 * expense due up to the end of the month (overdue included). The card forecast is the pending
 * card entries (not yet in an invoice) due up to the end of the month, overdue included; it is subtracted only in
 * projectedBalanceWithCard.
 */
public with sharing class ALT_CLS_Dashboard {
  public class Holder {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
  }

  public class Summary {
    @AuraEnabled
    public String currencyCode = UserInfo.getDefaultCurrency();
    @AuraEnabled
    public Date monthStart;
    @AuraEnabled
    public Date monthEnd;
    @AuraEnabled
    public Decimal overdueExpense = 0;
    @AuraEnabled
    public Decimal overdueIncome = 0;
    @AuraEnabled
    public Integer overdueCount = 0;
    @AuraEnabled
    public Decimal dueSoonExpense = 0;
    @AuraEnabled
    public Decimal dueSoonIncome = 0;
    @AuraEnabled
    public Integer dueSoonCount = 0;
    @AuraEnabled
    public Decimal income = 0;
    @AuraEnabled
    public Decimal expense = 0;
    @AuraEnabled
    public Decimal incomeRealized = 0;
    @AuraEnabled
    public Decimal expenseRealized = 0;
    @AuraEnabled
    public Decimal currentBalance = 0;
    @AuraEnabled
    public Decimal cardForecast = 0;
    @AuraEnabled
    public Decimal projectedBalance = 0;
    @AuraEnabled
    public Decimal projectedBalanceWithCard = 0;
  }

  public class EntryRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String holderName;
    @AuraEnabled
    public String categoryName;
    @AuraEnabled
    public Boolean overdue = false;
    @AuraEnabled
    public Boolean forecastCard = false;
    @AuraEnabled
    public Boolean invoice = false;
  }

  public class EntryList {
    @AuraEnabled
    public List<EntryRow> rows = new List<EntryRow>();
    @AuraEnabled
    public Boolean truncated = false;
  }

  public static final String FILTER_OVERDUE = 'OVERDUE';
  public static final String FILTER_DUE_SOON = 'DUE_SOON';

  @TestVisible
  private static Integer maxRows = 200;

  private static final Set<String> HOLDER_RECORD_TYPES = new Set<String>{
    'AXF_Person',
    'AXF_Business'
  };

  // Holders that appear in the filter: Pessoa Física and Pessoa Jurídica. Cliente and Família
  // accounts are left out.
  public List<Holder> holders() {
    List<Holder> result = new List<Holder>();
    for (Account account : [
      SELECT Id, Name
      FROM Account
      WHERE RecordType.DeveloperName IN :HOLDER_RECORD_TYPES
      WITH USER_MODE
      ORDER BY Name
    ]) {
      Holder holder = new Holder();
      holder.id = account.Id;
      holder.name = account.Name;
      result.add(holder);
    }
    return result;
  }

  public Summary summarize(Id holderId, Date month) {
    Date reference = month == null ? Date.today() : month;
    Summary summary = new Summary();
    summary.monthStart = reference.toStartOfMonth();
    summary.monthEnd = summary.monthStart.addMonths(1).addDays(-1);
    Date today = Date.today();
    Date monthStart = summary.monthStart;
    Date monthEnd = summary.monthEnd;
    // Pending entries already overdue are read whatever the selected month (E7-3), so the query
    // reaches up to the later of the month end and yesterday.
    Date queryEnd = today.addDays(-1) > monthEnd ? today.addDays(-1) : monthEnd;
    Decimal pendingCashNet = 0;
    String holderFilter = holderId == null
      ? ''
      : ' AND AXF_ENT_MD_Holder__c = :holderId';
    Map<String, Object> binds = new Map<String, Object>{
      'holderId' => holderId,
      'monthStart' => monthStart,
      'queryEnd' => queryEnd,
      'pendingStatus' => 'Pending'
    };
    for (
      SObject row : Database.queryWithBinds(
        'SELECT AXF_ENT_PKL_Type__c, AXF_ENT_PKL_Status__c, AXF_ENT_DAT_DueDate__c, ' +
          'AXF_ENT_FOR_AffectsCash__c, convertCurrency(AXF_ENT_CUR_Amount__c) ' +
          'FROM AXF_OBJ_Entry__c WHERE AXF_ENT_DAT_DueDate__c <= :queryEnd ' +
          'AND (AXF_ENT_PKL_Status__c = :pendingStatus OR AXF_ENT_DAT_DueDate__c >= :monthStart)' +
          holderFilter,
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AXF_OBJ_Entry__c entry = (AXF_OBJ_Entry__c) row;
      Boolean expense = entry.AXF_ENT_PKL_Type__c == 'Expense';
      Boolean pending = entry.AXF_ENT_PKL_Status__c == 'Pending';
      Decimal amount = entry.AXF_ENT_CUR_Amount__c == null
        ? 0
        : entry.AXF_ENT_CUR_Amount__c;
      Date due = entry.AXF_ENT_DAT_DueDate__c;
      Boolean inMonth = due >= monthStart && due <= monthEnd;
      if (entry.AXF_ENT_FOR_AffectsCash__c == true) {
        if (inMonth) {
          if (expense) {
            summary.expense += amount;
          } else {
            summary.income += amount;
          }
          if (!pending) {
            if (expense) {
              summary.expenseRealized += amount;
            } else {
              summary.incomeRealized += amount;
            }
          }
        }
        if (pending && (due < today || due <= monthEnd)) {
          pendingCashNet += expense ? -amount : amount;
          if (due < today) {
            summary.overdueCount++;
            if (expense) {
              summary.overdueExpense += amount;
            } else {
              summary.overdueIncome += amount;
            }
          } else {
            summary.dueSoonCount++;
            if (expense) {
              summary.dueSoonExpense += amount;
            } else {
              summary.dueSoonIncome += amount;
            }
          }
        }
      } else if (pending && due <= monthEnd) {
        summary.cardForecast += expense ? amount : -amount;
      }
    }
    for (
      SObject row : Database.queryWithBinds(
        'SELECT convertCurrency(AXF_BA_CUR_Balance__c) FROM AXF_OBJ_BankAccount__c' +
        (holderId == null ? '' : ' WHERE AXF_BA_MD_Holder__c = :holderId'),
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AXF_OBJ_BankAccount__c account = (AXF_OBJ_BankAccount__c) row;
      summary.currentBalance += account.AXF_BA_CUR_Balance__c == null
        ? 0
        : account.AXF_BA_CUR_Balance__c;
    }
    summary.projectedBalance = summary.currentBalance + pendingCashNet;
    summary.projectedBalanceWithCard =
      summary.projectedBalance - summary.cardForecast;
    return summary;
  }

  // Entries of the month list (E7-9). No filter: every entry due in the month. OVERDUE: pending
  // cash entries due before today, any month. DUE_SOON: pending cash entries due from today to the
  // end of the month. Ordered by due date; capped at maxRows.
  public EntryList entries(Id holderId, Date month, String filter) {
    Date monthStart = (month == null ? Date.today() : month).toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    Date today = Date.today();
    Map<String, Object> binds = new Map<String, Object>{
      'holderId' => holderId,
      'monthStart' => monthStart,
      'monthEnd' => monthEnd,
      'today' => today,
      'pendingStatus' => 'Pending'
    };
    if (
      String.isNotBlank(filter) &&
      filter != FILTER_OVERDUE &&
      filter != FILTER_DUE_SOON
    ) {
      throw new IllegalArgumentException('Filtro inválido: ' + filter);
    }
    String clause;
    if (filter == FILTER_OVERDUE) {
      clause =
        'AXF_ENT_PKL_Status__c = :pendingStatus AND AXF_ENT_FOR_AffectsCash__c = TRUE ' +
        'AND AXF_ENT_DAT_DueDate__c < :today';
    } else if (filter == FILTER_DUE_SOON) {
      clause =
        'AXF_ENT_PKL_Status__c = :pendingStatus AND AXF_ENT_FOR_AffectsCash__c = TRUE ' +
        'AND AXF_ENT_DAT_DueDate__c >= :today AND AXF_ENT_DAT_DueDate__c <= :monthEnd';
    } else {
      clause = 'AXF_ENT_DAT_DueDate__c >= :monthStart AND AXF_ENT_DAT_DueDate__c <= :monthEnd';
    }
    EntryList result = new EntryList();
    for (
      SObject row : Database.queryWithBinds(
        'SELECT Name, AXF_ENT_DAT_DueDate__c, AXF_ENT_PKL_Type__c, AXF_ENT_PKL_Status__c, ' +
          'AXF_ENT_FOR_AffectsCash__c, AXF_ENT_LKP_Invoice__c, AXF_ENT_MD_Holder__r.Name, ' +
          'AXF_ENT_LKP_Category__r.Name, convertCurrency(AXF_ENT_CUR_Amount__c) ' +
          'FROM AXF_OBJ_Entry__c WHERE ' +
          clause +
          (holderId == null ? '' : ' AND AXF_ENT_MD_Holder__c = :holderId') +
          ' ORDER BY AXF_ENT_DAT_DueDate__c, Name, Id LIMIT ' +
          (maxRows + 1),
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      if (result.rows.size() == maxRows) {
        result.truncated = true;
        break;
      }
      AXF_OBJ_Entry__c entry = (AXF_OBJ_Entry__c) row;
      EntryRow line = new EntryRow();
      line.id = entry.Id;
      line.name = entry.Name;
      line.dueDate = entry.AXF_ENT_DAT_DueDate__c;
      line.amount = entry.AXF_ENT_CUR_Amount__c;
      line.type = entry.AXF_ENT_PKL_Type__c;
      line.status = entry.AXF_ENT_PKL_Status__c;
      line.holderName = entry.AXF_ENT_MD_Holder__r?.Name;
      line.categoryName = entry.AXF_ENT_LKP_Category__r?.Name;
      line.forecastCard = entry.AXF_ENT_FOR_AffectsCash__c != true;
      line.invoice = entry.AXF_ENT_LKP_Invoice__c != null;
      line.overdue =
        entry.AXF_ENT_PKL_Status__c == 'Pending' &&
        entry.AXF_ENT_FOR_AffectsCash__c == true &&
        entry.AXF_ENT_DAT_DueDate__c < today;
      result.rows.add(line);
    }
    return result;
  }
}
