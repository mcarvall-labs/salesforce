/**
 * @description Budget (goals) view of the Axon dashboard: expenses of the selected month by
 * category against the monthly goal. Only expenses that affect cash count (a card purchase that is
 * not yet in an invoice is shown apart, as the forecast card line). Realized = Realized entries,
 * planned = every entry of the month (realized + pending).
 *
 * Goal of a category = the Budget with the latest start month up to the selected month that has
 * not ended (end month empty or not before it); a Budget without category is the total goal. For a
 * holder it is that holder's goal. For "all holders" a goal of the Família account wins; without
 * it, the goals of the holders are summed.
 */
public with sharing class ALT_CLS_DashboardBudget {
  public class Row {
    @AuraEnabled
    public Id categoryId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Decimal realized = 0;
    @AuraEnabled
    public Decimal planned = 0;
    @AuraEnabled
    public Decimal goal;
  }

  public class View {
    @AuraEnabled
    public Row total = new Row();
    @AuraEnabled
    public List<Row> rows = new List<Row>();
    @AuraEnabled
    public Decimal cardForecast = 0;
  }

  private static final String FAMILY = 'AXF_Family';
  private static final String NO_CATEGORY = 'none';

  public View build(Id holderId, Date month) {
    Date monthStart = (month == null ? Date.today() : month).toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    View view = new View();
    view.total.name = 'Total de despesas';
    Map<String, Row> byCategory = new Map<String, Row>();
    String holderFilter = holderId == null
      ? ''
      : ' AND AXF_ENT_MD_Holder__c = :holderId';
    Map<String, Object> binds = new Map<String, Object>{
      'holderId' => holderId,
      'monthStart' => monthStart,
      'monthEnd' => monthEnd,
      'expense' => 'Expense'
    };
    for (
      SObject row : Database.queryWithBinds(
        'SELECT AXF_ENT_LKP_Category__c, AXF_ENT_PKL_Status__c, ' +
          'AXF_ENT_FOR_AffectsCash__c, convertCurrency(AXF_ENT_CUR_Amount__c) ' +
          'FROM AXF_OBJ_Entry__c WHERE AXF_ENT_PKL_Type__c = :expense ' +
          'AND AXF_ENT_DAT_DueDate__c >= :monthStart AND AXF_ENT_DAT_DueDate__c <= :monthEnd' +
          holderFilter,
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AXF_OBJ_Entry__c entry = (AXF_OBJ_Entry__c) row;
      Decimal amount = entry.AXF_ENT_CUR_Amount__c == null
        ? 0
        : entry.AXF_ENT_CUR_Amount__c;
      Boolean pending = entry.AXF_ENT_PKL_Status__c == 'Pending';
      if (entry.AXF_ENT_FOR_AffectsCash__c != true) {
        if (pending) {
          view.cardForecast += amount;
        }
        continue;
      }
      String key = keyOf(entry.AXF_ENT_LKP_Category__c);
      Row line = byCategory.get(key);
      if (line == null) {
        line = new Row();
        line.categoryId = entry.AXF_ENT_LKP_Category__c;
        byCategory.put(key, line);
      }
      line.planned += amount;
      view.total.planned += amount;
      if (!pending) {
        line.realized += amount;
        view.total.realized += amount;
      }
    }
    applyGoals(view, byCategory, holderId, monthStart);
    nameCategories(byCategory);
    view.rows = byCategory.values();
    view.rows.sort(new ByPlannedDescending());
    return view;
  }

  private static String keyOf(Id categoryId) {
    return categoryId == null ? NO_CATEGORY : String.valueOf(categoryId);
  }

  private void applyGoals(
    View view,
    Map<String, Row> byCategory,
    Id holderId,
    Date monthStart
  ) {
    // Latest start month first, so the first goal found per holder and category is the current one.
    Map<String, Object> binds = new Map<String, Object>{
      'holderId' => holderId,
      'monthStart' => monthStart
    };
    Set<String> seen = new Set<String>();
    Map<String, Decimal> familyGoals = new Map<String, Decimal>();
    Map<String, Decimal> holderGoals = new Map<String, Decimal>();
    for (
      SObject row : Database.queryWithBinds(
        'SELECT AXF_BDG_MD_Holder__c, AXF_BDG_LKP_Category__c, ' +
          'AXF_BDG_MD_Holder__r.RecordType.DeveloperName, ' +
          'convertCurrency(AXF_BDG_CUR_Amount__c) FROM AXF_OBJ_Budget__c ' +
          'WHERE AXF_BDG_DAT_StartMonth__c <= :monthStart ' +
          'AND (AXF_BDG_DAT_EndMonth__c = NULL OR AXF_BDG_DAT_EndMonth__c >= :monthStart)' +
          (holderId == null ? '' : ' AND AXF_BDG_MD_Holder__c = :holderId') +
          ' ORDER BY AXF_BDG_DAT_StartMonth__c DESC, CreatedDate DESC',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AXF_OBJ_Budget__c budget = (AXF_OBJ_Budget__c) row;
      String key = keyOf(budget.AXF_BDG_LKP_Category__c);
      if (!seen.add(budget.AXF_BDG_MD_Holder__c + '|' + key)) {
        continue;
      }
      Decimal amount = budget.AXF_BDG_CUR_Amount__c == null
        ? 0
        : budget.AXF_BDG_CUR_Amount__c;
      Boolean family =
        budget.AXF_BDG_MD_Holder__r.RecordType.DeveloperName == FAMILY;
      Map<String, Decimal> target = family ? familyGoals : holderGoals;
      target.put(key, (target.containsKey(key) ? target.get(key) : 0) + amount);
    }
    Map<String, Decimal> goals = holderGoals.clone();
    goals.putAll(familyGoals);
    view.total.goal = goals.get(NO_CATEGORY);
    for (String key : goals.keySet()) {
      if (key == NO_CATEGORY) {
        continue;
      }
      Row line = byCategory.get(key);
      if (line == null) {
        line = new Row();
        line.categoryId = key;
        byCategory.put(key, line);
      }
      line.goal = goals.get(key);
    }
  }

  private void nameCategories(Map<String, Row> byCategory) {
    Set<Id> ids = new Set<Id>();
    for (Row line : byCategory.values()) {
      if (line.categoryId != null) {
        ids.add(line.categoryId);
      }
    }
    Map<Id, AXF_OBJ_Category__c> categories = new Map<Id, AXF_OBJ_Category__c>(
      [
        SELECT Name
        FROM AXF_OBJ_Category__c
        WHERE Id IN :ids
        WITH USER_MODE
      ]
    );
    for (Row line : byCategory.values()) {
      line.name = line.categoryId == null
        ? 'Sem categoria'
        : (categories.containsKey(line.categoryId)
            ? categories.get(line.categoryId).Name
            : 'Categoria');
    }
  }

  private class ByPlannedDescending implements System.Comparator<Row> {
    public Integer compare(Row first, Row second) {
      if (first.planned == second.planned) {
        return 0;
      }
      return first.planned > second.planned ? -1 : 1;
    }
  }
}
