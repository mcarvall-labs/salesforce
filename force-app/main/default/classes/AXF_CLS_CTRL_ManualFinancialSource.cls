/**
 * @description Thin controller for aXF_LWC_manualFinancialSource over the legacy PROD
 * model. Delegates to ALT_CLS_ManualFinancialSource, which enforces AXF_CanConfigure,
 * CRUD/FLS and sharing and returns sanitized outcomes.
 */
public with sharing class AXF_CLS_CTRL_ManualFinancialSource {
  // Primitive params so the LWC call binds reliably (Aura does not populate an
  // @AuraEnabled parameter typed as an inner class of another top-level class).
  @AuraEnabled
  public static AXF_CLS_SourceSetupDTO.BankInstitutionResult createBankInstitution(
    String name,
    String bankNumber
  ) {
    return new ALT_CLS_ManualFinancialSource()
      .createBankInstitution(name, bankNumber);
  }

  // expectedVersion is accepted for contract compatibility: the legacy model has no
  // source version, so it is ignored.
  @AuraEnabled
  public static AXF_CLS_SourceSetupDTO.ManualSaveResult save(
    String kind,
    Id sourceId,
    Id holderId,
    String currencyIsoCode,
    String institutionName,
    Id bankInstitutionId,
    String maskedNumber,
    String sourceType,
    String brand,
    String manualKey,
    Integer expectedVersion
  ) {
    ALT_CLS_ManualFinancialSource.SaveInput input = new ALT_CLS_ManualFinancialSource.SaveInput();
    input.kind = kind;
    input.sourceId = sourceId;
    input.holderId = holderId;
    input.currencyIsoCode = currencyIsoCode;
    input.institutionName = institutionName;
    input.bankInstitutionId = bankInstitutionId;
    input.maskedNumber = maskedNumber;
    input.sourceType = sourceType;
    input.brand = brand;
    input.manualKey = manualKey;
    return new ALT_CLS_ManualFinancialSource().save(input);
  }
}
