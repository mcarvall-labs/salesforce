/**
 * LWC controller for the AXF-3 authorized context bar.
 */
public with sharing class AXF_CLS_CTRL_AuthorizedContext {
  /**
   * Returns the holder contexts authorized for the running user.
   * @return sanitized context DTOs; never a broader existence signal
   */
  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_AuthorizedContextService.ContextView> getContexts() {
    try {
      return AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    } catch (QueryException exceptionCause) {
      throw sanitizedAccessError();
    } catch (SecurityException exceptionCause) {
      throw sanitizedAccessError();
    }
  }

  private static AuraHandledException sanitizedAccessError() {
    return new AuraHandledException(
      'Não foi possível carregar os contextos autorizados.'
    );
  }
}
