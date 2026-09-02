/**
 * @description Dedicated controller for aXF_LWC_sourceDiscovery (PROJECT_RULES §3). Thin:
 * validates authority via the service, returns typed DTOs, never a stack trace or a
 * secret/account number. AXF-84.
 */
public with sharing class AXF_CLS_CTRL_SourceDiscovery {
  @AuraEnabled(cacheable=true)
  public static AXF_CLS_PluggyDiscoveryService.DiscoveryResult getStatus(
    Id connectionId
  ) {
    return new AXF_CLS_PluggyDiscoveryService().status(connectionId);
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_PluggyDiscoveryService.DiscoveredSourceDTO> getDiscovered(
    Id connectionId
  ) {
    return new AXF_CLS_PluggyDiscoveryService().discovered(connectionId);
  }

  @AuraEnabled
  public static AXF_CLS_PluggyDiscoveryService.DiscoveryResult startDiscovery(
    Id connectionId
  ) {
    try {
      return new AXF_CLS_PluggyDiscoveryService().startOrResume(connectionId);
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = new AXF_CLS_PluggyDiscoveryService.DiscoveryResult();
      r.connectionId = connectionId;
      r.state = e.getMessage().startsWith('CONFLICT')
        ? 'RUNNING'
        : 'FAILED_RETRYABLE';
      r.complete = false;
      r.message = e.getMessage();
      return r;
    } catch (AXF_CLS_PluggyCollectionBlockedException e) {
      AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = new AXF_CLS_PluggyDiscoveryService.DiscoveryResult();
      r.connectionId = connectionId;
      r.state = 'FAILED_TERMINAL';
      r.complete = false;
      r.message = e.getMessage();
      return r;
    }
  }
}
