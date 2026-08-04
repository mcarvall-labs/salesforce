/**
 * @description Dedicated controller for the aXF_LWC_accountLookup LWC. Thin entry point that
 * delegates to ALT_CLS_AccountLookup for the actual query logic, per PROJECT_RULES.md §3.
 */
public with sharing class AXF_CLS_CTRL_AccountLookup {
  public class AccountOptionDTO {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String displayLabel;
  }

  @AuraEnabled(cacheable=true)
  public static List<AccountOptionDTO> getAccountOptions() {
    ALT_CLS_AccountLookup businessService = new ALT_CLS_AccountLookup();
    List<ALT_CLS_AccountLookup.OptionResult> results = businessService.getAccountOptions();

    List<AccountOptionDTO> dtos = new List<AccountOptionDTO>();
    for (ALT_CLS_AccountLookup.OptionResult res : results) {
      AccountOptionDTO dto = new AccountOptionDTO();
      dto.id = res.id;
      dto.displayLabel = res.displayLabel;
      dtos.add(dto);
    }
    return dtos;
  }
}
