/**
 * @description Idempotent sync of the bank accounts and credit cards of a PluggyConnection:
 * upserts by Pluggy Id under the connection's holder with the Pluggy record type.
 */
public with sharing class ALT_CLS_PluggyAccountSync {
  public class Result {
    public Boolean success = false;
    public String message;
    public Integer accounts = 0;
    public Integer cards = 0;
  }

  public class Linked {
    public Id id;
    public String kind;
    public String name;
    public String detail;
    public String holder;
  }

  // Record type visibility comes from permission sets, which a test cannot grant.
  @TestVisible
  private static Boolean assignRecordType = true;

  public Result sync(Id connectionId) {
    Result r = new Result();
    List<AXF_OBJ_PluggyConnection__c> found = [
      SELECT
        AXF_CON_MD_Holder__c,
        AXF_CON_PKL_Institution__c,
        AXF_CON_EXI_PluggyItemId__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
    ];
    if (found.isEmpty()) {
      r.message = 'Conexão não encontrada.';
      return r;
    }
    AXF_OBJ_PluggyConnection__c connection = found[0];
    List<Object> items;
    try {
      items = ALT_CLS_PluggyApi.results(
        new ALT_CLS_PluggyApi()
          .get(
            '/accounts?itemId=' +
            EncodingUtil.urlEncode(
              connection.AXF_CON_EXI_PluggyItemId__c,
              'UTF-8'
            )
          )
      );
    } catch (ALT_CLS_PluggyCredential.PluggyException e) {
      r.message = e.getMessage();
      return r;
    }
    List<AXF_OBJ_BankAccount__c> accounts = new List<AXF_OBJ_BankAccount__c>();
    List<AXF_OBJ_CreditCard__c> cards = new List<AXF_OBJ_CreditCard__c>();
    Id accountType = recordTypeId(Schema.SObjectType.AXF_OBJ_BankAccount__c);
    Id cardType = recordTypeId(Schema.SObjectType.AXF_OBJ_CreditCard__c);
    for (Object item : items) {
      Map<String, Object> pluggy = (Map<String, Object>) item;
      if ('CREDIT' == pluggy.get('type')) {
        cards.add(toCard(pluggy, connection, cardType));
      } else {
        accounts.add(toAccount(pluggy, connection, accountType));
      }
    }
    String failure = save(
      Database.upsert(
        accounts,
        AXF_OBJ_BankAccount__c.AXF_BA_EXI_PluggyAccountId__c,
        false
      )
    );
    failure = failure == null
      ? save(
          Database.upsert(
            cards,
            AXF_OBJ_CreditCard__c.AXF_CC_EXI_PluggyCardId__c,
            false
          )
        )
      : failure;
    if (failure != null) {
      r.message = 'Não foi possível salvar as contas e cartões: ' + failure;
      return r;
    }
    update new AXF_OBJ_PluggyConnection__c(
      Id = connection.Id,
      AXF_CON_DT_LastSyncDatetime__c = System.now()
    );
    r.success = true;
    r.accounts = accounts.size();
    r.cards = cards.size();
    r.message = 'Sincronização concluída.';
    return r;
  }

  @TestVisible
  private static Id recordTypeId(Schema.DescribeSObjectResult describe) {
    return assignRecordType
      ? describe.getRecordTypeInfosByDeveloperName()
          .get('AXF_Pluggy')
          .getRecordTypeId()
      : null;
  }

  public List<Linked> linked(Id connectionId) {
    List<Linked> items = new List<Linked>();
    for (AXF_OBJ_BankAccount__c account : [
      SELECT
        Name,
        AXF_BA_TXT_Branch__c,
        AXF_BA_TXT_Number__c,
        AXF_BA_MD_Holder__r.Name
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c = :connectionId
      WITH USER_MODE
      ORDER BY Name
    ]) {
      items.add(
        toLinked(
          account.Id,
          'Conta',
          account.Name,
          dash(account.AXF_BA_TXT_Branch__c) +
            ' / ' +
            dash(account.AXF_BA_TXT_Number__c),
          account.AXF_BA_MD_Holder__r.Name
        )
      );
    }
    for (AXF_OBJ_CreditCard__c card : [
      SELECT Name, AXF_CC_TXT_LastDigits__c, AXF_CC_MD_Holder__r.Name
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Connection__c = :connectionId
      WITH USER_MODE
      ORDER BY Name
    ]) {
      items.add(
        toLinked(
          card.Id,
          'Cartão',
          card.Name,
          'final ' + dash(card.AXF_CC_TXT_LastDigits__c),
          card.AXF_CC_MD_Holder__r.Name
        )
      );
    }
    return items;
  }

  private String dash(String value) {
    return String.isBlank(value) ? '-' : value;
  }

  private Linked toLinked(
    Id id,
    String kind,
    String name,
    String detail,
    String holder
  ) {
    Linked item = new Linked();
    item.id = id;
    item.kind = kind;
    item.name = name;
    item.detail = detail;
    item.holder = holder;
    return item;
  }

  private String save(List<Database.UpsertResult> results) {
    for (Database.UpsertResult result : results) {
      if (!result.isSuccess()) {
        return result.getErrors()[0].getMessage();
      }
    }
    return null;
  }

  private AXF_OBJ_BankAccount__c toAccount(
    Map<String, Object> pluggy,
    AXF_OBJ_PluggyConnection__c connection,
    Id recordTypeId
  ) {
    Map<String, Object> bank = (Map<String, Object>) pluggy.get('bankData');
    String transfer = bank == null ? null : (String) bank.get('transferNumber');
    AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
      Name = (String) pluggy.get('name'),
      AXF_BA_EXI_PluggyAccountId__c = (String) pluggy.get('id'),
      AXF_BA_MD_Holder__c = connection.AXF_CON_MD_Holder__c,
      AXF_BA_LKP_Connection__c = connection.Id,
      AXF_BA_PKL_Institution__c = connection.AXF_CON_PKL_Institution__c,
      AXF_BA_PKL_Type__c = 'SAVINGS_ACCOUNT' == pluggy.get('subtype')
        ? 'Savings'
        : 'Checking',
      AXF_BA_TXT_Branch__c = String.isBlank(transfer)
        ? null
        : transfer.substringBefore('/'),
      AXF_BA_TXT_Number__c = (String) pluggy.get('number'),
      AXF_BA_CUR_Balance__c = toDecimal(pluggy.get('balance')),
      AXF_BA_DT_LastSync__c = System.now()
    );
    setRecordType(account, recordTypeId);
    setCurrency(account, pluggy);
    return account;
  }

  private AXF_OBJ_CreditCard__c toCard(
    Map<String, Object> pluggy,
    AXF_OBJ_PluggyConnection__c connection,
    Id recordTypeId
  ) {
    Map<String, Object> credit = (Map<String, Object>) pluggy.get('creditData');
    if (credit == null) {
      credit = new Map<String, Object>();
    }
    String last = (String) pluggy.get('number');
    Date closing = ALT_CLS_PluggyApi.toDate(credit.get('balanceCloseDate'));
    Date due = ALT_CLS_PluggyApi.toDate(credit.get('balanceDueDate'));
    String brand = (String) credit.get('brand');
    String lastDigits = String.isBlank(last) ? null : last.right(4);
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = cardName(
        connection.AXF_CON_PKL_Institution__c,
        brand,
        lastDigits,
        (String) pluggy.get('name')
      ),
      AXF_CC_EXI_PluggyCardId__c = (String) pluggy.get('id'),
      AXF_CC_MD_Holder__c = connection.AXF_CON_MD_Holder__c,
      AXF_CC_LKP_Connection__c = connection.Id,
      AXF_CC_PKL_Institution__c = connection.AXF_CON_PKL_Institution__c,
      AXF_CC_TXT_Brand__c = brand,
      AXF_CC_TXT_Level__c = (String) credit.get('level'),
      AXF_CC_TXT_LastDigits__c = lastDigits,
      AXF_CC_CUR_Limit__c = toDecimal(credit.get('creditLimit')),
      AXF_CC_CUR_AvailableLimit__c = toDecimal(
        credit.get('availableCreditLimit')
      ),
      AXF_CC_NUM_ClosingDay__c = closing == null ? null : closing.day(),
      AXF_CC_NUM_DueDay__c = due == null ? null : due.day(),
      AXF_CC_DT_LastSync__c = System.now()
    );
    setRecordType(card, recordTypeId);
    setCurrency(card, pluggy);
    return card;
  }

  // "C6 Bank - MASTERCARD (1818)": institution label without its code prefix
  private String cardName(
    String code,
    String brand,
    String lastDigits,
    String fallback
  ) {
    String label = null;
    for (
      Schema.PicklistEntry entry : AXF_OBJ_CreditCard__c.AXF_CC_PKL_Institution__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.getValue() == code) {
        label = entry.getLabel();
      }
    }
    String prefix = code + ' - ';
    String bank = label != null && label.startsWith(prefix)
      ? label.substring(prefix.length())
      : label;
    if (String.isBlank(bank) || (String.isBlank(brand) && String.isBlank(lastDigits))) {
      return fallback;
    }
    String name = bank;
    if (!String.isBlank(brand)) {
      name += ' - ' + brand;
    }
    if (!String.isBlank(lastDigits)) {
      name += ' (' + lastDigits + ')';
    }
    return name.left(80);
  }

  private void setRecordType(SObject record, Id recordTypeId) {
    if (recordTypeId != null) {
      record.put('RecordTypeId', recordTypeId);
    }
  }

  private void setCurrency(SObject record, Map<String, Object> pluggy) {
    if (
      UserInfo.isMultiCurrencyOrganization() &&
      pluggy.get('currencyCode') != null
    ) {
      record.put('CurrencyIsoCode', pluggy.get('currencyCode'));
    }
  }

  private Decimal toDecimal(Object value) {
    return value == null ? null : Decimal.valueOf(String.valueOf(value));
  }
}
