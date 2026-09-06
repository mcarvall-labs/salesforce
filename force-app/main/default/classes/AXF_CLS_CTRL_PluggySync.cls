/**
 * @description Aura/LWC surface for the Pluggy transaction sync (AXF-12): trigger an
 * on-demand run and read the per-scope health. Both enforce AXF_CanConfigure and native
 * sharing/CRUD/FLS through the service; errors reach the client sanitized.
 */
public with sharing class AXF_CLS_CTRL_PluggySync {
  @AuraEnabled
  public static String syncNow(Id connectionId) {
    try {
      AXF_CLS_PluggySyncService svc = new AXF_CLS_PluggySyncService();
      List<AXF_CLS_PluggySyncService.ClaimedScope> scopes = svc.claimScopes(
        connectionId
      );
      if (scopes.isEmpty()) {
        return 'Nada a sincronizar agora: nenhuma conta ou cartao com titular confirmado, ou ja ha uma sincronizacao em andamento.';
      }
      System.enqueueJob(new AXF_CLS_PluggySyncQueueable(scopes));
      return scopes.size() +
        ' escopo(s) em sincronizacao. Acompanhe pelo painel de saude.';
    } catch (AXF_CLS_PluggyCollectionBlockedException e) {
      throw new AuraHandledException(e.getMessage());
    } catch (AXF_CLS_PluggyConfigException e) {
      throw new AuraHandledException(e.getMessage());
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_PluggySyncService.HealthRow> health(
    Id connectionId
  ) {
    try {
      return new AXF_CLS_PluggySyncService().health(connectionId);
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
