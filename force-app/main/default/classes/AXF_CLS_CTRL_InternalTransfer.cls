/**
 * @description Controller exclusivo do LWC aXF_LWC_internalTransfer (AXF-32). Erros sanitizados
 * como {code}; nunca stack trace, PII ou existencia de registros nao autorizados.
 */
public with sharing class AXF_CLS_CTRL_InternalTransfer {
  public class Context {
    @AuraEnabled
    public Boolean canConfirm;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public List<String> reasons;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      Context result = new Context();
      result.canConfirm = FeatureManagement.checkPermission(
        ALT_CLS_InternalTransferService.CP_CONFIRM
      );
      result.policyVersion = ALT_CLS_InternalTransferService.POLICY_VERSION;
      result.reasons = ALT_CLS_InternalTransferService.REASONS;
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  /** @description Pending TRANSFER_SUGGESTION items with both legs, redacted per-record. */
  @AuraEnabled
  public static List<ALT_CLS_InternalTransferService.TransferView> listPending() {
    try {
      ALT_CLS_InternalTransferService.requireAccess();
      List<ALT_CLS_ReviewQueueService.ReviewViewDTO> items = new ALT_CLS_ReviewQueueService()
        .listOpenByType('TRANSFER_SUGGESTION');
      List<ALT_CLS_InternalTransferService.TransferView> result = new List<ALT_CLS_InternalTransferService.TransferView>();
      ALT_CLS_InternalTransferService service = new ALT_CLS_InternalTransferService();
      for (ALT_CLS_ReviewQueueService.ReviewViewDTO item : items) {
        if (item.internalTransferId == null) {
          continue;
        }
        try {
          ALT_CLS_InternalTransferService.TransferView view = service.read(
            item.internalTransferId
          );
          view.reviewItemId = item.reviewItemId;
          result.add(view);
        } catch (ALT_CLS_InternalTransferService.TransferException denied) {
          // Not accessible to this user: skip it silently, never reveal existence.
        }
      }
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_InternalTransferService.TransferView confirm(
    String request
  ) {
    try {
      return new ALT_CLS_InternalTransferService()
        .confirm(
          (ALT_CLS_InternalTransferService.ConfirmInput) parse(
            request,
            ALT_CLS_InternalTransferService.ConfirmInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_InternalTransferService.TransferView reverse(
    String request
  ) {
    try {
      return new ALT_CLS_InternalTransferService()
        .reverse(
          (ALT_CLS_InternalTransferService.ReverseInput) parse(
            request,
            ALT_CLS_InternalTransferService.ReverseInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Object parse(String request, Type shape) {
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_InternalTransferService.TransferException(
        'INVALID_INPUT'
      );
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code;
    if (failure instanceof ALT_CLS_InternalTransferService.TransferException) {
      code = failure.getMessage();
    } else if (
      failure instanceof QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    } else {
      code = 'UNEXPECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
