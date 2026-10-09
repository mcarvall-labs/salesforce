/**
 * @description Idempotent sync of the invoices (Pluggy bills) and transactions of a Pluggy credit
 * card: upserts by Pluggy Id, links each transaction to its invoice by the bill id and stores the
 * signed amount in the original currency plus the converted amount Pluggy reports
 * (amountInAccountCurrency) as the BRL amount. Same window rule as the account transactions.
 * Each invoice also keeps one expense Entry (Lançamento) in BRL, created and refreshed (due date
 * and total) while it is Pending, so the dashboard shows the card as a single expense (E6-3); a
 * Realized one (paid and reconciled) is left alone.
 */
public with sharing class ALT_CLS_PluggyCardSync {
  public class Result {
    public Boolean success = false;
    public String message;
    public Integer invoices = 0;
    public Integer transactions = 0;
    public Integer skipped = 0;
    public Integer withoutInvoice = 0;
    public Integer invoiceEntries = 0;
  }

  private static final Integer INITIAL_DAYS = 90;
  private static final Integer OVERLAP_DAYS = 3;
  @TestVisible
  private static Integer maxBillPages = 20;

  public Result sync(Id creditCardId) {
    return sync(creditCardId, null, null);
  }

  // Manual window (fromDate/toDate, both inclusive) for the transactions; invoices are always
  // re-read in full. Idempotent by Pluggy Id.
  public Result sync(Id creditCardId, Date fromDate, Date toDate) {
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
          String.valueOf(
            fromDate == null ? startDate(creditCardId) : fromDate
          ) +
          (toDate == null ? '' : '&dateTo=' + String.valueOf(toDate))
      );
    } catch (ALT_CLS_PluggyCredential.PluggyException e) {
      r.message = e.getMessage();
      return r;
    }
    Map<String, String> existingStatus = new Map<String, String>();
    for (AXF_OBJ_CreditCardInvoice__c existing : [
      SELECT AXF_CCI_EXI_PluggyInvoiceId__c, AXF_CCI_PKL_Status__c
      FROM AXF_OBJ_CreditCardInvoice__c
      WHERE AXF_CCI_MD_CreditCard__c = :creditCardId
    ]) {
      existingStatus.put(
        existing.AXF_CCI_EXI_PluggyInvoiceId__c,
        existing.AXF_CCI_PKL_Status__c
      );
    }
    Map<String, AXF_OBJ_CreditCardInvoice__c> invoices = new Map<String, AXF_OBJ_CreditCardInvoice__c>();
    for (Object bill : bills) {
      Map<String, Object> pluggyBill = (Map<String, Object>) bill;
      if (pluggyBill.get('id') == null || pluggyBill.get('dueDate') == null) {
        r.skipped++;
        continue;
      }
      AXF_OBJ_CreditCardInvoice__c invoice = toInvoice(
        pluggyBill,
        creditCardId
      );
      if (
        'Paid' == existingStatus.get(invoice.AXF_CCI_EXI_PluggyInvoiceId__c)
      ) {
        invoice.AXF_CCI_PKL_Status__c = 'Paid';
      }
      invoices.put(invoice.AXF_CCI_EXI_PluggyInvoiceId__c, invoice);
    }
    Set<String> knownInvoices = new Set<String>(existingStatus.keySet());
    knownInvoices.addAll(invoices.keySet());
    Map<String, AXF_OBJ_CreditCardTransaction__c> transactions = new Map<String, AXF_OBJ_CreditCardTransaction__c>();
    for (Object item : items) {
      Map<String, Object> pluggy = (Map<String, Object>) item;
      if (
        pluggy.get('id') == null ||
        pluggy.get('date') == null ||
        pluggy.get('amount') == null
      ) {
        r.skipped++;
        continue;
      }
      AXF_OBJ_CreditCardTransaction__c cardTransaction = toTransaction(
        pluggy,
        creditCardId,
        knownInvoices
      );
      if (cardTransaction.AXF_CCT_LKP_Invoice__r == null) {
        r.withoutInvoice++;
      }
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
    try {
      r.invoiceEntries = syncInvoiceEntries(creditCardId, invoices.keySet());
    } catch (DmlException e) {
      r.message =
        'Não foi possível salvar o lançamento da fatura: ' + e.getMessage();
      return r;
    }
    r.success = true;
    r.invoices = invoices.size();
    r.transactions = transactions.size();
    r.message = 'Sincronização concluída.';
    if (r.skipped > 0) {
      r.message +=
        ' ' +
        r.skipped +
        ' itens sem id, data ou valor foram ignorados.';
    }
    if (r.withoutInvoice > 0) {
      r.message += ' ' + r.withoutInvoice + ' transações ficaram sem fatura.';
    }
    return r;
  }

  // One Pending expense Entry per invoice, in BRL (the invoice total is always BRL). Existing
  // Pending ones follow the invoice due date and total; Realized ones are never touched.
  private Integer syncInvoiceEntries(
    Id creditCardId,
    Set<String> pluggyInvoiceIds
  ) {
    if (pluggyInvoiceIds.isEmpty()) {
      return 0;
    }
    AXF_OBJ_CreditCard__c card = [
      SELECT Name, AXF_CC_MD_Holder__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :creditCardId
    ];
    List<AXF_OBJ_CreditCardInvoice__c> savedInvoices = [
      SELECT
        AXF_CCI_TXT_Period__c,
        AXF_CCI_DAT_DueDate__c,
        AXF_CCI_CUR_TotalAmount__c
      FROM AXF_OBJ_CreditCardInvoice__c
      WHERE
        AXF_CCI_MD_CreditCard__c = :creditCardId
        AND AXF_CCI_EXI_PluggyInvoiceId__c IN :pluggyInvoiceIds
    ];
    Set<Id> invoiceIds = new Set<Id>();
    for (AXF_OBJ_CreditCardInvoice__c saved : savedInvoices) {
      invoiceIds.add(saved.Id);
    }
    Map<Id, AXF_OBJ_Entry__c> entryByInvoice = new Map<Id, AXF_OBJ_Entry__c>();
    List<AXF_OBJ_Entry__c> existingEntries = [
      SELECT
        AXF_ENT_PKL_Status__c,
        AXF_ENT_LKP_Invoice__c,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Invoice__c IN :invoiceIds
    ];
    for (AXF_OBJ_Entry__c entry : existingEntries) {
      AXF_OBJ_Entry__c kept = entryByInvoice.get(entry.AXF_ENT_LKP_Invoice__c);
      if (kept == null || kept.AXF_ENT_PKL_Status__c == 'Pending') {
        entryByInvoice.put(entry.AXF_ENT_LKP_Invoice__c, entry);
      }
    }
    List<AXF_OBJ_Entry__c> toInsert = new List<AXF_OBJ_Entry__c>();
    List<AXF_OBJ_Entry__c> toUpdate = new List<AXF_OBJ_Entry__c>();
    for (AXF_OBJ_CreditCardInvoice__c invoice : savedInvoices) {
      Decimal total = invoice.AXF_CCI_CUR_TotalAmount__c;
      if (
        total == null ||
        total <= 0 ||
        invoice.AXF_CCI_DAT_DueDate__c == null
      ) {
        continue;
      }
      AXF_OBJ_Entry__c existing = entryByInvoice.get(invoice.Id);
      if (existing == null) {
        toInsert.add(
          new AXF_OBJ_Entry__c(
            Name = ('Fatura ' +
              card.Name +
              ' ' +
              invoice.AXF_CCI_TXT_Period__c)
              .abbreviate(80),
            AXF_ENT_MD_Holder__c = card.AXF_CC_MD_Holder__c,
            AXF_ENT_PKL_Type__c = 'Expense',
            AXF_ENT_PKL_Status__c = 'Pending',
            CurrencyIsoCode = 'BRL',
            AXF_ENT_CUR_Amount__c = total,
            AXF_ENT_DAT_DueDate__c = invoice.AXF_CCI_DAT_DueDate__c,
            AXF_ENT_LKP_CreditCard__c = creditCardId,
            AXF_ENT_LKP_Invoice__c = invoice.Id
          )
        );
      } else if (
        existing.AXF_ENT_PKL_Status__c == 'Pending' &&
        (existing.AXF_ENT_CUR_Amount__c != total ||
        existing.AXF_ENT_DAT_DueDate__c != invoice.AXF_CCI_DAT_DueDate__c)
      ) {
        toUpdate.add(
          new AXF_OBJ_Entry__c(
            Id = existing.Id,
            AXF_ENT_CUR_Amount__c = total,
            AXF_ENT_DAT_DueDate__c = invoice.AXF_CCI_DAT_DueDate__c
          )
        );
      }
    }
    String failure = firstEntryFailure(Database.insert(toInsert, false));
    String updateFailure = firstEntryFailure(Database.update(toUpdate, false));
    failure = failure == null ? updateFailure : failure;
    if (failure != null) {
      throw new DmlException(failure);
    }
    return toInsert.size() + toUpdate.size();
  }

  private String firstEntryFailure(List<Database.SaveResult> results) {
    for (Database.SaveResult result : results) {
      if (!result.isSuccess()) {
        return result.getErrors()[0].getMessage();
      }
    }
    return null;
  }

  // /bills is page-paginated ({total, totalPages, page, results}), unlike /v2/transactions.
  private List<Object> bills(ALT_CLS_PluggyApi api, String pluggyId) {
    List<Object> all = new List<Object>();
    Integer totalPages = 1;
    for (Integer page = 1; page <= totalPages; page++) {
      if (page > maxBillPages) {
        throw new ALT_CLS_PluggyCredential.PluggyException(
          'O Pluggy retornou mais de ' +
            maxBillPages +
            ' páginas de faturas; nada foi gravado.'
        );
      }
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
      AXF_CCI_CUR_TotalAmount__c = pluggy.get('totalAmount') == null
        ? null
        : Decimal.valueOf(String.valueOf(pluggy.get('totalAmount'))),
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
      cardTransaction.AXF_CCT_TXT_Installment__c = String.valueOf(
        metadata.get('installmentNumber')
      );
      if (metadata.get('totalInstallments') != null) {
        cardTransaction.AXF_CCT_TXT_Installment__c +=
          '/' + String.valueOf(metadata.get('totalInstallments'));
      }
    }
    if (
      cardTransaction.AXF_CCT_CUR_AmountBRL__c == null &&
      'BRL' == pluggy.get('currencyCode')
    ) {
      cardTransaction.AXF_CCT_CUR_AmountBRL__c = cardTransaction.AXF_CCT_CUR_Amount__c;
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
