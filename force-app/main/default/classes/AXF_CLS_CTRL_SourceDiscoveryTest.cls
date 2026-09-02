/**
 * @description AXF-84. The controller surfaces status/sources and turns a blocked or
 * conflicting discovery into a clean DTO instead of an exception.
 */
@IsTest
private class AXF_CLS_CTRL_SourceDiscoveryTest {
  static AXF_OBJ_PluggyConnection__c conn() {
    return AXF_CLS_PluggyTestData.connection('ITEM_A');
  }

  @IsTest
  static void startDiscoverySucceedsThroughController() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(
      c.Id
    );
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state);
    System.assertEquals(
      2,
      AXF_CLS_CTRL_SourceDiscovery.getDiscovered(c.Id).size()
    );
    System.assertEquals(
      'SUCCEEDED',
      AXF_CLS_CTRL_SourceDiscovery.getStatus(c.Id).state
    );
  }

  @IsTest
  static void blockedDiscoveryReturnsTerminalDto() {
    AXF_OBJ_PluggyConnection__c c = conn();
    c.AXF_CON_PKL_ConsentState__c = 'REVOKED';
    update c;
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;

    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(
      c.Id
    );
    System.assertEquals('FAILED_TERMINAL', r.state);
    System.assertEquals(false, r.complete);
  }

  @IsTest
  static void unauthorizedReturnsRetryableDto() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = false;

    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(
      c.Id
    );
    System.assertEquals(false, r.complete);
    System.assert(r.message.containsIgnoreCase('autoriza'));
  }
}
