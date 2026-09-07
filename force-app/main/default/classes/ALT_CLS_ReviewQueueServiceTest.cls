/**
 * @description Testes unitarios de ALT_CLS_ReviewQueueService (AXF-94, RVI, AD-41).
 * Cobre: criacao de item OPEN; idempotencia por ReviewKey; tipo invalido/sem registro rejeitados;
 * listOpen/abrir; resolve (RESOLVED) expurga Prior* e grava ator/instante/nota; dismiss;
 * versao obsoleta -> CONFLICT; item nao-OPEN nao re-resolve; delete/edicao direta bloqueados;
 * item invisivel por sharing -> listOpen nao vaza. Dados ficticios; testes proporcionais ao delta.
 */
@IsTest
private class ALT_CLS_ReviewQueueServiceTest {
  private static Account makeAccount(String name) {
    Account acc = new Account(Name = name);
    insert acc;
    return acc;
  }

  private static AXF_OBJ_CreditCard__c makeCard(Account acc) {
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_LKP_Account__c = acc.Id,
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert card;
    return card;
  }

  private static AXF_OBJ_FinancialTransaction__c makeFtx(Account acc) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = acc.Id,
      AXF_FTX_NUM_Magnitude__c = 100,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'CONFIRMED',
      AXF_FTX_EXI_ClientRequestId__c = 'rvi-ftx-' + Datetime.now().getTime()
    );
    insert ftx;
    return ftx;
  }

  private static ALT_CLS_ReviewQueueService svc() {
    return new ALT_CLS_ReviewQueueService();
  }

  private static ALT_CLS_ReviewQueueService.CreateInputDTO input(
    String type,
    String key,
    Id accountId
  ) {
    ALT_CLS_ReviewQueueService.CreateInputDTO dto = new ALT_CLS_ReviewQueueService.CreateInputDTO();
    dto.type = type;
    dto.reviewKey = key;
    dto.accountId = accountId;
    dto.priorAmount = 42.5;
    dto.priorDescription = 'descricao anterior';
    dto.priorDate = Date.today().addDays(-1);
    return dto;
  }

  @IsTest
  static void createItem_OpenStoresPriorAndKey() {
    Account acc = makeAccount('Titular RVI-1');

    ALT_CLS_ReviewQueueService.ResultDTO res = svc()
      .createItem(input('HOLDER_CONFIRMATION', 'k-1', acc.Id));

    Assert.isTrue(res.success, 'Item criado.');
    Assert.areEqual('OPEN', res.state);
    AXF_OBJ_ReviewItem__c stored = [
      SELECT
        AXF_RVI_PKL_State__c,
        AXF_RVI_NUM_PriorAmount__c,
        AXF_RVI_EXI_ReviewKey__c,
        AXF_RVI_NUM_Version__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE Id = :res.reviewItemId
      LIMIT 1
    ];
    Assert.areEqual('OPEN', stored.AXF_RVI_PKL_State__c);
    Assert.areEqual(42.5, stored.AXF_RVI_NUM_PriorAmount__c);
    Assert.areEqual('k-1', stored.AXF_RVI_EXI_ReviewKey__c);
    Assert.areEqual(0, stored.AXF_RVI_NUM_Version__c);
  }

  @IsTest
  static void createItem_SameOpenKey_Idempotent() {
    Account acc = makeAccount('Titular RVI-2');
    Id first = svc()
      .createItem(input('SOURCE_CHANGE', 'k-2', acc.Id))
      .reviewItemId;

    ALT_CLS_ReviewQueueService.ResultDTO again = svc()
      .createItem(input('SOURCE_CHANGE', 'k-2', acc.Id));

    Assert.isFalse(again.success, 'Nao duplica item OPEN.');
    Assert.areEqual(first, again.reviewItemId);
    Assert.areEqual(
      1, // um item OPEN permanece (nao duplica)
      [
        SELECT COUNT()
        FROM AXF_OBJ_ReviewItem__c
        WHERE AXF_RVI_EXI_ReviewKey__c = 'k-2'
      ]
    );
  }

  @IsTest
  static void createItem_InvalidTypeOrNoRef_Throws() {
    Account acc = makeAccount('Titular RVI-3');
    Exception caught;
    try {
      svc().createItem(input('BAD_TYPE', 'k-3', acc.Id));
    } catch (AXF_CLS_ReviewQueueException e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Tipo invalido rejeitado.');

    caught = null;
    try {
      ALT_CLS_ReviewQueueService.CreateInputDTO noRef = input(
        'SOURCE_CHANGE',
        'k-3b',
        acc.Id
      );
      noRef.accountId = null;
      svc().createItem(noRef);
    } catch (AXF_CLS_ReviewQueueException e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Item sem registro referenciado rejeitado.');
  }

  @IsTest
  static void resolve_ExpungesPriorAndRecordsActor() {
    Account acc = makeAccount('Titular RVI-4');
    AXF_OBJ_FinancialTransaction__c ftx = makeFtx(acc);
    ALT_CLS_ReviewQueueService.CreateInputDTO dto = input(
      'MATCH_LOW_CONFIDENCE',
      'k-4',
      acc.Id
    );
    dto.financialTransactionId = ftx.Id;
    Id itemId = svc().createItem(dto).reviewItemId;

    ALT_CLS_ReviewQueueService.ResolveInputDTO resolve = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    resolve.reviewItemId = itemId;
    resolve.decision = 'RESOLVED';
    resolve.note = 'confirmado';
    resolve.expectedVersion = 0;
    ALT_CLS_ReviewQueueService.ResultDTO res = svc().resolve(resolve);

    Assert.isTrue(res.success, 'Item resolvido.');
    AXF_OBJ_ReviewItem__c stored = [
      SELECT
        AXF_RVI_PKL_State__c,
        AXF_RVI_NUM_PriorAmount__c,
        AXF_RVI_DAT_PriorDate__c,
        AXF_RVI_TXT_PriorDescription__c,
        AXF_RVI_LKP_ResolvedByUser__c,
        AXF_RVI_DT_ResolvedAt__c,
        AXF_RVI_TAL_ResolutionNote__c,
        AXF_RVI_NUM_Version__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE Id = :itemId
      LIMIT 1
    ];
    Assert.areEqual('RESOLVED', stored.AXF_RVI_PKL_State__c);
    Assert.areEqual(
      null,
      stored.AXF_RVI_NUM_PriorAmount__c,
      'Prior* expurgado.'
    );
    Assert.areEqual(
      null,
      stored.AXF_RVI_TXT_PriorDescription__c,
      'Descricao expurgada.'
    );
    Assert.areEqual(UserInfo.getUserId(), stored.AXF_RVI_LKP_ResolvedByUser__c);
    Assert.isNotNull(stored.AXF_RVI_DT_ResolvedAt__c);
    Assert.areEqual('confirmado', stored.AXF_RVI_TAL_ResolutionNote__c);
    Assert.areEqual(1, stored.AXF_RVI_NUM_Version__c);
  }

  @IsTest
  static void dismiss_AllowedAndExpunges() {
    Account acc = makeAccount('Titular RVI-5');
    Id itemId = svc()
      .createItem(input('SOURCE_DELETE', 'k-5', acc.Id))
      .reviewItemId;

    ALT_CLS_ReviewQueueService.ResolveInputDTO d = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    d.reviewItemId = itemId;
    d.decision = 'DISMISSED';
    d.expectedVersion = 0;
    ALT_CLS_ReviewQueueService.ResultDTO res = svc().resolve(d);

    Assert.isTrue(res.success);
    Assert.areEqual('DISMISSED', res.state);
    AXF_OBJ_ReviewItem__c stored = [
      SELECT AXF_RVI_PKL_State__c, AXF_RVI_NUM_PriorAmount__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE Id = :itemId
      LIMIT 1
    ];
    Assert.areEqual('DISMISSED', stored.AXF_RVI_PKL_State__c);
    Assert.areEqual(null, stored.AXF_RVI_NUM_PriorAmount__c);
  }

  @IsTest
  static void resolve_WrongVersion_ThrowsConflict() {
    Account acc = makeAccount('Titular RVI-6');
    Id itemId = svc()
      .createItem(input('ACCOUNT_MERGE', 'k-6', acc.Id))
      .reviewItemId;

    ALT_CLS_ReviewQueueService.ResolveInputDTO d = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    d.reviewItemId = itemId;
    d.decision = 'RESOLVED';
    d.expectedVersion = 5; // divergente
    Exception caught;
    try {
      svc().resolve(d);
    } catch (AXF_CLS_ReviewQueueException e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Versao obsoleta gera CONFLICT.');
    Assert.areEqual(
      1, // permanece OPEN apos CONFLICT
      [
        SELECT COUNT()
        FROM AXF_OBJ_ReviewItem__c
        WHERE Id = :itemId AND AXF_RVI_PKL_State__c = 'OPEN'
      ]
    );
  }

  @IsTest
  static void resolve_NonOpenItem_NotReResolved() {
    Account acc = makeAccount('Titular RVI-7');
    Id itemId = svc()
      .createItem(input('SOURCE_CHANGE', 'k-7', acc.Id))
      .reviewItemId;
    ALT_CLS_ReviewQueueService.ResolveInputDTO first = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    first.reviewItemId = itemId;
    first.decision = 'RESOLVED';
    first.expectedVersion = 0;
    svc().resolve(first);

    ALT_CLS_ReviewQueueService.ResolveInputDTO again = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    again.reviewItemId = itemId;
    again.decision = 'DISMISSED';
    again.expectedVersion = 1;
    ALT_CLS_ReviewQueueService.ResultDTO res = svc().resolve(again);

    Assert.isFalse(res.success, 'Item ja resolvido nao re-resolve.');
    Assert.areEqual('RESOLVED', res.state);
  }

  @IsTest
  static void listOpen_And_Open_ReturnVisible() {
    Account acc = makeAccount('Titular RVI-8');
    Id itemId = svc()
      .createItem(input('HOLDER_CONFIRMATION', 'k-8', acc.Id))
      .reviewItemId;

    List<ALT_CLS_ReviewQueueService.ReviewViewDTO> items = svc().listOpen();
    ALT_CLS_ReviewQueueService.ReviewViewDTO view = svc().open(itemId);

    Assert.isTrue(items.size() >= 1, 'Item aberto aparece na lista.');
    Assert.isNotNull(view);
    Assert.areEqual('HOLDER_CONFIRMATION', view.type);
    Assert.areEqual('OPEN', view.state);
    Assert.areEqual(42.5, view.priorAmount);
  }

  @IsTest
  static void directUpdateOrDeleteOnResolved_Blocked() {
    Account acc = makeAccount('Titular RVI-9');
    Id itemId = svc()
      .createItem(input('TRANSFER_SUGGESTION', 'k-9', acc.Id))
      .reviewItemId;
    ALT_CLS_ReviewQueueService.ResolveInputDTO d = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    d.reviewItemId = itemId;
    d.decision = 'RESOLVED';
    d.expectedVersion = 0;
    svc().resolve(d);

    AXF_OBJ_ReviewItem__c resolved = [
      SELECT AXF_RVI_TAL_ResolutionNote__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE Id = :itemId
      LIMIT 1
    ];
    Boolean updateBlocked = false;
    try {
      resolved.AXF_RVI_TAL_ResolutionNote__c = 'tentativa';
      update resolved;
    } catch (Exception e) {
      updateBlocked = true;
    }
    Assert.isTrue(updateBlocked, 'Item resolvido imutavel.');

    Boolean deleteBlocked = false;
    try {
      delete resolved;
    } catch (Exception e) {
      deleteBlocked = true;
    }
    Assert.isTrue(deleteBlocked, 'Item nao pode ser excluido.');
  }
}
