@IsTest
private class ALT_CLS_PluggyConnectionSummaryTest {
  @TestSetup
  static void setup() {
    ALT_CLS_ConnectionTestUser.create('axfdash');
  }

  private static void connection(Id holderId, String item, String status) {
    insert new AXF_OBJ_PluggyConnection__c(
      AXF_CON_MD_Holder__c = holderId,
      AXF_CON_PKL_Institution__c = '341',
      AXF_CON_EXI_PluggyItemId__c = item,
      AXF_CON_PKL_Status__c = status
    );
  }

  private static User dashboardUser() {
    return ALT_CLS_ConnectionTestUser.find('axfdash');
  }

  @IsTest
  static void summarizeCountsByStatus() {
    System.runAs(dashboardUser()) {
      Account holder = new Account(Name = 'Holder');
      insert holder;
      connection(holder.Id, 'a', 'Active');
      connection(holder.Id, 'b', 'Active');
      connection(holder.Id, 'c', 'Error');
      connection(holder.Id, 'd', 'Paused');
      ALT_CLS_PluggyConnectionSummary.Summary s = new ALT_CLS_PluggyConnectionSummary()
        .summarize();
      System.assertEquals(2, s.active);
      System.assertEquals(1, s.error);
      System.assertEquals(1, s.paused);
      System.assertEquals(4, s.rows.size());
      System.assertEquals('Holder', s.rows[0].holder);
      System.assert(s.rows[0].institution.contains('341'));
    }
  }

  @IsTest
  static void summarizeIsEmptyWithoutConnections() {
    System.runAs(dashboardUser()) {
      System.assertEquals(
        0,
        new ALT_CLS_PluggyConnectionSummary().summarize().rows.size()
      );
    }
  }
}
