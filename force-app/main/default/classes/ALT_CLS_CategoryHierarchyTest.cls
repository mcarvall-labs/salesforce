@IsTest
private class ALT_CLS_CategoryHierarchyTest {
  @TestSetup
  static void setup() {
    ALT_CLS_ConnectionTestUser.create('axfcat');
  }

  private static AXF_OBJ_Category__c category(String name, Id parentId) {
    return new AXF_OBJ_Category__c(
      Name = name,
      AXF_CAT_PKL_Type__c = 'Expense',
      AXF_CAT_LKP_Parent__c = parentId
    );
  }

  private static Database.SaveResult tryUpdate(AXF_OBJ_Category__c record) {
    return Database.update(record, false);
  }

  @IsTest
  static void allowsUnlimitedDepth() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfcat')) {
      AXF_OBJ_Category__c parent = category('Moradia', null);
      insert parent;
      Id parentId = parent.Id;
      for (Integer i = 0; i < 6; i++) {
        AXF_OBJ_Category__c child = category('Nivel ' + i, parentId);
        insert child;
        parentId = child.Id;
      }
      System.assertEquals(
        7,
        [SELECT COUNT() FROM AXF_OBJ_Category__c WHERE Name LIKE 'Nivel%' OR Name = 'Moradia']
      );
    }
  }

  @IsTest
  static void blocksSelfParent() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfcat')) {
      AXF_OBJ_Category__c root = category('Lazer', null);
      insert root;
      root.AXF_CAT_LKP_Parent__c = root.Id;
      System.assert(!tryUpdate(root).isSuccess());
    }
  }

  @IsTest
  static void blocksIndirectCycle() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfcat')) {
      AXF_OBJ_Category__c a = category('A', null);
      insert a;
      AXF_OBJ_Category__c b = category('B', a.Id);
      insert b;
      AXF_OBJ_Category__c c = category('C', b.Id);
      insert c;
      a.AXF_CAT_LKP_Parent__c = c.Id;
      Database.SaveResult result = tryUpdate(a);
      System.assert(!result.isSuccess());
      System.assert(result.getErrors()[0].getMessage().contains('circular'));
    }
  }

  @IsTest
  static void allowsReparentingWithoutCycle() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfcat')) {
      AXF_OBJ_Category__c a = category('A', null);
      AXF_OBJ_Category__c b = category('B', null);
      insert new List<AXF_OBJ_Category__c>{ a, b };
      AXF_OBJ_Category__c child = category('Filha', a.Id);
      insert child;
      child.AXF_CAT_LKP_Parent__c = b.Id;
      System.assert(tryUpdate(child).isSuccess());
    }
  }

  @IsTest
  static void blocksCycleInsideBulkUpdate() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfcat')) {
      AXF_OBJ_Category__c a = category('A', null);
      AXF_OBJ_Category__c b = category('B', null);
      insert new List<AXF_OBJ_Category__c>{ a, b };
      a.AXF_CAT_LKP_Parent__c = b.Id;
      b.AXF_CAT_LKP_Parent__c = a.Id;
      List<Database.SaveResult> results = Database.update(
        new List<AXF_OBJ_Category__c>{ a, b },
        false
      );
      System.assert(!results[0].isSuccess());
      System.assert(!results[1].isSuccess());
    }
  }

  @IsTest
  static void blocksDeleteOfParentWithChildren() {
    AXF_OBJ_Category__c parent = category('Pai', null);
    insert parent;
    AXF_OBJ_Category__c child = category('Filha', parent.Id);
    insert child;
    Database.DeleteResult blocked = Database.delete(parent, false);
    System.assert(!blocked.isSuccess());
    System.assert(blocked.getErrors()[0].getMessage().contains('subcategorias'));
    System.assert(Database.delete(child, false).isSuccess());
    System.assert(Database.delete(parent, false).isSuccess());
  }

  @IsTest
  static void allowsSwappingParentAndChildInOneBatch() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfcat')) {
      AXF_OBJ_Category__c a = category('A', null);
      insert a;
      AXF_OBJ_Category__c b = category('B', a.Id);
      insert b;
      a.AXF_CAT_LKP_Parent__c = b.Id;
      b.AXF_CAT_LKP_Parent__c = null;
      for (
        Database.SaveResult result : Database.update(
          new List<AXF_OBJ_Category__c>{ a, b },
          false
        )
      ) {
        System.assert(result.isSuccess());
      }
    }
  }

  @IsTest
  static void rejectsChainDeeperThanTheLimit() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfcat')) {
      ALT_CLS_CategoryHierarchy.maxLevels = 3;
      Id parentId = null;
      for (Integer i = 0; i < 4; i++) {
        AXF_OBJ_Category__c node = category('N' + i, parentId);
        insert node;
        parentId = node.Id;
      }
      Database.SaveResult result = Database.insert(
        category('Fundo', parentId),
        false
      );
      System.assert(!result.isSuccess());
      System.assert(result.getErrors()[0].getMessage().contains('profunda'));
    }
  }

  @IsTest
  static void deepChainRejectsOnlyItsOwnRecordInABatch() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfcat')) {
      ALT_CLS_CategoryHierarchy.maxLevels = 3;
      Id parentId = null;
      for (Integer i = 0; i < 4; i++) {
        AXF_OBJ_Category__c node = category('N' + i, parentId);
        insert node;
        parentId = node.Id;
      }
      AXF_OBJ_Category__c root = category('Raiz', null);
      insert root;
      List<Database.SaveResult> results = Database.insert(
        new List<AXF_OBJ_Category__c>{
          category('Fundo', parentId),
          category('Raso', root.Id)
        },
        false
      );
      System.assert(!results[0].isSuccess());
      System.assert(results[1].isSuccess());
    }
  }

  @IsTest
  static void allowsDeletingASubtreeInOneBatch() {
    AXF_OBJ_Category__c parent = category('Pai', null);
    insert parent;
    AXF_OBJ_Category__c child = category('Filha', parent.Id);
    insert child;
    for (
      Database.DeleteResult result : Database.delete(
        new List<AXF_OBJ_Category__c>{ parent, child },
        false
      )
    ) {
      System.assert(result.isSuccess());
    }
  }
}
