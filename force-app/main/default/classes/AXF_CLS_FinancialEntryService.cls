/**
 * @description Creates a manually-entered "Lançamento financeiro" (AXF_OBJ_FinancialTransaction__c)
 * from the guided entry wizard. AXF-19.
 *
 * Contract:
 *  - Money algebra (IMPLEMENTATION-CONTRACTS.md §1, kept per RECONCILIATION-CONTRACT.md): magnitude
 *    is always non-negative, direction (DEBIT|CREDIT) is separate, original currency never rewritten.
 *  - Mutation/idempotency (Fechamento G6-7, replaces the retired CommandExecution envelope): the
 *    client generates one idempotency key per confirm intent (AXF_FTX_EXI_ClientRequestId__c); the
 *    same key replays the durable result, a different payload under the same key is CONFLICT.
 *  - Authority: the target Account must be one of the caller's authorized contexts (AXF-3); the
 *    server never trusts an accountId from the client at face value. Ownership/sharing/CRUD/FLS are
 *    native (WITH USER_MODE / as user) — no AXF_CanConfigure gate, this is regular user data entry.
 *  - No AccountTeam, no financial content is revealed on a rejected attempt — errors are sanitized.
 */
public with sharing class AXF_CLS_FinancialEntryService {
  public class EntryInput {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String direction; // DEBIT | CREDIT
    @AuraEnabled
    public Decimal magnitude;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Date purchaseDate;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Id bankAccountId;
    @AuraEnabled
    public Id creditCardId;
    @AuraEnabled
    public String clientRequestId;
  }

  public class EntryResult {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public String outcome; // CREATED | ALREADY | CONFLICT | INVALID | FORBIDDEN
    @AuraEnabled
    public String message;
  }

  public class FundingSourceOption {
    @AuraEnabled
    public Id bankAccountId;
    @AuraEnabled
    public Id creditCardId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String kind; // BANK_ACCOUNT | CREDIT_CARD
  }

  private static final Set<String> VALID_DIRECTIONS = new Set<String>{
    'DEBIT',
    'CREDIT'
  };

  private static final String MSG_FORBIDDEN = 'Você não tem autorização para lançar nesta pessoa ou empresa.';
  private static final String MSG_INVALID = 'Revise os campos destacados antes de confirmar.';
  private static final String MSG_CONFLICT = 'Este lançamento já foi enviado com dados diferentes. Recarregue e confirme novamente.';
  private static final String MSG_SOURCE_INVALID = 'A conta ou o cartão selecionado não está disponível para esta pessoa ou empresa.';

  /**
   * @description Bank accounts / credit cards the caller can post this entry against —
   * only AVAILABLE sources (never CUSTODY, G5-5) belonging to the given authorized Account.
   */
  public static List<FundingSourceOption> getFundingSources(Id accountId) {
    List<FundingSourceOption> out = new List<FundingSourceOption>();
    if (accountId == null || !isAuthorizedContext(accountId)) {
      return out;
    }
    for (AXF_OBJ_BankAccount__c ba : [
      SELECT Id, AXF_BA_TXT_InstitutionName__c, AXF_BA_TXT_NumberMasked__c
      FROM AXF_OBJ_BankAccount__c
      WHERE
        AXF_BA_LKP_Account__c = :accountId
        AND AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
      ORDER BY AXF_BA_TXT_InstitutionName__c
    ]) {
      FundingSourceOption o = new FundingSourceOption();
      o.bankAccountId = ba.Id;
      o.kind = 'BANK_ACCOUNT';
      o.label = String.join(
        new List<String>{
          ba.AXF_BA_TXT_InstitutionName__c,
          ba.AXF_BA_TXT_NumberMasked__c
        },
        ' '
      );
      out.add(o);
    }
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT Id, AXF_CC_TXT_InstitutionName__c, AXF_CC_TXT_LastFourMasked__c
      FROM AXF_OBJ_CreditCard__c
      WHERE
        AXF_CC_LKP_Account__c = :accountId
        AND AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
      ORDER BY AXF_CC_TXT_InstitutionName__c
    ]) {
      FundingSourceOption o = new FundingSourceOption();
      o.creditCardId = cc.Id;
      o.kind = 'CREDIT_CARD';
      o.label = String.join(
        new List<String>{
          cc.AXF_CC_TXT_InstitutionName__c,
          cc.AXF_CC_TXT_LastFourMasked__c
        },
        ' '
      );
      out.add(o);
    }
    return out;
  }

  /**
   * @description Creates (or, on a client retry, safely reuses) one Lançamento. Never persists a
   * partial record and never confirms before every check passes.
   */
  public static EntryResult createEntry(EntryInput input) {
    EntryResult err = validate(input);
    if (err != null) {
      return err;
    }

    List<AXF_OBJ_FinancialTransaction__c> existing = [
      SELECT
        Id,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_LKP_CreditCard__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_EXI_ClientRequestId__c = :input.clientRequestId
      WITH USER_MODE
      LIMIT 1
    ];

    if (!existing.isEmpty()) {
      AXF_OBJ_FinancialTransaction__c prior = existing[0];
      Boolean samePayload =
        prior.AXF_FTX_LKP_Account__c == input.accountId &&
        prior.AXF_FTX_PKL_Direction__c == input.direction &&
        prior.AXF_FTX_NUM_Magnitude__c == input.magnitude &&
        prior.AXF_FTX_TXT_CurrencyIsoCode__c == input.currencyIsoCode &&
        prior.AXF_FTX_DAT_PurchaseDate__c == input.purchaseDate &&
        prior.AXF_FTX_LKP_BankAccount__c == input.bankAccountId &&
        prior.AXF_FTX_LKP_CreditCard__c == input.creditCardId;
      EntryResult r = new EntryResult();
      r.financialTransactionId = prior.Id;
      if (samePayload) {
        r.outcome = 'ALREADY';
        r.message = null;
      } else {
        r.outcome = 'CONFLICT';
        r.message = MSG_CONFLICT;
      }
      return r;
    }

    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = input.accountId,
      AXF_FTX_PKL_Direction__c = input.direction,
      AXF_FTX_NUM_Magnitude__c = input.magnitude,
      AXF_FTX_TXT_CurrencyIsoCode__c = input.currencyIsoCode,
      AXF_FTX_DAT_PurchaseDate__c = input.purchaseDate,
      AXF_FTX_DAT_DueDate__c = input.dueDate,
      AXF_FTX_LKP_BankAccount__c = input.bankAccountId,
      AXF_FTX_LKP_CreditCard__c = input.creditCardId,
      AXF_FTX_PKL_Status__c = 'CONFIRMED',
      AXF_FTX_CHK_IsEstimated__c = false,
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = input.clientRequestId
    );

    try {
      insert as user ftx;
    } catch (DmlException dmlError) {
      EntryResult r = new EntryResult();
      r.outcome = 'INVALID';
      r.message = MSG_INVALID;
      return r;
    }

    EntryResult r = new EntryResult();
    r.financialTransactionId = ftx.Id;
    r.outcome = 'CREATED';
    return r;
  }

  private static EntryResult validate(EntryInput input) {
    if (
      input == null ||
      input.accountId == null ||
      !isAuthorizedContext(input.accountId)
    ) {
      return err('FORBIDDEN', MSG_FORBIDDEN);
    }
    if (
      String.isBlank(input.direction) ||
      !VALID_DIRECTIONS.contains(input.direction.trim().toUpperCase())
    ) {
      return err('INVALID', MSG_INVALID);
    }
    if (input.magnitude == null || input.magnitude <= 0) {
      return err('INVALID', MSG_INVALID);
    }
    if (
      String.isBlank(input.currencyIsoCode) ||
      input.currencyIsoCode.trim().length() != 3
    ) {
      return err('INVALID', MSG_INVALID);
    }
    if (input.purchaseDate == null) {
      return err('INVALID', MSG_INVALID);
    }
    if (input.bankAccountId != null && input.creditCardId != null) {
      return err('INVALID', MSG_INVALID);
    }
    if (
      String.isBlank(input.clientRequestId) ||
      input.clientRequestId.length() != 36
    ) {
      return err('INVALID', MSG_INVALID);
    }
    if (
      input.bankAccountId != null &&
      !isAvailableBankAccount(input.bankAccountId, input.accountId)
    ) {
      return err('INVALID', MSG_SOURCE_INVALID);
    }
    if (
      input.creditCardId != null &&
      !isAvailableCreditCard(input.creditCardId, input.accountId)
    ) {
      return err('INVALID', MSG_SOURCE_INVALID);
    }
    return null;
  }

  private static EntryResult err(String outcome, String message) {
    EntryResult r = new EntryResult();
    r.outcome = outcome;
    r.message = message;
    return r;
  }

  private static Boolean isAuthorizedContext(Id accountId) {
    Set<Id> allowed = new Set<Id>();
    for (
      AXF_CLS_AuthorizedContextService.ContextView v : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      allowed.add(v.accountId);
    }
    return allowed.contains(accountId);
  }

  private static Boolean isAvailableBankAccount(
    Id bankAccountId,
    Id accountId
  ) {
    Integer found = [
      SELECT COUNT()
      FROM AXF_OBJ_BankAccount__c
      WHERE
        Id = :bankAccountId
        AND AXF_BA_LKP_Account__c = :accountId
        AND AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
    ];
    return found > 0;
  }

  private static Boolean isAvailableCreditCard(Id creditCardId, Id accountId) {
    Integer found = [
      SELECT COUNT()
      FROM AXF_OBJ_CreditCard__c
      WHERE
        Id = :creditCardId
        AND AXF_CC_LKP_Account__c = :accountId
        AND AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
    ];
    return found > 0;
  }
}
