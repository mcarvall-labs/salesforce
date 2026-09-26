/**
 * @description Dedicated controller for aXF_LWC_sourceDiscovery over the legacy PROD model.
 * Thin: delegates to ALT_CLS_PluggySourceSetup (connections) and
 * ALT_CLS_ManualFinancialSource (bank institution directory); returns typed DTOs and
 * only sanitized messages (never a stack trace, secret or full Item ID).
 */
public with sharing class AXF_CLS_CTRL_SourceDiscovery {
  private static final String GENERIC_ERROR = 'Não foi possível concluir a operação. Tente novamente.';

  @AuraEnabled(cacheable=true)
  public static AXF_CLS_SourceSetupDTO.DiscoveryResult getStatus(
    Id connectionId
  ) {
    try {
      guard();
      return new ALT_CLS_PluggySourceSetup().status(connectionId);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  @AuraEnabled
  public static AXF_CLS_SourceSetupDTO.RegisterResult registerConnection(
    String pluggyItemId,
    Id bankInstitutionId
  ) {
    try {
      guard();
      return new ALT_CLS_PluggySourceSetup()
        .registerConnection(pluggyItemId, bankInstitutionId);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_SourceSetupDTO.ConnectionOverview> getConnections() {
    try {
      guard();
      return new ALT_CLS_PluggySourceSetup().overview();
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  @AuraEnabled
  public static AXF_CLS_SourceSetupDTO.UpdateReferencesResult updateReferences(
    Id connectionId,
    Id bankInstitutionId,
    Id holderId
  ) {
    try {
      guard();
      return new ALT_CLS_PluggySourceSetup()
        .updateReferences(connectionId, bankInstitutionId, holderId);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  @AuraEnabled
  public static AXF_CLS_SourceSetupDTO.DeleteResult deleteConnection(
    Id connectionId
  ) {
    try {
      guard();
      return new ALT_CLS_PluggySourceSetup().deleteConnection(connectionId);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  // Primitive params so the LWC call binds reliably (Aura does not populate an
  // @AuraEnabled parameter typed as an inner class of another top-level class).
  @AuraEnabled
  public static AXF_CLS_SourceSetupDTO.BankInstitutionResult createBankInstitution(
    String name,
    String bankNumber
  ) {
    return new ALT_CLS_ManualFinancialSource()
      .createBankInstitution(name, bankNumber);
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_SourceSetupDTO.DiscoveredSource> getDiscovered(
    Id connectionId
  ) {
    try {
      guard();
      return new ALT_CLS_PluggySourceSetup().discovered(connectionId);
    } catch (Exception e) {
      throw auraError(e);
    }
  }

  @AuraEnabled
  public static AXF_CLS_SourceSetupDTO.DiscoveryResult startDiscovery(
    Id connectionId
  ) {
    return new ALT_CLS_PluggySourceSetup().startOrResume(connectionId);
  }

  // Test-only hook to exercise the sanitized error path of every read/write.
  @TestVisible
  private static Boolean simulateFailure = false;

  private static void guard() {
    if (simulateFailure) {
      throw new DmlException('Simulated failure');
    }
  }

  @TestVisible
  private static AuraHandledException auraError(Exception e) {
    String message = e instanceof ALT_CLS_PluggySourceSetup.SourceSetupException
      ? e.getMessage()
      : GENERIC_ERROR;
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
