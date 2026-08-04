/**
 * @description Query service for recent financial-account options used by quick flow actions.
 */
public with sharing class ALT_CLS_FinancialAccountLookup {
  public class OptionResult {
    public String id;
    public String displayLabel;

    public OptionResult(Id recordId, String recordName) {
      id = recordId;
      displayLabel = recordName;
    }
  }

  public List<OptionResult> getBankAccounts(Id accountId) {
    List<OptionResult> results = new List<OptionResult>();
    for (AXF_OBJ_BankAccount__c record : [
      SELECT Id, Name
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Account__c = :accountId
      WITH USER_MODE
      ORDER BY LastReferencedDate DESC NULLS LAST, LastModifiedDate DESC
      LIMIT 25
    ]) {
      results.add(new OptionResult(record.Id, record.Name));
    }
    return results;
  }

  public List<OptionResult> getCreditCards(Id accountId) {
    List<OptionResult> results = new List<OptionResult>();
    for (AXF_OBJ_CreditCard__c record : [
      SELECT Id, Name
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Account__c = :accountId
      WITH USER_MODE
      ORDER BY LastReferencedDate DESC NULLS LAST, LastModifiedDate DESC
      LIMIT 25
    ]) {
      results.add(new OptionResult(record.Id, record.Name));
    }
    return results;
  }
}
