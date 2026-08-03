/**
 * @description       :
 * @author            : Michel Carvalho Lopes
 * @group             : Altice Labs
 * @last modified on  : 07-18-2026
 * @last modified by  : Michel Carvalho Lopes
 * @tested with       :
 * @version           : 1.0
 * @modification log  :
 * Modifications Log
 * Ver   Date         Author                  Modification
 * 1.0   07-18-2026   Michel Carvalho Lopes   Initial Version
**/
public with sharing class AXF_CLS_PluggyItemSyncQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer MAX_CALLOUTS_PER_EXECUTION = 90;
    private static final String ITEMS_ENDPOINT = 'callout:AXF_NC_Pluggy_API/items/';

    private List<AXF_OBJ_PluggyConnection__c> connectionsToProcess;

    public AXF_CLS_PluggyItemSyncQueueable() {
        this(
            [
                SELECT Id, AXF_CON_EXI_PluggyItemId__c
                FROM AXF_OBJ_PluggyConnection__c
                WHERE AXF_CON_EXI_PluggyItemId__c != null
            ]
        );
    }

    public AXF_CLS_PluggyItemSyncQueueable(List<AXF_OBJ_PluggyConnection__c> connections) {
        this.connectionsToProcess = connections;
    }

    public void execute(QueueableContext context) {
        if (connectionsToProcess.isEmpty()) {
            return;
        }

        Integer batchSize = Math.min(connectionsToProcess.size(), MAX_CALLOUTS_PER_EXECUTION);
        List<AXF_OBJ_PluggyConnection__c> currentBatch = new List<AXF_OBJ_PluggyConnection__c>();
        List<AXF_OBJ_PluggyConnection__c> remaining = new List<AXF_OBJ_PluggyConnection__c>();

        for (Integer i = 0; i < connectionsToProcess.size(); i++) {
            if (i < batchSize) {
                currentBatch.add(connectionsToProcess[i]);
            } else {
                remaining.add(connectionsToProcess[i]);
            }
        }

        String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();
        List<AXF_OBJ_PluggyConnection__c> connectionsToUpdate = new List<AXF_OBJ_PluggyConnection__c>();
        AXF_CLS_PluggyAccountSync_Service.AccountSyncResult accountsToUpsert = new AXF_CLS_PluggyAccountSync_Service.AccountSyncResult();
        List<AXF_OBJ_Investment__c> investmentsToUpsert = new List<AXF_OBJ_Investment__c>();
        List<AXF_OBJ_Loan__c> loansToUpsert = new List<AXF_OBJ_Loan__c>();

        for (AXF_OBJ_PluggyConnection__c conn : currentBatch) {
            connectionsToUpdate.add(syncConnection(conn, apiKey, accountsToUpsert, investmentsToUpsert, loansToUpsert));
        }

        AXF_CLS_PluggyAccountSync_Service.upsertAccounts(accountsToUpsert);

        if (!investmentsToUpsert.isEmpty()) {
            AXF_CLS_PluggyInvSync_Service.upsertInvestments(investmentsToUpsert);
        }

        if (!loansToUpsert.isEmpty()) {
            AXF_CLS_PluggyLoanSync_Service.upsertLoans(loansToUpsert);
        }

        if (!connectionsToUpdate.isEmpty()) {
            update connectionsToUpdate;
        }

        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new AXF_CLS_PluggyItemSyncQueueable(remaining));
        } else if (!Test.isRunningTest()) {
            enqueueCreditCardSyncIfNeeded(accountsToUpsert.creditCards);
            enqueueBankAccountSyncIfNeeded(accountsToUpsert.bankAccounts);
        }
    }

    private void enqueueCreditCardSyncIfNeeded(List<AXF_OBJ_CreditCard__c> syncedCreditCards) {
        List<AXF_OBJ_CreditCard__c> creditCardsWithId = new List<AXF_OBJ_CreditCard__c>();
        for (AXF_OBJ_CreditCard__c card : syncedCreditCards) {
            if (card.Id != null) {
                creditCardsWithId.add(card);
            }
        }

        if (!creditCardsWithId.isEmpty()) {
            System.enqueueJob(new AXF_CLS_PluggyCreditCardSyncQueueable(creditCardsWithId));
        }
    }

    private void enqueueBankAccountSyncIfNeeded(List<AXF_OBJ_BankAccount__c> syncedBankAccounts) {
        List<AXF_OBJ_BankAccount__c> bankAccountsWithId = new List<AXF_OBJ_BankAccount__c>();
        for (AXF_OBJ_BankAccount__c acc : syncedBankAccounts) {
            if (acc.Id != null) {
                bankAccountsWithId.add(acc);
            }
        }

        if (!bankAccountsWithId.isEmpty()) {
            System.enqueueJob(new AXF_CLS_PluggyBankAccountSyncQueueable(bankAccountsWithId));
        }
    }

    private AXF_OBJ_PluggyConnection__c syncConnection(
        AXF_OBJ_PluggyConnection__c conn,
        String apiKey,
        AXF_CLS_PluggyAccountSync_Service.AccountSyncResult accountsToUpsert,
        List<AXF_OBJ_Investment__c> investmentsToUpsert,
        List<AXF_OBJ_Loan__c> loansToUpsert
    ) {
        AXF_OBJ_PluggyConnection__c updated = new AXF_OBJ_PluggyConnection__c(Id = conn.Id);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(ITEMS_ENDPOINT + conn.AXF_CON_EXI_PluggyItemId__c);
        req.setMethod('GET');
        req.setHeader('X-API-KEY', apiKey);

        try {
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                updated.AXF_CON_TXT_SyncStatus__c = (String) body.get('status');
                updated.AXF_CON_TXT_ExecutionStatus__c = (String) body.get('executionStatus');
                updated.AXF_CON_DT_LastSyncDatetime__c = parseLastUpdatedAt((String) body.get('lastUpdatedAt'));
                updated.AXF_CON_TXT_SyncErrorMessage__c = extractErrorMessage(body.get('error'));

                if (updated.AXF_CON_TXT_SyncStatus__c == 'UPDATED') {
                    collectRelatedData(
                        conn.Id,
                        conn.AXF_CON_EXI_PluggyItemId__c,
                        apiKey,
                        accountsToUpsert,
                        investmentsToUpsert,
                        loansToUpsert
                    );
                }
            } else {
                updated.AXF_CON_TXT_SyncErrorMessage__c = 'Falha HTTP ' + res.getStatusCode() + ' ao consultar /items.';
            }
        } catch (Exception e) {
            updated.AXF_CON_TXT_SyncErrorMessage__c = 'Erro de conexão: ' + e.getMessage();
        }

        return updated;
    }

    private void collectRelatedData(
        Id connectionId,
        String pluggyItemId,
        String apiKey,
        AXF_CLS_PluggyAccountSync_Service.AccountSyncResult accountsToUpsert,
        List<AXF_OBJ_Investment__c> investmentsToUpsert,
        List<AXF_OBJ_Loan__c> loansToUpsert
    ) {
        try {
            AXF_CLS_PluggyAccountSync_Service.AccountSyncResult fetched = AXF_CLS_PluggyAccountSync_Service.fetchAccountsForConnection(
                connectionId,
                pluggyItemId,
                apiKey
            );
            accountsToUpsert.bankAccounts.addAll(fetched.bankAccounts);
            accountsToUpsert.creditCards.addAll(fetched.creditCards);
        } catch (Exception e) {
            // Falha ao buscar contas/cartões não deve interromper a atualização do status da conexão.
        }

        try {
            investmentsToUpsert.addAll(
                AXF_CLS_PluggyInvSync_Service.fetchInvestmentsForConnection(connectionId, pluggyItemId, apiKey)
            );
        } catch (Exception e) {
            // Falha ao buscar investimentos não deve interromper a atualização do status da conexão.
        }

        try {
            loansToUpsert.addAll(AXF_CLS_PluggyLoanSync_Service.fetchLoansForConnection(connectionId, pluggyItemId, apiKey));
        } catch (Exception e) {
            // Falha ao buscar empréstimos não deve interromper a atualização do status da conexão.
        }
    }

    private Datetime parseLastUpdatedAt(String isoDatetime) {
        if (String.isBlank(isoDatetime)) {
            return null;
        }
        return (Datetime) JSON.deserialize('"' + isoDatetime + '"', Datetime.class);
    }

    private String extractErrorMessage(Object errorNode) {
        if (errorNode == null) {
            return null;
        }
        String code = null;
        String rawMessage = null;

        if (errorNode instanceof Map<String, Object>) {
            Map<String, Object> errorMap = (Map<String, Object>) errorNode;
            code = (String) errorMap.get('code');
            Object message = errorMap.get('message');
            rawMessage = message != null ? String.valueOf(message) : null;
        } else {
            rawMessage = String.valueOf(errorNode);
        }

        // Mapeamento de erros conhecidos para mensagens amigáveis em Português (US-023)
        if (String.isNotBlank(code)) {
            switch on code {
                when 'INVALID_CREDENTIALS', 'INVALID_PARAMETER' {
                    return 'Credenciais inválidas: As chaves ou senha informadas foram recusadas pela instituição bancária. Por favor, re-conecte o banco.';
                }
                when 'USER_INPUT_REQUIRED', 'WAITING_USER_INPUT' {
                    return 'Autenticação necessária: O banco exige token SMS/OTP ou autorização adicional no aplicativo bancário.';
                }
                when 'SITE_ERROR', 'CONNECTOR_ERROR' {
                    return 'Instabilidade na Instituição: O sistema do banco está temporariamente indisponível. A sincronização será tentada novamente mais tarde.';
                }
                when 'UNEXPECTED_ERROR' {
                    return 'Erro Inesperado: Ocorreu uma falha no processamento do conector bancário pela Pluggy.';
                }
            }
        }

        if (String.isNotBlank(rawMessage)) {
            if (rawMessage.contains('INVALID_CREDENTIALS') || rawMessage.contains('invalid credentials')) {
                return 'Credenciais inválidas: As chaves ou senha informadas foram recusadas pela instituição bancária. Por favor, re-conecte o banco.';
            }
            return rawMessage;
        }

        return String.valueOf(errorNode);
    }
}