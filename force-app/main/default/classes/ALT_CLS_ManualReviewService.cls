/** @description Administrative manual-entry follow-up. Never applies financial matching effects. */
public with sharing class ALT_CLS_ManualReviewService {
  /** @description Bulk producer used inside the entry creation transaction. */
  public void recordEntries(List<AXF_OBJ_FinancialTransaction__c> entries) {
    if (entries == null || entries.isEmpty())
      return;
    List<ALT_CLS_ReviewQueueService.CreateInputDTO> inputs = new List<ALT_CLS_ReviewQueueService.CreateInputDTO>();
    for (AXF_OBJ_FinancialTransaction__c entry : entries) {
      ALT_CLS_ReviewQueueService.CreateInputDTO input = new ALT_CLS_ReviewQueueService.CreateInputDTO();
      input.type = 'MANUAL_CONFIRMATION';
      input.reviewKey = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf('AXF-17:' + entry.Id))
      );
      input.financialTransactionId = entry.Id;
      input.accountId = entry.AXF_FTX_LKP_Account__c;
      inputs.add(input);
    }
    for (
      ALT_CLS_ReviewQueueService.ResultDTO result : new ALT_CLS_ReviewQueueService()
        .createItems(inputs)
    ) {
      if (!result.success)
        throw new AXF_CLS_ReviewQueueException(
          'Manual review could not be recorded.'
        );
    }
  }
  /** @description Reads only the administrative producer through the common access checks. */
  public List<ALT_CLS_ReviewQueueService.ReviewViewDTO> listPending() {
    return new ALT_CLS_ReviewQueueService()
      .listOpenByType('MANUAL_CONFIRMATION');
  }
  /** @description Confirms once using the common locking, replay and evidence protocol. */
  public ALT_CLS_ReviewQueueService.ResultDTO confirm(
    Id itemId,
    Decimal version,
    String note
  ) {
    ALT_CLS_ReviewQueueService queue = new ALT_CLS_ReviewQueueService();
    ALT_CLS_ReviewQueueService.ReviewViewDTO item = queue.open(itemId);
    if (item == null || item.type != 'MANUAL_CONFIRMATION')
      throw new AXF_CLS_ReviewQueueException('Manual item unavailable.');
    ALT_CLS_ReviewQueueService.ResolveInputDTO input = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    input.reviewItemId = itemId;
    input.expectedVersion = version;
    input.note = note;
    input.decision = 'RESOLVED';
    return queue.resolve(input);
  }
}
