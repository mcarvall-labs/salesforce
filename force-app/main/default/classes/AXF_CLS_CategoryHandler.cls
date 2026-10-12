public with sharing class AXF_CLS_CategoryHandler {
  public static void handleBeforeSave(
    List<AXF_OBJ_Category__c> categories,
    Map<Id, AXF_OBJ_Category__c> oldCategories
  ) {
    new ALT_CLS_CategoryHierarchy().validate(categories, oldCategories);
  }

  public static void handleBeforeDelete(List<AXF_OBJ_Category__c> categories) {
    new ALT_CLS_CategoryHierarchy().blockDeleteWithChildren(categories);
  }
}
