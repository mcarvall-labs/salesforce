public with sharing class AXF_CLS_CTRL_Category {
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
  public static List<AXF_OBJ_Category__c> getCategories(
    String recordTypeDeveloperName
  ) {
    String rtDevName = (recordTypeDeveloperName == 'DESPESA' ||
      recordTypeDeveloperName == 'Expense')
      ? 'AXF_CAT_RT_Expense'
      : (recordTypeDeveloperName == 'RECEITA' ||
          recordTypeDeveloperName == 'Revenue')
          ? 'AXF_CAT_RT_Revenue'
          : recordTypeDeveloperName;

    return [
      SELECT Id, Name, AXF_CAT_PKL_Type__c, RecordType.DeveloperName
      FROM AXF_OBJ_Category__c
      WHERE
        RecordType.DeveloperName = :rtDevName
        OR AXF_CAT_PKL_Type__c = :recordTypeDeveloperName
        OR (AXF_CAT_PKL_Type__c = NULL
        AND RecordTypeId = NULL)
      WITH USER_MODE
      ORDER BY Name ASC
    ];
  }

  /**
   * Returns only leaf-selectable categories (subcategories, or top-level categories
   * without subcategories) with a combined "Parent > Child" display label, so
   * transactions are always tagged at the most specific level for reporting rollups
   * via AXF_CAT_LKP_Parent__c. Parent categories that have subcategories are excluded
   * from the selectable list (they act as grouping only).
   */
  @AuraEnabled(cacheable=true)
  public static List<CategoryOptionDTO> getCategoryOptions(
    String recordTypeDeveloperName
  ) {
    List<AXF_OBJ_Category__c> categories = [
      SELECT Id, Name, AXF_CAT_LKP_Parent__c, AXF_CAT_LKP_Parent__r.Name
      FROM AXF_OBJ_Category__c
      WHERE RecordType.DeveloperName = :recordTypeDeveloperName
      WITH USER_MODE
      ORDER BY AXF_CAT_LKP_Parent__r.Name ASC NULLS FIRST, Name ASC
    ];

    Set<Id> parentIds = new Set<Id>();
    for (AXF_OBJ_Category__c cat : categories) {
      if (cat.AXF_CAT_LKP_Parent__c != null) {
        parentIds.add(cat.AXF_CAT_LKP_Parent__c);
      }
    }

    List<CategoryOptionDTO> options = new List<CategoryOptionDTO>();
    for (AXF_OBJ_Category__c cat : categories) {
      if (parentIds.contains(cat.Id)) {
        continue;
      }
      CategoryOptionDTO dto = new CategoryOptionDTO();
      dto.id = cat.Id;
      dto.displayLabel = cat.AXF_CAT_LKP_Parent__c != null
        ? cat.AXF_CAT_LKP_Parent__r.Name + ' > ' + cat.Name
        : cat.Name;
      options.add(dto);
    }
    return options;
  }

  /**
   * Returns only top-level categories (no AXF_CAT_LKP_Parent__c) for the given RecordType,
   * used to populate the "Parent Category" picker when creating a new Category from the
   * quick-entry form, so a new subcategory can only be nested under an existing group.
   */
  @AuraEnabled(cacheable=true)
  public static List<CategoryOptionDTO> getTopLevelCategoryOptions(
    String recordTypeDeveloperName
  ) {
    List<AXF_OBJ_Category__c> categories = [
      SELECT Id, Name
      FROM AXF_OBJ_Category__c
      WHERE
        RecordType.DeveloperName = :recordTypeDeveloperName
        AND AXF_CAT_LKP_Parent__c = NULL
      WITH USER_MODE
      ORDER BY Name ASC
    ];

    List<CategoryOptionDTO> options = new List<CategoryOptionDTO>();
    for (AXF_OBJ_Category__c cat : categories) {
      CategoryOptionDTO dto = new CategoryOptionDTO();
      dto.id = cat.Id;
      dto.displayLabel = cat.Name;
      options.add(dto);
    }
    return options;
  }

  /**
   * Creates a new Category on the fly from the quick-entry Category lookup (US-091), so a
   * missing Category can be added without leaving the Nova Despesa/Receita modal. Returns
   * the same id/displayLabel shape as getCategoryOptions so the lookup can select it immediately.
   */
  @AuraEnabled
  public static CategoryOptionDTO createCategory(CategoryCreationDTO dto) {
    if (dto == null || String.isBlank(dto.name)) {
      throw new AuraHandledException('Category name is required.');
    }

    String rtDevName = (dto.recordTypeDeveloperName == 'DESPESA' ||
      dto.recordTypeDeveloperName == 'Expense')
      ? 'AXF_CAT_RT_Expense'
      : (dto.recordTypeDeveloperName == 'RECEITA' ||
          dto.recordTypeDeveloperName == 'Revenue')
          ? 'AXF_CAT_RT_Revenue'
          : dto.recordTypeDeveloperName;

    Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.AXF_OBJ_Category__c.getRecordTypeInfosByDeveloperName();
    if (!rtMap.containsKey(rtDevName)) {
      throw new AuraHandledException('Invalid Category Record Type.');
    }

    Id parentId;
    if (String.isNotBlank(dto.parentId)) {
      try {
        parentId = (Id) dto.parentId;
      } catch (Exception e) {
        throw new AuraHandledException('Invalid Parent Category.');
      }
      if (parentId.getSObjectType() != AXF_OBJ_Category__c.SObjectType) {
        throw new AuraHandledException('Invalid Parent Category.');
      }
    }

    AXF_OBJ_Category__c cat = new AXF_OBJ_Category__c(
      Name = dto.name.trim(),
      RecordTypeId = rtMap.get(rtDevName).getRecordTypeId(),
      AXF_CAT_LKP_Parent__c = parentId
    );
    insert cat;

    CategoryOptionDTO result = new CategoryOptionDTO();
    result.id = cat.Id;
    result.displayLabel = cat.Name;

    if (parentId != null) {
      AXF_OBJ_Category__c parent = [
        SELECT Name
        FROM AXF_OBJ_Category__c
        WHERE Id = :parentId
        WITH USER_MODE
        LIMIT 1
      ];
      result.displayLabel = parent.Name + ' > ' + cat.Name;
    }

    return result;
  }
}
