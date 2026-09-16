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

  @AuraEnabled
  public static AXF_CLS_PluggyDiscoveryService.RegisterResult registerConnection(
    String pluggyItemId
  ) {
    try {
      return new AXF_CLS_PluggyDiscoveryService()
        .registerConnection(pluggyItemId);
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      throw new AuraHandledException(e.getMessage());
    } catch (AXF_CLS_PluggyIntegrationException e) {
      // Auth/config failure (e.g. External Credential not provisioned) — surface the
      // sanitized message so it is not shown as a generic internal error.
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_PluggyDiscoveryService.ConnectionOverviewDTO> getConnections() {
    return new AXF_CLS_PluggyDiscoveryService().overview();
  }

  @AuraEnabled
  public static AXF_CLS_PluggyDiscoveryService.UpdateReferencesResult updateReferences(
    Id connectionId,
    Id bankInstitutionId,
    Id holderId
  ) {
    try {
      return new AXF_CLS_PluggyDiscoveryService()
        .updateReferences(connectionId, bankInstitutionId, holderId);
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static AXF_CLS_PluggyDiscoveryService.DeleteResult deleteConnection(
    Id connectionId
  ) {
    try {
      return new AXF_CLS_PluggyDiscoveryService()
        .deleteConnection(connectionId);
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  // Primitive params so the LWC call binds reliably (Aura does not populate an
  // @AuraEnabled parameter typed as an inner class of another top-level class).
  @AuraEnabled
  public static ALT_CLS_BankInstitution.SaveResult createBankInstitution(
    String name,
    String bankNumber
  ) {
    ALT_CLS_BankInstitution.SaveInput input = new ALT_CLS_BankInstitution.SaveInput();
    input.name = name;
    input.bankNumber = bankNumber;
    return new ALT_CLS_BankInstitution().save(input);
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
    } catch (AXF_CLS_PluggyIntegrationException e) {
      // Auth/config failure before any item lookup — return a clean terminal DTO with the
      // sanitized message instead of leaking an unhandled exception.
      AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = new AXF_CLS_PluggyDiscoveryService.DiscoveryResult();
      r.connectionId = connectionId;
      r.state = 'FAILED_TERMINAL';
      r.complete = false;
      r.message = e.getMessage();
      return r;
    }
  }
}
