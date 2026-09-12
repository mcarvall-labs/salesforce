/**
 * @description Creates and maintains the canonical Financial Institution directory
 * (AXF_OBJ_BankInstitution__c) that AXF-106 reuses as the single bank reference.
 *
 * - The bank number (COMPE code) is the authoritative external identifier: creation is
 *   idempotent on it, and a repeated number returns the existing record instead of
 *   duplicating the directory.
 * - Authority: the caller must hold AXF_CanConfigure. USER_MODE enforces object CRUD,
 *   field-level security and sharing on every read and write, so a client-supplied value
 *   grants nothing on its own.
 * - Registering an institution creates no connection, account, card or holder.
 */
public with sharing class ALT_CLS_BankInstitution {
  public enum Outcome {
    CREATED,
    ALREADY,
    INVALID,
    FORBIDDEN,
    FAILED
  }

  public class SaveInput {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String bankNumber;
  }

  public class SaveResult {
    @AuraEnabled
    public Id institutionId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String bankNumber;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<String> invalidFields = new List<String>();
  }

  @TestVisible
  private static Boolean canConfigureOverride;
  @TestVisible
  private static String lastFailure;

  private static final Integer MAX_NAME = 80;
  private static final Integer MAX_BANK_NUMBER = 8;

  private static Boolean canConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  public SaveResult save(SaveInput input) {
    if (!canConfigure()) {
      return fail(
        new SaveResult(),
        Outcome.FORBIDDEN,
        'Você não tem autorização para cadastrar instituições financeiras.'
      );
    }
    SaveResult r = new SaveResult();
    if (input == null) {
      return invalid(r, 'name', 'Informe o nome da instituição.');
    }
    String name = input.name == null ? null : input.name.trim();
    String bankNumber = input.bankNumber == null
      ? null
      : input.bankNumber.trim();
    if (String.isBlank(name)) {
      return invalid(r, 'name', 'Informe o nome da instituição.');
    }
    if (name.length() > MAX_NAME) {
      return invalid(r, 'name', 'O nome excede o limite permitido.');
    }
    if (String.isBlank(bankNumber)) {
      return invalid(r, 'bankNumber', 'Informe o código bancário.');
    }
    if (bankNumber.length() > MAX_BANK_NUMBER) {
      return invalid(r, 'bankNumber', 'O código bancário é muito longo.');
    }

    try {
      // The bank number is the external identity: re-informing it must never duplicate
      // the directory, and it must never silently rename an existing institution.
      List<AXF_OBJ_BankInstitution__c> existing = [
        SELECT Id, Name, AXF_BI_EXI_Bank_Number__c
        FROM AXF_OBJ_BankInstitution__c
        WHERE AXF_BI_EXI_Bank_Number__c = :bankNumber
        WITH USER_MODE
        LIMIT 1
      ];
      if (!existing.isEmpty()) {
        r.institutionId = existing[0].Id;
        r.name = existing[0].Name;
        r.bankNumber = existing[0].AXF_BI_EXI_Bank_Number__c;
        r.outcome = Outcome.ALREADY.name();
        r.message = 'Instituição financeira já cadastrada para este código bancário.';
        return r;
      }

      AXF_OBJ_BankInstitution__c row = new AXF_OBJ_BankInstitution__c(
        Name = name,
        AXF_BI_EXI_Bank_Number__c = bankNumber
      );
      insert as user row;
      r.institutionId = row.Id;
      r.name = name;
      r.bankNumber = bankNumber;
      r.outcome = Outcome.CREATED.name();
      r.message = 'Instituição financeira cadastrada.';
      return r;
    } catch (DmlException e) {
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      return fail(
        r,
        Outcome.INVALID,
        'Não foi possível cadastrar: verifique se o código bancário já existe.'
      );
    } catch (Exception e) {
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      return fail(
        r,
        Outcome.FAILED,
        'Não foi possível cadastrar a instituição. Nada foi alterado.'
      );
    }
  }

  private static SaveResult invalid(
    SaveResult r,
    String field,
    String message
  ) {
    r.invalidFields.add(field);
    return fail(r, Outcome.INVALID, message);
  }

  private static SaveResult fail(
    SaveResult r,
    Outcome outcome,
    String message
  ) {
    r.outcome = outcome.name();
    r.message = message;
    return r;
  }
}
