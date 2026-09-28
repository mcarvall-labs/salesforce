/**
 * @description Business service layer for Account "titular" lookup options, used by the
 * quick-entry Account picker. Consumed by AXF_CLS_CTRL_AccountLookup. Contains no @AuraEnabled
 * members and no LWC-specific concepts, per PROJECT_RULES.md §3.
 */
public inherited sharing class ALT_CLS_AccountLookup {
  public class OptionResult {
    public String id;
    public String displayLabel;
  }

  /**
   * Returns Account "titular" options for the quick-entry Account lookup, ordered by Name, so
   * the picker can show a full candidate list on focus instead of relying on the running
   * user's Recently Viewed list (which is often empty for Account, since this app's day-to-day
   * navigation centers on BankAccount/CreditCard, not Account).
   */
  public List<OptionResult> getAccountOptions() {
    List<Account> accounts = [
      SELECT Id, Name
      FROM Account
      WITH USER_MODE
      ORDER BY Name ASC
    ];

    List<OptionResult> options = new List<OptionResult>();
    for (Account acc : accounts) {
      OptionResult opt = new OptionResult();
      opt.id = acc.Id;
      opt.displayLabel = acc.Name;
      options.add(opt);
    }
    return options;
  }
}
