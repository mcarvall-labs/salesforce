public with sharing class AXF_CLS_PluggyTxSync_Service {

    // A API legada '/transactions' (paginação por page) foi descontinuada pela Pluggy (HTTP 410).
    // A API atual '/v2/transactions' exige accountId obrigatoriamente e usa paginação por cursor.
    private static final String TRANSACTIONS_ENDPOINT_V2 = 'callout:AXF_NC_Pluggy_API/v2/transactions?accountId=';

    // Keeps a safety buffer below Salesforce's 100-callouts-per-transaction governor limit so the
    // pagination loop can always upsert what it has and reschedule a resume instead of throwing
    // a System.LimitException mid-pagination (which would silently discard the whole batch).
    private static final Integer CALLOUT_SAFETY_MARGIN = 3;

    // Short, fixed delay used when pagination is paused proactively due to the callout governor
    // limit (as opposed to a Pluggy HTTP 429, which carries its own Retry-After).
    private static final Integer GOVERNOR_LIMIT_RETRY_SECONDS = 10;

    public class TransactionSyncResult {
        public List<AXF_OBJ_BankAccountTransaction__c> bankAccountTransactions = new List<AXF_OBJ_BankAccountTransaction__c>();
        public List<AXF_OBJ_CreditCardTransaction__c> creditCardTransactions = new List<AXF_OBJ_CreditCardTransaction__c>();
    }

    /**
     * @description Thrown when the Pluggy API returns HTTP 429 (rate limit) while paginating /v2/transactions.
     * Carries the cursor of the page that was being requested so the caller can resume from the same point.
     */
    public class RateLimitException extends Exception {
        public String resumeCursor;
        public Integer retryAfterSeconds;
        // Transactions already fetched and routed from earlier pages of THIS SAME account's pagination
        // sequence, before the interruption. Callers must merge this into whatever they upsert so no
        // financial transaction data already retrieved from Pluggy is ever silently discarded.
        public TransactionSyncResult partialResult;
    }

    /**
     * @description Busca transações de uma conta específica da Pluggy (Bank Account ou Credit Card),
     * usando o endpoint atual /v2/transactions com paginação por cursor.
     */
    public static TransactionSyncResult fetchTransactionsForConnection(String pluggyItemId, String apiKey, String pluggyAccountId) {
        return fetchTransactionsForConnection(pluggyItemId, apiKey, pluggyAccountId, (String) null, null, null);
    }

    /**
     * @description Overload allowing pagination to resume from a specific cursor, used when a previous
     * attempt was interrupted by an HTTP 429 rate limit response.
     * @throws RateLimitException when the Pluggy API responds with HTTP 429.
     */
    public static TransactionSyncResult fetchTransactionsForConnection(String pluggyItemId, String apiKey, String pluggyAccountId, String startCursor) {
        return fetchTransactionsForConnection(pluggyItemId, apiKey, pluggyAccountId, startCursor, null, null);
    }

    /**
     * @description Overload allowing the transaction query to be filtered by period (dateFrom/dateTo),
     * used by targeted manual syncs (Bank Account / Credit Card / Credit Card Invoice).
     */
    public static TransactionSyncResult fetchTransactionsForConnection(String pluggyItemId, String apiKey, String pluggyAccountId, Date startDate, Date endDate) {
        return fetchTransactionsForConnection(pluggyItemId, apiKey, pluggyAccountId, (String) null, startDate, endDate);
    }

    /**
     * @description Overload combining cursor resume with an optional dateFrom/dateTo period filter.
     * @throws RateLimitException when the Pluggy API responds with HTTP 429.
     */
    public static TransactionSyncResult fetchTransactionsForConnection(String pluggyItemId, String apiKey, String pluggyAccountId, String startCursor, Date startDate, Date endDate) {
        TransactionSyncResult result = new TransactionSyncResult();

        if (String.isBlank(pluggyAccountId)) {
            return result;
        }

        Map<String, Id> bankAccountIdByPluggyId = queryBankAccountIds();
        Map<String, AXF_OBJ_CreditCard__c> creditCardByPluggyId = queryCreditCards();
        Map<String, Id> categoryIdByPluggyId = queryCategoryIds();
        Map<String, Id> invoiceIdByPluggyId = queryInvoiceIds();

        String periodParams = (startDate != null && endDate != null)
            ? '&dateFrom=' + formatDate(startDate) + '&dateTo=' + formatDate(endDate)
            : '';

        String cursor = startCursor;
        Boolean hasNextPage = true;

        while (hasNextPage) {
            // Governor-limit-safe pagination: check the remaining callout budget for this transaction
            // BEFORE requesting the next page. If it's running low, stop here (never mid-HTTP-response),
            // so the caller can upsert everything fetched so far and reschedule a continuation from the
            // exact cursor — extending the same resume mechanism used for HTTP 429 rate limiting.
            if (Limits.getLimitCallouts() - Limits.getCallouts() <= CALLOUT_SAFETY_MARGIN) {
                RateLimitException governorLimitException = new RateLimitException(
                    'Approaching Salesforce callout governor limit while paginating transactions for account ' + pluggyAccountId + '.'
                );
                governorLimitException.resumeCursor = cursor;
                governorLimitException.retryAfterSeconds = GOVERNOR_LIMIT_RETRY_SECONDS;
                governorLimitException.partialResult = result;
                throw governorLimitException;
            }

            String endpoint = TRANSACTIONS_ENDPOINT_V2
                + EncodingUtil.urlEncode(pluggyAccountId, 'UTF-8')
                + periodParams
                + (String.isNotBlank(cursor) ? '&after=' + EncodingUtil.urlEncode(cursor, 'UTF-8') : '');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('X-API-KEY', apiKey);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() == 429) {
                RateLimitException rle = new RateLimitException(
                    'Pluggy API rate limit (HTTP 429) exceeded for account ' + pluggyAccountId + '.'
                );
                rle.resumeCursor = cursor;
                rle.retryAfterSeconds = parseRetryAfterSeconds(res.getHeader('Retry-After'));
                rle.partialResult = result;
                throw rle;
            }

            if (res.getStatusCode() != 200) {
                break;
            }

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> results = (List<Object>) body.get('results');

            if (results != null) {
                routeTransactions(
                    results,
                    bankAccountIdByPluggyId,
                    creditCardByPluggyId,
                    categoryIdByPluggyId,
                    invoiceIdByPluggyId,
                    result
                );
            }

            cursor = (String) body.get('next');
            hasNextPage = String.isNotBlank(cursor);
        }

        return result;
    }

    /**
     * @description Parses the Retry-After header (numeric seconds form only) returned by the Pluggy API.
     * Returns null when absent or expressed as an HTTP-date, so the caller can fall back to exponential backoff.
     */
    private static Integer parseRetryAfterSeconds(String retryAfterHeader) {
        if (String.isBlank(retryAfterHeader) || !retryAfterHeader.trim().isNumeric()) {
            return null;
        }
        return Integer.valueOf(retryAfterHeader.trim());
    }

    public static void upsertTransactions(TransactionSyncResult result) {
        if (!result.bankAccountTransactions.isEmpty()) {
            Database.upsert(
                result.bankAccountTransactions,
                AXF_OBJ_BankAccountTransaction__c.AXF_BAT_EXI_PluggyTransactionId__c,
                false
            );
        }
        if (!result.creditCardTransactions.isEmpty()) {
            Database.upsert(
                result.creditCardTransactions,
                AXF_OBJ_CreditCardTransaction__c.AXF_CCT_EXI_PluggyTransactionId__c,
                false
            );
        }
    }

    private static void routeTransactions(
        List<Object> results,
        Map<String, Id> bankAccountIdByPluggyId,
        Map<String, AXF_OBJ_CreditCard__c> creditCardByPluggyId,
        Map<String, Id> categoryIdByPluggyId,
        Map<String, Id> invoiceIdByPluggyId,
        TransactionSyncResult result
    ) {
        for (Object item : results) {
            Map<String, Object> data = (Map<String, Object>) item;
            String accountId = (String) data.get('accountId');

            if (accountId == null) {
                continue;
            }

            if (bankAccountIdByPluggyId.containsKey(accountId)) {
                result.bankAccountTransactions.add(
                    mapBankAccountTransaction(data, bankAccountIdByPluggyId.get(accountId), categoryIdByPluggyId)
                );
            } else if (creditCardByPluggyId.containsKey(accountId)) {
                result.creditCardTransactions.add(
                    mapCreditCardTransaction(
                        data,
                        creditCardByPluggyId.get(accountId),
                        categoryIdByPluggyId,
                        invoiceIdByPluggyId
                    )
                );
            }
        }
    }

    private static AXF_OBJ_BankAccountTransaction__c mapBankAccountTransaction(
        Map<String, Object> data,
        Id bankAccountId,
        Map<String, Id> categoryIdByPluggyId
    ) {
        AXF_OBJ_BankAccountTransaction__c txn = new AXF_OBJ_BankAccountTransaction__c();
        txn.AXF_BAT_EXI_PluggyTransactionId__c = (String) data.get('id');
        txn.AXF_BAT_LKP_BankAccount__c = bankAccountId;
        txn.AXF_BAT_CUR_Amount__c = data.get('amount') != null ? (Decimal) data.get('amount') : null;
        txn.AXF_BAT_TXT_Description__c = (String) data.get('description');
        txn.AXF_BAT_DAT_Date__c = parseDatetime((String) data.get('date'));
        txn.AXF_BAT_LKP_Category__c = resolveCategory((String) data.get('categoryId'), categoryIdByPluggyId);
        return txn;
    }

    private static AXF_OBJ_CreditCardTransaction__c mapCreditCardTransaction(
        Map<String, Object> data,
        AXF_OBJ_CreditCard__c creditCard,
        Map<String, Id> categoryIdByPluggyId,
        Map<String, Id> invoiceIdByPluggyId
    ) {
        AXF_OBJ_CreditCardTransaction__c txn = new AXF_OBJ_CreditCardTransaction__c();
        txn.AXF_CCT_EXI_PluggyTransactionId__c = (String) data.get('id');
        txn.AXF_CCT_LKP_CreditCard__c = creditCard.Id;
        txn.AXF_CCT_CUR_Amount__c = data.get('amount') != null ? (Decimal) data.get('amount') : null;
        String description = (String) data.get('description');
        txn.AXF_CCT_TXT_Description__c = description;
        txn.Name = String.isNotBlank(description) ? description.left(80) : 'Transaction';
        txn.AXF_CCT_DAT_Date__c = parseDatetime((String) data.get('date'));
        txn.AXF_CCT_LKP_Category__c = resolveCategory((String) data.get('categoryId'), categoryIdByPluggyId);

        // billId is nested inside creditCardMetadata per Pluggy API v2 spec
        Boolean invoiceSet = false;
        Map<String, Object> ccMeta = (Map<String, Object>) data.get('creditCardMetadata');
        if (ccMeta != null) {
            String billId = (String) ccMeta.get('billId');
            if (billId != null) {
                if (invoiceIdByPluggyId.containsKey(billId)) {
                    txn.AXF_CCT_LKP_CreditCardInvoice__c = invoiceIdByPluggyId.get(billId);
                    invoiceSet = true;
                } else {
                    txn.AXF_CCT_LKP_CreditCardInvoice__r = new AXF_OBJ_CreditCardInvoice__c(
                        AXF_CCI_EXI_PluggyInvoiceId__c = billId
                    );
                    invoiceSet = true;
                }
            }
        }

        // Fallback: If no direct billId, relate via External ID ({LastFourDigits}_{YYYY-MM})
        if (!invoiceSet && String.isNotBlank(creditCard.AXF_CC_TXT_LastFourDigits__c) && txn.AXF_CCT_DAT_Date__c != null) {
            String yearMonth = txn.AXF_CCT_DAT_Date__c.format('yyyy-MM');
            String targetExternalId = creditCard.AXF_CC_TXT_LastFourDigits__c + '_' + yearMonth;
            txn.AXF_CCT_LKP_CreditCardInvoice__r = new AXF_OBJ_CreditCardInvoice__c(
                AXF_CCI_EXT_ExternalId__c = targetExternalId
            );
        }

        return txn;
    }

    private static Id resolveCategory(String categoryId, Map<String, Id> categoryIdByPluggyId) {
        return categoryId != null && categoryIdByPluggyId.containsKey(categoryId) ? categoryIdByPluggyId.get(categoryId) : null;
    }

    private static Map<String, Id> queryBankAccountIds() {
        Map<String, Id> idsByPluggyId = new Map<String, Id>();
        for (AXF_OBJ_BankAccount__c account : [
            SELECT Id, AXF_BA_EXI_PluggyAccountId__c
            FROM AXF_OBJ_BankAccount__c
            WHERE AXF_BA_EXI_PluggyAccountId__c != null
        ]) {
            idsByPluggyId.put(account.AXF_BA_EXI_PluggyAccountId__c, account.Id);
        }
        return idsByPluggyId;
    }

    private static Map<String, AXF_OBJ_CreditCard__c> queryCreditCards() {
        Map<String, AXF_OBJ_CreditCard__c> cardsByPluggyId = new Map<String, AXF_OBJ_CreditCard__c>();
        for (AXF_OBJ_CreditCard__c card : [
            SELECT Id, AXF_CC_EXI_PluggyCreditCardId__c, AXF_CC_TXT_LastFourDigits__c
            FROM AXF_OBJ_CreditCard__c
            WHERE AXF_CC_EXI_PluggyCreditCardId__c != null
        ]) {
            cardsByPluggyId.put(card.AXF_CC_EXI_PluggyCreditCardId__c, card);
        }
        return cardsByPluggyId;
    }

    private static Map<String, Id> queryCategoryIds() {
        Map<String, Id> idsByPluggyId = new Map<String, Id>();
        for (AXF_OBJ_Category__c category : [
            SELECT Id, AXF_CAT_EXI_PluggyCategoryId__c
            FROM AXF_OBJ_Category__c
            WHERE AXF_CAT_EXI_PluggyCategoryId__c != null
        ]) {
            idsByPluggyId.put(category.AXF_CAT_EXI_PluggyCategoryId__c, category.Id);
        }
        return idsByPluggyId;
    }

    private static Map<String, Id> queryInvoiceIds() {
        Map<String, Id> idsByPluggyId = new Map<String, Id>();
        for (AXF_OBJ_CreditCardInvoice__c invoice : [
            SELECT Id, AXF_CCI_EXI_PluggyInvoiceId__c
            FROM AXF_OBJ_CreditCardInvoice__c
            WHERE AXF_CCI_EXI_PluggyInvoiceId__c != null
        ]) {
            idsByPluggyId.put(invoice.AXF_CCI_EXI_PluggyInvoiceId__c, invoice.Id);
        }
        return idsByPluggyId;
    }

    private static Datetime parseDatetime(String isoDatetime) {
        if (String.isBlank(isoDatetime)) {
            return null;
        }
        return (Datetime) JSON.deserialize('"' + isoDatetime + '"', Datetime.class);
    }

    /**
     * @description Formats a Date as YYYY-MM-DD, the format expected by the Pluggy dateFrom/dateTo query params.
     */
    private static String formatDate(Date d) {
        String monthStr = d.month() < 10 ? '0' + d.month() : String.valueOf(d.month());
        String dayStr = d.day() < 10 ? '0' + d.day() : String.valueOf(d.day());
        return d.year() + '-' + monthStr + '-' + dayStr;
    }
}