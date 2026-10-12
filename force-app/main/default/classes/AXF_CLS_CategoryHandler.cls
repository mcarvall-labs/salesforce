public with sharing class AXF_CLS_CategoryHandler {
  public static void handleBeforeSave(List<AXF_OBJ_Category__c> categories) {
    new ALT_CLS_CategoryHierarchy().validate(categories);
  }

  public static void handleBeforeDelete(List<AXF_OBJ_Category__c> categories) {
    new ALT_CLS_CategoryHierarchy().blockDeleteWithChildren(categories);
  }
}
