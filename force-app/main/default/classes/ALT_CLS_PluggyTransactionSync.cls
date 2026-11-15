/**
 * @description Idempotent sync of the transactions of a Pluggy bank account: upserts by Pluggy
 * Transaction Id with a signed amount (debit negative, credit positive). The window starts at
 * the last stored transaction date minus a few days (pending items can still change), or 90
 * days back on the first run.
 */
public with sharing class ALT_CLS_PluggyTransactionSync {
  public class Result {
    public Boolean success = false;
    public String message;
    public Integer transactions = 0;
    public Integer skipped = 0;
  }

  private static final Integer INITIAL_DAYS = 90;
  private static final Integer OVERLAP_DAYS = 3;

  public Result sync(Id bankAccountId) {
    return sync(bankAccountId, null, null);
  }

  // Manual window (fromDate/toDate, both inclusive): re-reads the period regardless of what is
  // already stored. The upsert by Pluggy Transaction Id keeps it idempotent.
  public Result sync(Id bankAccountId, Date fromDate, Date toDate) {
    Result r = new Result();
    List<AXF_OBJ_BankAccount__c> found = [
      SELECT AXF_BA_EXI_PluggyAccountId__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :bankAccountId
    ];
    if (
      found.isEmpty() || String.isBlank(found[0].AXF_BA_EXI_PluggyAccountId__c)
    ) {
      r.message = 'Conta sem Id do Pluggy: transações de conta manual entram por importação.';
      return r;
    }
    List<Object> items;
    try {
      items = new ALT_CLS_PluggyApi()
        .getAll(
          '/v2/transactions?accountId=' +
            EncodingUtil.urlEncode(
              found[0].AXF_BA_EXI_PluggyAccountId__c,
              'UTF-8'
            ) +
            '&dateFrom=' +
            String.valueOf(
              fromDate == null ? startDate(bankAccountId) : fromDate
            ) +
            (toDate == null ? '' : '&dateTo=' + String.valueOf(toDate))
        );
    } catch (ALT_CLS_PluggyCredential.PluggyException e) {
      r.message = e.getMessage();
      return r;
    }
    Map<String, AXF_OBJ_BankAccountTransaction__c> byPluggyId = new Map<String, AXF_OBJ_BankAccountTransaction__c>();
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
      AXF_OBJ_BankAccountTransaction__c bankTransaction = toTransaction(
        pluggy,
        bankAccountId
      );
      byPluggyId.put(
        bankTransaction.AXF_BAT_EXI_PluggyTransactionId__c,
        bankTransaction
      );
    }
    for (
      Database.UpsertResult result : Database.upsert(
        byPluggyId.values(),
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_EXI_PluggyTransactionId__c,
        false
      )
    ) {
      if (!result.isSuccess()) {
        r.message =
          'Não foi possível salvar as transações: ' +
          result.getErrors()[0].getMessage();
        return r;
      }
    }
    r.success = true;
    r.transactions = byPluggyId.size();
    r.message = r.skipped == 0
      ? 'Sincronização concluída.'
      : 'Sincronização concluída; ' +
        r.skipped +
        ' transações sem id, data ou valor foram ignoradas.';
    return r;
  }

  private Date startDate(Id bankAccountId) {
    AggregateResult latest = [
      SELECT MAX(AXF_BAT_DAT_Date__c) lastDate
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE AXF_BAT_MD_BankAccount__c = :bankAccountId
    ];
    Date lastDate = (Date) latest.get('lastDate');
    return lastDate == null
      ? Date.today().addDays(-INITIAL_DAYS)
      : lastDate.addDays(-OVERLAP_DAYS);
  }

  private AXF_OBJ_BankAccountTransaction__c toTransaction(
    Map<String, Object> pluggy,
    Id bankAccountId
  ) {
    Decimal rawAmount = Decimal.valueOf(String.valueOf(pluggy.get('amount')));
    String type = (String) pluggy.get('type');
    String raw = (String) pluggy.get('descriptionRaw');
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MD_BankAccount__c = bankAccountId,
      AXF_BAT_EXI_PluggyTransactionId__c = (String) pluggy.get('id'),
      AXF_BAT_DAT_Date__c = ALT_CLS_PluggyApi.toDate(pluggy.get('date')),
      AXF_BAT_TXT_Description__c = String.isBlank(raw)
        ? (String) pluggy.get('description')
        : raw,
      AXF_BAT_CUR_Amount__c = 'DEBIT' == type
        ? -rawAmount.abs()
        : ('CREDIT' == type ? rawAmount.abs() : rawAmount),
      AXF_BAT_TXT_PluggyCategory__c = (String) pluggy.get('category')
    );
  }
}
