/**
 * @description Idempotent sync of the invoices (Pluggy bills) and transactions of a Pluggy credit
 * card: upserts by Pluggy Id, links each transaction to its invoice by the bill id and stores the
 * signed amount in the original currency plus the converted amount Pluggy reports
 * (amountInAccountCurrency) as the BRL amount. Same window rule as the account transactions.
 */
public with sharing class ALT_CLS_PluggyCardSync {
  public class Result {
    public Boolean success = false;
    public String message;
    public Integer invoices = 0;
    public Integer transactions = 0;
  }

  private static final Integer INITIAL_DAYS = 90;
  private static final Integer OVERLAP_DAYS = 3;
  private static final Integer MAX_BILL_PAGES = 20;

  public Result sync(Id creditCardId) {
    Result r = new Result();
    List<AXF_OBJ_CreditCard__c> found = [
      SELECT AXF_CC_EXI_PluggyCardId__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :creditCardId
    ];
    if (
      found.isEmpty() || String.isBlank(found[0].AXF_CC_EXI_PluggyCardId__c)
    ) {
      r.message = 'Cartão sem Id do Pluggy: transações de cartão manual entram por importação.';
      return r;
    }
    String pluggyId = EncodingUtil.urlEncode(
      found[0].AXF_CC_EXI_PluggyCardId__c,
      'UTF-8'
    );
    ALT_CLS_PluggyApi api = new ALT_CLS_PluggyApi();
    List<Object> bills;
    List<Object> items;
    try {
      bills = bills(api, pluggyId);
      items = api.getAll(
        '/v2/transactions?accountId=' +
          pluggyId +
          '&dateFrom=' +
          String.valueOf(startDate(creditCardId))
      );
    } catch (ALT_CLS_PluggyCredential.PluggyException e) {
      r.message = e.getMessage();
      return r;
    }
    Map<String, AXF_OBJ_CreditCardInvoice__c> invoices = new Map<String, AXF_OBJ_CreditCardInvoice__c>();
    for (Object bill : bills) {
      AXF_OBJ_CreditCardInvoice__c invoice = toInvoice(
        (Map<String, Object>) bill,
        creditCardId
      );
      invoices.put(invoice.AXF_CCI_EXI_PluggyInvoiceId__c, invoice);
    }
    Map<String, AXF_OBJ_CreditCardTransaction__c> transactions = new Map<String, AXF_OBJ_CreditCardTransaction__c>();
    for (Object item : items) {
      AXF_OBJ_CreditCardTransaction__c cardTransaction = toTransaction(
        (Map<String, Object>) item,
        creditCardId,
        invoices.keySet()
      );
      transactions.put(
        cardTransaction.AXF_CCT_EXI_PluggyTransactionId__c,
        cardTransaction
      );
    }
    String failure = firstFailure(
      Database.upsert(
        invoices.values(),
        AXF_OBJ_CreditCardInvoice__c.AXF_CCI_EXI_PluggyInvoiceId__c,
        false
      )
    );
    failure = failure == null
      ? firstFailure(
          Database.upsert(
            transactions.values(),
            AXF_OBJ_CreditCardTransaction__c.AXF_CCT_EXI_PluggyTransactionId__c,
            false
          )
        )
      : failure;
    if (failure != null) {
      r.message = 'Não foi possível salvar faturas e transações: ' + failure;
      return r;
    }
    r.success = true;
    r.invoices = invoices.size();
    r.transactions = transactions.size();
    r.message = 'Sincronização concluída.';
    return r;
  }

  // /bills is page-paginated ({total, totalPages, page, results}), unlike /v2/transactions.
  private List<Object> bills(ALT_CLS_PluggyApi api, String pluggyId) {
    List<Object> all = new List<Object>();
    Integer totalPages = 1;
    for (
      Integer page = 1; page <= totalPages && page <= MAX_BILL_PAGES; page++
    ) {
      Map<String, Object> body = api.get(
        '/bills?accountId=' + pluggyId + '&page=' + page
      );
      all.addAll(ALT_CLS_PluggyApi.results(body));
      if (body.get('totalPages') != null) {
        totalPages = Integer.valueOf(body.get('totalPages'));
      }
    }
    return all;
  }

  private Date startDate(Id creditCardId) {
    AggregateResult latest = [
      SELECT MAX(AXF_CCT_DAT_Date__c) lastDate
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE AXF_CCT_MD_CreditCard__c = :creditCardId
    ];
    Date lastDate = (Date) latest.get('lastDate');
    return lastDate == null
      ? Date.today().addDays(-INITIAL_DAYS)
      : lastDate.addDays(-OVERLAP_DAYS);
  }

  private String firstFailure(List<Database.UpsertResult> results) {
    for (Database.UpsertResult result : results) {
      if (!result.isSuccess()) {
        return result.getErrors()[0].getMessage();
      }
    }
    return null;
  }

  // Pluggy has no explicit invoice status: past due date counts as closed. Paid is not
  // reported by the bills endpoint.
  private AXF_OBJ_CreditCardInvoice__c toInvoice(
    Map<String, Object> pluggy,
    Id creditCardId
  ) {
    Date due = ALT_CLS_PluggyApi.toDate(pluggy.get('dueDate'));
    return new AXF_OBJ_CreditCardInvoice__c(
      AXF_CCI_MD_CreditCard__c = creditCardId,
      AXF_CCI_EXI_PluggyInvoiceId__c = (String) pluggy.get('id'),
      AXF_CCI_TXT_Period__c = String.valueOf(due).substring(0, 7),
      AXF_CCI_DAT_DueDate__c = due,
      AXF_CCI_CUR_TotalAmount__c = Decimal.valueOf(
        String.valueOf(pluggy.get('totalAmount'))
      ),
      AXF_CCI_PKL_Status__c = due < Date.today() ? 'Closed' : 'Open'
    );
  }

  private AXF_OBJ_CreditCardTransaction__c toTransaction(
    Map<String, Object> pluggy,
    Id creditCardId,
    Set<String> syncedBillIds
  ) {
    Boolean debit = 'DEBIT' == pluggy.get('type');
    Map<String, Object> metadata = (Map<String, Object>) pluggy.get(
      'creditCardMetadata'
    );
    String billId = metadata == null ? null : (String) metadata.get('billId');
    String raw = (String) pluggy.get('descriptionRaw');
    AXF_OBJ_CreditCardTransaction__c cardTransaction = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MD_CreditCard__c = creditCardId,
      AXF_CCT_EXI_PluggyTransactionId__c = (String) pluggy.get('id'),
      AXF_CCT_DAT_Date__c = ALT_CLS_PluggyApi.toDate(pluggy.get('date')),
      AXF_CCT_TXT_Description__c = String.isBlank(raw)
        ? (String) pluggy.get('description')
        : raw,
      AXF_CCT_CUR_Amount__c = signed(pluggy.get('amount'), debit),
      AXF_CCT_CUR_AmountBRL__c = pluggy.get('amountInAccountCurrency') == null
        ? null
        : signed(pluggy.get('amountInAccountCurrency'), debit),
      AXF_CCT_TXT_CurrencyCode__c = (String) pluggy.get('currencyCode'),
      AXF_CCT_TXT_PluggyCategory__c = (String) pluggy.get('category')
    );
    if (metadata != null && metadata.get('installmentNumber') != null) {
      cardTransaction.AXF_CCT_TXT_Installment__c =
        String.valueOf(metadata.get('installmentNumber')) +
        '/' +
        String.valueOf(metadata.get('totalInstallments'));
    }
    if (billId != null && syncedBillIds.contains(billId)) {
      cardTransaction.AXF_CCT_LKP_Invoice__r = new AXF_OBJ_CreditCardInvoice__c(
        AXF_CCI_EXI_PluggyInvoiceId__c = billId
      );
    }
    return cardTransaction;
  }

  private Decimal signed(Object value, Boolean debit) {
    Decimal amount = Decimal.valueOf(String.valueOf(value)).abs();
    return debit ? -amount : amount;
  }
}
