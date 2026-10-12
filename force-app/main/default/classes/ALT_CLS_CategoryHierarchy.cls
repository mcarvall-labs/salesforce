/**
 * @description Guards the Category hierarchy (AXF_CAT_LKP_Parent__c): a category cannot be
 * its own parent, and no chain of parents may loop back to it. Depth is unlimited in
 * practice: ancestors are walked upward, one query per level, and a chain longer than
 * maxLevels is rejected instead of being left unchecked. Integrity reads run in system
 * mode so a user who cannot see a category still cannot create a loop through it.
 */
public with sharing class ALT_CLS_CategoryHierarchy {
  @TestVisible
  private static Integer maxLevels = 50;

  public void validate(
    List<AXF_OBJ_Category__c> categories,
    Map<Id, AXF_OBJ_Category__c> oldCategories
  ) {
    List<AXF_OBJ_Category__c> changed = new List<AXF_OBJ_Category__c>();
    Map<Id, Id> parentOf = new Map<Id, Id>();
    Set<Id> pending = new Set<Id>();
    for (AXF_OBJ_Category__c category : categories) {
      if (
        oldCategories != null &&
        category.Id != null &&
        oldCategories.get(category.Id).AXF_CAT_LKP_Parent__c ==
        category.AXF_CAT_LKP_Parent__c
      ) {
        continue;
      }
      if (category.Id != null) {
        parentOf.put(category.Id, category.AXF_CAT_LKP_Parent__c);
      }
      if (category.AXF_CAT_LKP_Parent__c == null) {
        continue;
      }
      if (category.AXF_CAT_LKP_Parent__c == category.Id) {
        category.AXF_CAT_LKP_Parent__c.addError(
          'Uma categoria não pode ser pai de si mesma.'
        );
        continue;
      }
      changed.add(category);
      pending.add(category.AXF_CAT_LKP_Parent__c);
    }

    Integer level = 0;
    while (!pending.isEmpty() && level < maxLevels) {
      Set<Id> next = new Set<Id>();
      for (AXF_OBJ_Category__c ancestor : [
        SELECT AXF_CAT_LKP_Parent__c
        FROM AXF_OBJ_Category__c
        WHERE Id IN :pending
        WITH SYSTEM_MODE
      ]) {
        if (!parentOf.containsKey(ancestor.Id)) {
          parentOf.put(ancestor.Id, ancestor.AXF_CAT_LKP_Parent__c);
          if (ancestor.AXF_CAT_LKP_Parent__c != null) {
            next.add(ancestor.AXF_CAT_LKP_Parent__c);
          }
        }
      }
      pending = next;
      level++;
    }
    Boolean tooDeep = !pending.isEmpty();

    for (AXF_OBJ_Category__c category : changed) {
      if (tooDeep || loopsBack(category, parentOf)) {
        category.AXF_CAT_LKP_Parent__c.addError(
          tooDeep
            ? 'Hierarquia de categorias profunda demais.'
            : 'Categoria pai inválida: a hierarquia ficaria circular.'
        );
      }
    }
  }

  public void blockDeleteWithChildren(List<AXF_OBJ_Category__c> categories) {
    Map<Id, AXF_OBJ_Category__c> byId = new Map<Id, AXF_OBJ_Category__c>(
      categories
    );
    for (AXF_OBJ_Category__c child : [
      SELECT AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE AXF_CAT_LKP_Parent__c IN :byId.keySet()
      WITH SYSTEM_MODE
    ]) {
      AXF_OBJ_Category__c parent = byId.get(child.AXF_CAT_LKP_Parent__c);
      if (!byId.containsKey(child.Id) && !parent.hasErrors()) {
        parent.addError(
          'Não é possível excluir uma categoria que possui subcategorias.'
        );
      }
    }
  }

  private Boolean loopsBack(
    AXF_OBJ_Category__c category,
    Map<Id, Id> parentOf
  ) {
    Id current = category.AXF_CAT_LKP_Parent__c;
    for (Integer i = 0; i <= maxLevels && current != null; i++) {
      if (current == category.Id) {
        return true;
      }
      current = parentOf.get(current);
    }
    return false;
  }
}
