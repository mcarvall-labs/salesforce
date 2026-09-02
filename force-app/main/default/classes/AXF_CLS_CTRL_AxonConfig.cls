/**
 * @description Access model for the "AXON - Configuration" hub (AXF-91).
 *
 * The hub only routes to capabilities already delivered — it holds no business
 * logic and duplicates no service. Each area's own controller enforces its
 * authority and contracts on the server; this method only tells the client which
 * tiles to render so a hidden tile is never mistaken for authorization (AC1).
 *
 * - `canConfigure` (AXF_CanConfigure) unlocks the administrative areas: Pluggy
 *   credentials, titulares, vínculos/responsáveis, pessoas/acessos, fontes
 *   manuais, retomar configuração, saúde das fontes.
 * - Every authenticated Axon user may open the personal display-currency
 *   preference (AXF-87) — scoped to their own preference by that capability (AC6).
 *
 * AXF-91.
 */
public with sharing class AXF_CLS_CTRL_AxonConfig {
  @TestVisible
  private static Boolean canConfigureOverride;

  public class Access {
    @AuraEnabled
    public Boolean canConfigure = false;
    @AuraEnabled
    public Boolean canSetCurrency = true;
  }

  @AuraEnabled(cacheable=true)
  public static Access access() {
    Access a = new Access();
    a.canConfigure = canConfigureOverride != null
      ? canConfigureOverride
      : FeatureManagement.checkPermission('AXF_CanConfigure');
    a.canSetCurrency = true;
    return a;
  }
}
