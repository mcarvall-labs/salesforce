/**
 * @description Business service layer for manual Pluggy synchronization: full sync of all
 * registered connections, targeted per-record sync (Bank Account, Credit Card, Credit Card
 * Invoice), and async full-item sync triggering. Consumed by AXF_CLS_CTRL_PluggyManualSync and
 * AXF_CLS_CTRL_SyncAllAccounts. Contains no @AuraEnabled members and no LWC-specific concepts,
 * per PROJECT_RULES.md §3.
 */
public inherited sharing class ALT_CLS_ManualSync {
  public class SyncExecutionResult {
    public Boolean isSuccess;
    public String message;
    public Integer bankAccountsSynced;
    public Integer creditCardsSynced;
    public Integer connectionsProcessed;
    public Integer transactionsSynced;
    public Integer invoicesSynced;
    public List<String> errors;

    public SyncExecutionResult() {
      this.isSuccess = true;
      this.bankAccountsSynced = 0;
      this.creditCardsSynced = 0;
      this.connectionsProcessed = 0;
      this.transactionsSynced = 0;
      this.invoicesSynced = 0;
      this.errors = new List<String>();
    }
  }

  /**
   * @description Executa a sincronização síncrona de itens, contas e cartões do Open Finance.
   * Retorna um resultado detalhado (sucesso ou erro exato) para exibição na tela do LWC.
   */
  public SyncExecutionResult performSync() {
    SyncExecutionResult result = new SyncExecutionResult();

    try {
      String apiKey;
      try {
        apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();
      } catch (Exception authEx) {
        result.isSuccess = false;
        result.message = authEx.getMessage();
        return result;
      }

      List<AXF_OBJ_PluggyConnection__c> connections = [
        SELECT Id, Name, AXF_CON_EXI_PluggyItemId__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE AXF_CON_EXI_PluggyItemId__c != NULL
      ];

      if (connections.isEmpty()) {
        result.isSuccess = false;
        result.message = 'Nenhuma conexão bancária (Pluggy Connection) cadastrada no sistema para sincronizar.';
        return result;
      }

      result.connectionsProcessed = connections.size();

      List<AXF_OBJ_PluggyConnection__c> connectionsToUpdate = new List<AXF_OBJ_PluggyConnection__c>();
      AXF_CLS_PluggyAccountSync_Service.AccountSyncResult accountsToUpsert = new AXF_CLS_PluggyAccountSync_Service.AccountSyncResult();
      List<AXF_OBJ_Investment__c> investmentsToUpsert = new List<AXF_OBJ_Investment__c>();
      List<AXF_OBJ_Loan__c> loansToUpsert = new List<AXF_OBJ_Loan__c>();

      for (AXF_OBJ_PluggyConnection__c conn : connections) {
        AXF_OBJ_PluggyConnection__c updatedConn = syncConnectionRecord(
          conn,
          apiKey,
          accountsToUpsert,
          investmentsToUpsert,
          loansToUpsert,
          result.errors
        );
        connectionsToUpdate.add(updatedConn);
      }

      if (!accountsToUpsert.bankAccounts.isEmpty()) {
        Database.UpsertResult[] bankResults = Database.upsert(
          accountsToUpsert.bankAccounts,
          AXF_OBJ_BankAccount__c.AXF_BA_EXI_PluggyAccountId__c,
          false
        );
        for (Database.UpsertResult ur : bankResults) {
          if (ur.isSuccess()) {
            result.bankAccountsSynced++;
          } else {
            for (Database.Error err : ur.getErrors()) {
              result.errors.add(
                'Erro ao salvar Conta Bancária: ' + err.getMessage()
              );
            }
          }
        }
      }

      if (!accountsToUpsert.creditCards.isEmpty()) {
        Database.UpsertResult[] cardResults = Database.upsert(
          accountsToUpsert.creditCards,
          AXF_OBJ_CreditCard__c.AXF_CC_EXI_PluggyCreditCardId__c,
          false
        );
        for (Database.UpsertResult ur : cardResults) {
          if (ur.isSuccess()) {
            result.creditCardsSynced++;
          } else {
            for (Database.Error err : ur.getErrors()) {
              result.errors.add(
                'Erro ao salvar Cartão de Crédito: ' + err.getMessage()
              );
            }
          }
        }
      }

      if (!investmentsToUpsert.isEmpty()) {
        AXF_CLS_PluggyInvSync_Service.upsertInvestments(investmentsToUpsert);
      }

      if (!loansToUpsert.isEmpty()) {
        AXF_CLS_PluggyLoanSync_Service.upsertLoans(loansToUpsert);
      }

      if (!connectionsToUpdate.isEmpty()) {
        update connectionsToUpdate;
      }

      if (
        result.errors.isEmpty() ||
        result.bankAccountsSynced > 0 ||
        result.creditCardsSynced > 0
      ) {
        result.message =
          'Sincronização concluída com sucesso! ' +
          result.connectionsProcessed +
          ' conexões processadas, ' +
          result.bankAccountsSynced +
          ' contas bancárias e ' +
          result.creditCardsSynced +
          ' cartões de crédito sincronizados.';
      } else {
        result.isSuccess = false;
        result.message = 'A consulta de conexões foi executada, mas nenhuma conta foi retornada ou criada. Verifique os erros apresentados abaixo.';
      }
    } catch (Exception e) {
      result.isSuccess = false;
      result.message =
        'Erro inesperado durante a sincronização: ' + e.getMessage();
    }

    return result;
  }

  /**
   * @description Dispara o enfileiramento assíncrono da Queueable de sincronização geral.
   */
  public String triggerItemSync() {
    if (!Test.isRunningTest()) {
      System.enqueueJob(new AXF_CLS_PluggyItemSyncQueueable());
    }
    return 'Sincronização iniciada com sucesso!';
  }

  /**
   * @description Dispara a sincronização a partir de um registro específico (LWC Quick Action).
   * Quando o objeto de origem já possui uma sincronização direcionada implementada
   * (AXF_OBJ_BankAccount__c, AXF_OBJ_CreditCard__c, AXF_OBJ_CreditCardInvoice__c), a
   * sincronização é executada de forma síncrona e restrita ao registro (ou ao seu Cartão de
   * Crédito pai, no caso de Faturas). Caso contrário, mantém o comportamento de sincronização
   * geral assíncrona.
   * startDate/endDate escopam a sincronização a um período específico (dateFrom/dateTo). Quando
   * qualquer um deles for omitido, o padrão é a janela de 3 meses: primeiro dia do mês anterior
   * até o último dia do próximo mês.
   */
  public SyncExecutionResult syncRecord(
    Id recordId,
    String sObjectType,
    Date startDate,
    Date endDate
  ) {
    Date effectiveStartDate = startDate;
    Date effectiveEndDate = endDate;
    if (effectiveStartDate == null || effectiveEndDate == null) {
      Date firstDayOfCurrentMonth = Date.today().toStartOfMonth();
      effectiveStartDate = firstDayOfCurrentMonth.addMonths(-1);
      effectiveEndDate = firstDayOfCurrentMonth.addMonths(2).addDays(-1);
    }

    if (sObjectType == 'AXF_OBJ_BankAccount__c') {
      return syncBankAccountTransactions(
        recordId,
        effectiveStartDate,
        effectiveEndDate
      );
    }

    if (
      sObjectType == 'AXF_OBJ_CreditCard__c' ||
      sObjectType == 'AXF_OBJ_CreditCardInvoice__c'
    ) {
      Id creditCardId;

      if (sObjectType == 'AXF_OBJ_CreditCard__c') {
        creditCardId = recordId;
      } else {
        AXF_OBJ_CreditCardInvoice__c invoice = [
          SELECT AXF_CCI_MD_CreditCard__c
          FROM AXF_OBJ_CreditCardInvoice__c
          WHERE Id = :recordId
          LIMIT 1
        ];
        creditCardId = invoice.AXF_CCI_MD_CreditCard__c;
      }

      AXF_OBJ_CreditCard__c card = [
        SELECT
          AXF_CC_EXI_PluggyCreditCardId__c,
          AXF_CC_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c
        FROM AXF_OBJ_CreditCard__c
        WHERE Id = :creditCardId
        LIMIT 1
      ];

      if (
        String.isBlank(card.AXF_CC_EXI_PluggyCreditCardId__c) ||
        card.AXF_CC_LKP_PluggyConnection__r == null ||
        String.isBlank(
          card.AXF_CC_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c
        )
      ) {
        SyncExecutionResult errResult = new SyncExecutionResult();
        errResult.isSuccess = false;
        errResult.message = 'Este Cartão de Crédito não possui uma Conexão Pluggy válida associada.';
        return errResult;
      }

      SyncExecutionResult combinedResult = new SyncExecutionResult();

      try {
        String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();

        List<AXF_OBJ_CreditCardInvoice__c> invoices = AXF_CLS_PluggyBillSync_Service.fetchBillsForCreditCard(
          creditCardId,
          card.AXF_CC_EXI_PluggyCreditCardId__c,
          apiKey
        );

        AXF_CLS_PluggyTxSync_Service.TransactionSyncResult txResult = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
          card.AXF_CC_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c,
          apiKey,
          card.AXF_CC_EXI_PluggyCreditCardId__c,
          effectiveStartDate,
          effectiveEndDate
        );

        if (!invoices.isEmpty()) {
          Database.UpsertResult[] invResults = Database.upsert(
            invoices,
            AXF_OBJ_CreditCardInvoice__c.AXF_CCI_EXI_PluggyInvoiceId__c,
            false
          );
          for (Database.UpsertResult ur : invResults) {
            if (ur.isSuccess()) {
              combinedResult.invoicesSynced++;
            } else {
              for (Database.Error err : ur.getErrors()) {
                combinedResult.errors.add(
                  'Erro ao salvar fatura: ' + err.getMessage()
                );
              }
            }
          }
        }

        if (!txResult.creditCardTransactions.isEmpty()) {
          Database.UpsertResult[] txResults = Database.upsert(
            txResult.creditCardTransactions,
            AXF_OBJ_CreditCardTransaction__c.AXF_CCT_EXI_PluggyTransactionId__c,
            false
          );
          for (Database.UpsertResult ur : txResults) {
            if (ur.isSuccess()) {
              combinedResult.transactionsSynced++;
            } else {
              for (Database.Error err : ur.getErrors()) {
                combinedResult.errors.add(
                  'Erro ao salvar transação: ' + err.getMessage()
                );
              }
            }
          }
        }

        if (combinedResult.errors.isEmpty()) {
          combinedResult.message =
            'Sincronização concluída com sucesso! ' +
            combinedResult.invoicesSynced +
            ' fatura(s) e ' +
            combinedResult.transactionsSynced +
            ' transação(ões) do cartão sincronizadas.';
        } else {
          combinedResult.isSuccess = (combinedResult.invoicesSynced > 0 ||
          combinedResult.transactionsSynced > 0);
          combinedResult.message =
            combinedResult.invoicesSynced +
            ' fatura(s) e ' +
            combinedResult.transactionsSynced +
            ' transação(ões) sincronizadas com ' +
            combinedResult.errors.size() +
            ' erro(s).';
        }
      } catch (Exception e) {
        combinedResult.isSuccess = false;
        combinedResult.message =
          'Erro durante a sincronização de faturas e transações: ' +
          e.getMessage();
      }

      return combinedResult;
    }

    SyncExecutionResult fallback = new SyncExecutionResult();
    if (!Test.isRunningTest()) {
      System.enqueueJob(new AXF_CLS_PluggyItemSyncQueueable());
    }
    fallback.message = 'Sincronização geral iniciada com sucesso!';
    return fallback;
  }

  /**
   * @description Sincroniza de forma direcionada apenas as transações da Conta Bancária informada.
   * O accountId vem do próprio registro de Bank Account aberto na tela (contexto do LWC).
   */
  private SyncExecutionResult syncBankAccountTransactions(
    Id bankAccountId,
    Date startDate,
    Date endDate
  ) {
    SyncExecutionResult result = new SyncExecutionResult();
    AXF_OBJ_BankAccount__c account = [
      SELECT
        AXF_BA_EXI_PluggyAccountId__c,
        AXF_BA_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :bankAccountId
      LIMIT 1
    ];

    if (
      String.isBlank(account.AXF_BA_EXI_PluggyAccountId__c) ||
      account.AXF_BA_LKP_PluggyConnection__r == null ||
      String.isBlank(
        account.AXF_BA_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c
      )
    ) {
      result.isSuccess = false;
      result.message = 'Esta Conta Bancária não possui uma Conexão Pluggy válida associada.';
      return result;
    }

    try {
      String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();

      AXF_CLS_PluggyTxSync_Service.TransactionSyncResult txResult = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
        account.AXF_BA_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c,
        apiKey,
        account.AXF_BA_EXI_PluggyAccountId__c,
        startDate,
        endDate
      );

      Database.UpsertResult[] upsertResults = new List<Database.UpsertResult>();
      if (!txResult.bankAccountTransactions.isEmpty()) {
        upsertResults = Database.upsert(
          txResult.bankAccountTransactions,
          AXF_OBJ_BankAccountTransaction__c.AXF_BAT_EXI_PluggyTransactionId__c,
          false
        );
        for (Database.UpsertResult ur : upsertResults) {
          if (ur.isSuccess()) {
            result.transactionsSynced++;
          } else {
            for (Database.Error err : ur.getErrors()) {
              result.errors.add(
                'Erro ao salvar transação: ' + err.getMessage()
              );
            }
          }
        }
      }

      if (result.errors.isEmpty()) {
        result.message =
          'Sincronização concluída com sucesso! ' +
          result.transactionsSynced +
          ' transações bancárias sincronizadas.';
      } else {
        result.isSuccess = result.transactionsSynced > 0;
        result.message =
          result.transactionsSynced +
          ' transações sincronizadas com ' +
          result.errors.size() +
          ' erro(s).';
      }
    } catch (Exception e) {
      result.isSuccess = false;
      result.message = 'Erro durante a sincronização: ' + e.getMessage();
    }

    return result;
  }

  /**
   * @description Sincroniza de forma direcionada apenas as faturas (bills) do Credit Card informado.
   * O accountId vem do registro de Credit Card aberto na tela (contexto do LWC).
   */
  private SyncExecutionResult syncCreditCardInvoices(Id creditCardId) {
    SyncExecutionResult result = new SyncExecutionResult();
    AXF_OBJ_CreditCard__c card = [
      SELECT AXF_CC_EXI_PluggyCreditCardId__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :creditCardId
      LIMIT 1
    ];

    if (String.isBlank(card.AXF_CC_EXI_PluggyCreditCardId__c)) {
      result.isSuccess = false;
      result.message = 'Este Cartão de Crédito não possui um ID Pluggy válido associado.';
      return result;
    }

    try {
      String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();

      List<AXF_OBJ_CreditCardInvoice__c> invoices = AXF_CLS_PluggyBillSync_Service.fetchBillsForCreditCard(
        creditCardId,
        card.AXF_CC_EXI_PluggyCreditCardId__c,
        apiKey
      );

      if (!invoices.isEmpty()) {
        Database.UpsertResult[] upsertResults = Database.upsert(
          invoices,
          AXF_OBJ_CreditCardInvoice__c.AXF_CCI_EXI_PluggyInvoiceId__c,
          false
        );
        for (Database.UpsertResult ur : upsertResults) {
          if (ur.isSuccess()) {
            result.invoicesSynced++;
          } else {
            for (Database.Error err : ur.getErrors()) {
              result.errors.add('Erro ao salvar fatura: ' + err.getMessage());
            }
          }
        }
      }

      if (result.errors.isEmpty()) {
        result.message =
          'Sincronização concluída com sucesso! ' +
          result.invoicesSynced +
          ' fatura(s) sincronizadas.';
      } else {
        result.isSuccess = result.invoicesSynced > 0;
        result.message =
          result.invoicesSynced +
          ' fatura(s) sincronizadas com ' +
          result.errors.size() +
          ' erro(s).';
      }
    } catch (Exception e) {
      result.isSuccess = false;
      result.message =
        'Erro durante a sincronização de faturas: ' + e.getMessage();
    }

    return result;
  }

  /**
   * @description Sincroniza as transações do Cartão de Crédito pai da Fatura informada.
   * A Pluggy não permite filtrar transações por fatura — filtra apenas por conta/cartão.
   * O vínculo com a fatura é feito automaticamente via creditCardMetadata.billId em cada transação.
   * O accountId passado à API é o AXF_CC_EXI_PluggyCreditCardId__c do cartão pai da fatura.
   */
  private SyncExecutionResult syncInvoiceTransactions(Id invoiceId) {
    SyncExecutionResult result = new SyncExecutionResult();
    AXF_OBJ_CreditCardInvoice__c invoice = [
      SELECT
        AXF_CCI_MD_CreditCard__r.AXF_CC_EXI_PluggyCreditCardId__c,
        AXF_CCI_MD_CreditCard__r.AXF_CC_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c
      FROM AXF_OBJ_CreditCardInvoice__c
      WHERE Id = :invoiceId
      LIMIT 1
    ];

    if (
      invoice.AXF_CCI_MD_CreditCard__r == null ||
      String.isBlank(
        invoice.AXF_CCI_MD_CreditCard__r.AXF_CC_EXI_PluggyCreditCardId__c
      ) ||
      invoice.AXF_CCI_MD_CreditCard__r.AXF_CC_LKP_PluggyConnection__r == null ||
      String.isBlank(
        invoice.AXF_CCI_MD_CreditCard__r.AXF_CC_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c
      )
    ) {
      result.isSuccess = false;
      result.message = 'Esta Fatura não possui um Cartão de Crédito com Conexão Pluggy válida associada.';
      return result;
    }

    try {
      String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();

      AXF_CLS_PluggyTxSync_Service.TransactionSyncResult txResult = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
        invoice.AXF_CCI_MD_CreditCard__r.AXF_CC_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c,
        apiKey,
        invoice.AXF_CCI_MD_CreditCard__r.AXF_CC_EXI_PluggyCreditCardId__c
      );

      if (!txResult.creditCardTransactions.isEmpty()) {
        Database.UpsertResult[] upsertResults = Database.upsert(
          txResult.creditCardTransactions,
          AXF_OBJ_CreditCardTransaction__c.AXF_CCT_EXI_PluggyTransactionId__c,
          false
        );
        for (Database.UpsertResult ur : upsertResults) {
          if (ur.isSuccess()) {
            result.transactionsSynced++;
          } else {
            for (Database.Error err : ur.getErrors()) {
              result.errors.add(
                'Erro ao salvar transação: ' + err.getMessage()
              );
            }
          }
        }
      }

      if (result.errors.isEmpty()) {
        result.message =
          'Sincronização concluída com sucesso! ' +
          result.transactionsSynced +
          ' transação(ões) do cartão sincronizadas.';
      } else {
        result.isSuccess = result.transactionsSynced > 0;
        result.message =
          result.transactionsSynced +
          ' transação(ões) sincronizadas com ' +
          result.errors.size() +
          ' erro(s).';
      }
    } catch (Exception e) {
      result.isSuccess = false;
      result.message =
        'Erro durante a sincronização de transações: ' + e.getMessage();
    }

    return result;
  }

  private AXF_OBJ_PluggyConnection__c syncConnectionRecord(
    AXF_OBJ_PluggyConnection__c conn,
    String apiKey,
    AXF_CLS_PluggyAccountSync_Service.AccountSyncResult accountsToUpsert,
    List<AXF_OBJ_Investment__c> investmentsToUpsert,
    List<AXF_OBJ_Loan__c> loansToUpsert,
    List<String> errorsList
  ) {
    AXF_OBJ_PluggyConnection__c updated = new AXF_OBJ_PluggyConnection__c(
      Id = conn.Id
    );
    String endpoint =
      'callout:AXF_NC_Pluggy_API/items/' + conn.AXF_CON_EXI_PluggyItemId__c;

    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('GET');
    req.setHeader('X-API-KEY', apiKey);

    try {
      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() == 200) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        updated.AXF_CON_TXT_SyncStatus__c = (String) body.get('status');
        updated.AXF_CON_TXT_ExecutionStatus__c = (String) body.get(
          'executionStatus'
        );
        updated.AXF_CON_DT_LastSyncDatetime__c = parseDatetime(
          (String) body.get('lastUpdatedAt')
        );

        Object errorNode = body.get('error');
        if (errorNode != null) {
          updated.AXF_CON_TXT_SyncErrorMessage__c = String.valueOf(errorNode);
          errorsList.add(
            'Conexão ' +
              conn.Name +
              ': ' +
              updated.AXF_CON_TXT_SyncErrorMessage__c
          );
        }

        try {
          AXF_CLS_PluggyAccountSync_Service.AccountSyncResult fetched = AXF_CLS_PluggyAccountSync_Service.fetchAccountsForConnection(
            conn.Id,
            conn.AXF_CON_EXI_PluggyItemId__c,
            apiKey
          );
          accountsToUpsert.bankAccounts.addAll(fetched.bankAccounts);
          accountsToUpsert.creditCards.addAll(fetched.creditCards);
        } catch (Exception accEx) {
          errorsList.add(
            'Erro ao buscar contas para ' +
              conn.Name +
              ': ' +
              accEx.getMessage()
          );
        }

        try {
          investmentsToUpsert.addAll(
            AXF_CLS_PluggyInvSync_Service.fetchInvestmentsForConnection(
              conn.Id,
              conn.AXF_CON_EXI_PluggyItemId__c,
              apiKey
            )
          );
        } catch (Exception invEx) {
        }

        try {
          loansToUpsert.addAll(
            AXF_CLS_PluggyLoanSync_Service.fetchLoansForConnection(
              conn.Id,
              conn.AXF_CON_EXI_PluggyItemId__c,
              apiKey
            )
          );
        } catch (Exception loanEx) {
        }
      } else {
        String errMsg =
          'Falha HTTP ' +
          res.getStatusCode() +
          ' ao consultar item (' +
          conn.Name +
          '): ' +
          res.getBody();
        updated.AXF_CON_TXT_SyncErrorMessage__c = errMsg;
        errorsList.add(errMsg);
      }
    } catch (Exception e) {
      updated.AXF_CON_TXT_SyncErrorMessage__c =
        'Erro de conexão (' +
        conn.Name +
        '): ' +
        e.getMessage();
      errorsList.add('Erro ao conectar (' + conn.Name + '): ' + e.getMessage());
    }

    return updated;
  }

  private Datetime parseDatetime(String isoDatetime) {
    if (String.isBlank(isoDatetime)) {
      return null;
    }
    return (Datetime) JSON.deserialize('"' + isoDatetime + '"', Datetime.class);
  }
}
