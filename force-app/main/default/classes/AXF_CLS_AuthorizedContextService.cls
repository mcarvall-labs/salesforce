/**
 * Lists Account holder contexts that are visible to the running user. AXF-3.
 * Account sharing is the authority: this service creates no parallel grant model.
 */
public with sharing class AXF_CLS_AuthorizedContextService {
  private static final Set<String> HOLDER_RECORD_TYPES = new Set<String>{
    'AXF_Person',
    'AXF_Business'
  };

  @TestVisible
  private static List<Account> contextsOverride;
  @TestVisible
  private static String currencyOverride;
  @TestVisible
  private static Boolean simulateSecurityFailure;

  /** Read-only context exposed to the context bar. */
  public class ContextView {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String contextType;
    @AuraEnabled
    public String presentationCurrency;
  }

  /**
   * Returns only Person and Business Accounts visible through effective sharing and FLS.
   * @return authorized contexts sorted by display name
   */
  public static List<ContextView> listAuthorizedContexts() {
    if (simulateSecurityFailure == true) {
      throw new SecurityException('test-only denied detail');
    }
    List<Account> rows = contextsOverride;
    if (rows == null) {
      rows = [
        SELECT Id, Name, IsPersonAccount, RecordType.DeveloperName
        FROM Account
        WHERE RecordType.DeveloperName IN :HOLDER_RECORD_TYPES
        WITH USER_MODE
        ORDER BY Name, Id
        LIMIT 200
      ];
    }

    String displayCurrency = currencyOverride;
    if (displayCurrency == null) {
      displayCurrency = new AXF_CLS_ReportCurrencyService()
        .effectivePreference();
    }

    List<ContextView> result = new List<ContextView>();
    for (Account row : rows) {
      if (!HOLDER_RECORD_TYPES.contains(row.RecordType?.DeveloperName)) {
        continue;
      }
      ContextView view = new ContextView();
      view.accountId = row.Id;
      view.label = row.Name;
      view.contextType = row.IsPersonAccount ? 'PERSON' : 'BUSINESS';
      view.presentationCurrency = displayCurrency;
      result.add(view);
    }
    return result;
  }
}
