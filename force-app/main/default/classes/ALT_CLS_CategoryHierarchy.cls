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
      if (
        category.AXF_CAT_LKP_Parent__c != null &&
        category.AXF_CAT_LKP_Parent__c == category.Id
      ) {
        category.AXF_CAT_LKP_Parent__c.addError(
          'Uma categoria não pode ser pai de si mesma.'
        );
        continue;
      }
      if (category.Id != null) {
        parentOf.put(category.Id, category.AXF_CAT_LKP_Parent__c);
      }
      if (category.AXF_CAT_LKP_Parent__c == null) {
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

    for (AXF_OBJ_Category__c category : changed) {
      String problem = chainProblem(category, parentOf);
      if (problem != null) {
        category.AXF_CAT_LKP_Parent__c.addError(problem);
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
      if (
        parent != null &&
        !byId.containsKey(child.Id) &&
        !parent.hasErrors()
      ) {
        parent.addError(
          'Não é possível excluir uma categoria que possui subcategorias.'
        );
      }
    }
  }

  /** Returns the error for this record's own chain, or null when the chain is fine. */
  private String chainProblem(
    AXF_OBJ_Category__c category,
    Map<Id, Id> parentOf
  ) {
    Id current = category.AXF_CAT_LKP_Parent__c;
    while (current != null) {
      if (current == category.Id) {
        return 'Categoria pai inválida: a hierarquia ficaria circular.';
      }
      if (!parentOf.containsKey(current)) {
        return 'Hierarquia de categorias profunda demais.';
      }
      current = parentOf.get(current);
    }
    return null;
  }
}
