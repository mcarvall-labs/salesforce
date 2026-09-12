/** Thin LWC boundary for AXF-86. */
public with sharing class AXF_CLS_CTRL_ManualFinancialSource {
  // Primitive params so the LWC call binds reliably (Aura does not populate an
  // @AuraEnabled parameter typed as an inner class of another top-level class).
  @AuraEnabled
  public static ALT_CLS_BankInstitution.SaveResult createBankInstitution(
    String name,
    String bankNumber
  ) {
    ALT_CLS_BankInstitution.SaveInput input = new ALT_CLS_BankInstitution.SaveInput();
    input.name = name;
    input.bankNumber = bankNumber;
    return new ALT_CLS_BankInstitution().save(input);
  }

  // Primitive params (not the service's inner DTO) so the LWC call binds reliably:
  // Aura does not populate the fields of an @AuraEnabled Apex class that is an inner
  // class of another top-level class. Same limitation fixed in
  // AXF_CLS_CTRL_OnboardingProgress. AXF-86 / AXF-106.
  @AuraEnabled
  public static ALT_CLS_ManualFinancialSource.SaveResult save(
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
    input.expectedVersion = expectedVersion;
    return new ALT_CLS_ManualFinancialSource().save(input);
  }
}
