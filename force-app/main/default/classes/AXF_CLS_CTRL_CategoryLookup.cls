/**
 * @description Dedicated controller for the aXF_LWC_categoryLookup LWC. Thin entry point that
 * delegates to ALT_CLS_CategoryLookup for the actual query logic, per PROJECT_RULES.md §3.
 */
public with sharing class AXF_CLS_CTRL_CategoryLookup {
  public class CategoryOptionDTO {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String displayLabel;
  }

  public class CategoryCreationDTO {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String parentId;
    @AuraEnabled
    public String recordTypeDeveloperName;
  }

  @AuraEnabled(cacheable=true)
  public static List<CategoryOptionDTO> getCategoryOptions(
    String recordTypeDeveloperName
  ) {
    ALT_CLS_CategoryLookup businessService = new ALT_CLS_CategoryLookup();
    List<ALT_CLS_CategoryLookup.OptionResult> results = businessService.getCategoryOptions(
      recordTypeDeveloperName
    );
    return toDtos(results);
  }

  /**
   * @description Returns only top-level categories, used to populate the "Parent Category"
   * picker when creating a new Category from the quick-entry form.
   */
  @AuraEnabled(cacheable=true)
  public static List<CategoryOptionDTO> getTopLevelCategoryOptions(
    String recordTypeDeveloperName
  ) {
    ALT_CLS_CategoryLookup businessService = new ALT_CLS_CategoryLookup();
    List<ALT_CLS_CategoryLookup.OptionResult> results = businessService.getTopLevelCategoryOptions(
      recordTypeDeveloperName
    );
    return toDtos(results);
  }

  /**
   * @description Creates a new Category on the fly from the quick-entry Category lookup
   * (US-091), so a missing Category can be added without leaving the Nova Despesa/Receita modal.
   */
  @AuraEnabled
  public static CategoryOptionDTO createCategory(CategoryCreationDTO dto) {
    if (dto == null || String.isBlank(dto.name)) {
      throw new AuraHandledException('Category name is required.');
    }
    try {
      ALT_CLS_CategoryLookup businessService = new ALT_CLS_CategoryLookup();
      ALT_CLS_CategoryLookup.CategoryCreationRequest req = new ALT_CLS_CategoryLookup.CategoryCreationRequest();
      req.name = dto.name;
      req.parentId = dto.parentId;
      req.recordTypeDeveloperName = dto.recordTypeDeveloperName;

      ALT_CLS_CategoryLookup.OptionResult result = businessService.createCategory(
        req
      );
      CategoryOptionDTO createdDto = new CategoryOptionDTO();
      createdDto.id = result.id;
      createdDto.displayLabel = result.displayLabel;
      return createdDto;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Erro ao criar categoria: ' + e.getMessage()
      );
    }
  }

  private static List<CategoryOptionDTO> toDtos(
    List<ALT_CLS_CategoryLookup.OptionResult> results
  ) {
    List<CategoryOptionDTO> dtos = new List<CategoryOptionDTO>();
    for (ALT_CLS_CategoryLookup.OptionResult res : results) {
      CategoryOptionDTO dto = new CategoryOptionDTO();
      dto.id = res.id;
      dto.displayLabel = res.displayLabel;
      dtos.add(dto);
    }
    return dtos;
  }
}
