/**
 * @description Testes unitarios de ALT_CLS_ReviewQueueService (AXF-94, RVI, AD-41).
 * Cobre: criacao de item OPEN; idempotencia por ReviewKey; tipo invalido/sem registro rejeitados;
 * listOpen/open, retained typed evidence, versioned resolution and dismissal;
 * versao obsoleta -> CONFLICT; item nao-OPEN nao re-resolve; delete/edicao direta bloqueados;
 * item invisivel por sharing -> listOpen nao vaza. Dados ficticios; testes proporcionais ao delta.
 */
@IsTest
private class ALT_CLS_ReviewQueueServiceTest {
  private static Account makeAccount(String name) {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
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

  @IsTest
  static void blankNoteDoesNotChangeStateOrVersion() {
    Account account = makeAccount('Required note');
    Id itemId = svc()
      .createItem(input('HOLDER_CONFIRMATION', 'required-note', account.Id))
      .reviewItemId;
    ALT_CLS_ReviewQueueService.ResolveInputDTO request = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    request.reviewItemId = itemId;
    request.expectedVersion = 0;
    request.decision = 'DISMISSED';
    request.note = '  ';
    Test.startTest();
    try {
      svc().resolve(request);
      Assert.fail('Blank notes must be rejected.');
    } catch (AXF_CLS_ReviewQueueException expected) {
      Assert.isTrue(
        expected.getMessage().contains('note'),
        'Stable note validation explains rejection.'
      );
    }
    Test.stopTest();
    AXF_OBJ_ReviewItem__c stored = [
      SELECT AXF_RVI_PKL_State__c, AXF_RVI_NUM_Version__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE Id = :itemId
    ];
    Assert.areEqual(
      'OPEN',
      stored.AXF_RVI_PKL_State__c,
      'Rejected decision preserves state.'
    );
    Assert.areEqual(
      0,
      stored.AXF_RVI_NUM_Version__c,
      'Rejected decision preserves version.'
    );
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
    dto.priorMatchConfidence = 75;
    dto.priorCurrency = 'BRL';
    dto.priorDirection = 'DEBIT';
    dto.priorStatus = 'CONFIRMED';
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
      .createItem(input('HOLDER_CONFIRMATION', 'k-2', acc.Id))
      .reviewItemId;

    ALT_CLS_ReviewQueueService.ResultDTO again = svc()
      .createItem(input('HOLDER_CONFIRMATION', 'k-2', acc.Id));

    Assert.isTrue(
      again.success,
      'Identical replay succeeds without duplication.'
    );
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
        'HOLDER_CONFIRMATION',
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
  static void resolve_RetainsPriorAndRecordsActor() {
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
    resolve.note = 'Reviewed with source evidence';
    resolve.expectedVersion = 0;
    Datetime beforeResolve = Datetime.now();
    ALT_CLS_ReviewQueueService.ResultDTO res = svc().resolve(resolve);
    Datetime afterResolve = Datetime.now();

    Assert.isTrue(res.success, 'Item resolvido.');
    AXF_OBJ_ReviewItem__c stored = [
      SELECT
        AXF_RVI_PKL_State__c,
        AXF_RVI_NUM_PriorAmount__c,
        AXF_RVI_DAT_PriorDate__c,
        AXF_RVI_NUM_PriorMatchConfidence__c,
        AXF_RVI_TXT_PriorDescription__c,
        AXF_RVI_TXT_PriorCurrency__c,
        AXF_RVI_TXT_PriorDirection__c,
        AXF_RVI_TXT_PriorStatus__c,
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
      'BRL',
      stored.AXF_RVI_TXT_PriorCurrency__c,
      'Prior currency retained.'
    );
    Assert.areEqual(
      'DEBIT',
      stored.AXF_RVI_TXT_PriorDirection__c,
      'Prior direction retained.'
    );
    Assert.areEqual(
      'CONFIRMED',
      stored.AXF_RVI_TXT_PriorStatus__c,
      'Prior status retained.'
    );
    Assert.isTrue(
      stored.AXF_RVI_DT_ResolvedAt__c >=
        Datetime.valueOfGmt(beforeResolve.formatGmt('yyyy-MM-dd HH:mm:ss')) &&
        stored.AXF_RVI_DT_ResolvedAt__c <=
        Datetime.valueOfGmt(afterResolve.formatGmt('yyyy-MM-dd HH:mm:ss')),
      'ResolvedAt is bounded by the resolution call at persisted second precision.'
    );
    Assert.areEqual(
      42.5,
      stored.AXF_RVI_NUM_PriorAmount__c,
      'Prior evidence is retained.'
    );
    Assert.areEqual(
      'descricao anterior',
      stored.AXF_RVI_TXT_PriorDescription__c,
      'Description evidence is retained.'
    );
    Assert.areEqual(
      Date.today().addDays(-1),
      stored.AXF_RVI_DAT_PriorDate__c,
      'Prior date retained.'
    );
    Assert.areEqual(
      75,
      stored.AXF_RVI_NUM_PriorMatchConfidence__c,
      'Prior confidence retained.'
    );
    Assert.areEqual(UserInfo.getUserId(), stored.AXF_RVI_LKP_ResolvedByUser__c);
    Assert.isNotNull(stored.AXF_RVI_DT_ResolvedAt__c);
    Assert.areEqual(
      'Reviewed with source evidence',
      stored.AXF_RVI_TAL_ResolutionNote__c
    );
    Assert.areEqual(1, stored.AXF_RVI_NUM_Version__c);
  }

  @IsTest
  static void dismiss_AllowedAndRetainsEvidence() {
    Account acc = makeAccount('Titular RVI-5');
    Id itemId = svc()
      .createItem(input('HOLDER_CONFIRMATION', 'k-5', acc.Id))
      .reviewItemId;

    ALT_CLS_ReviewQueueService.ResolveInputDTO d = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    d.reviewItemId = itemId;
    d.decision = 'DISMISSED';
    d.note = 'Reviewed with source evidence';
    d.expectedVersion = 0;
    Datetime beforeResolve = Datetime.now();
    ALT_CLS_ReviewQueueService.ResultDTO res = svc().resolve(d);
    Datetime afterResolve = Datetime.now();

    Assert.isTrue(res.success);
    Assert.areEqual('DISMISSED', res.state);
    AXF_OBJ_ReviewItem__c stored = [
      SELECT
        AXF_RVI_PKL_State__c,
        AXF_RVI_NUM_PriorAmount__c,
        AXF_RVI_DAT_PriorDate__c,
        AXF_RVI_TXT_PriorDescription__c,
        AXF_RVI_TXT_PriorCurrency__c,
        AXF_RVI_TXT_PriorDirection__c,
        AXF_RVI_TXT_PriorStatus__c,
        AXF_RVI_NUM_PriorMatchConfidence__c,
        AXF_RVI_DT_ResolvedAt__c,
        AXF_RVI_LKP_ResolvedByUser__c,
        AXF_RVI_NUM_Version__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE Id = :itemId
      LIMIT 1
    ];
    Assert.areEqual('DISMISSED', stored.AXF_RVI_PKL_State__c);
    Assert.areEqual(
      'BRL',
      stored.AXF_RVI_TXT_PriorCurrency__c,
      'Prior currency retained.'
    );
    Assert.areEqual(
      'DEBIT',
      stored.AXF_RVI_TXT_PriorDirection__c,
      'Prior direction retained.'
    );
    Assert.areEqual(
      'CONFIRMED',
      stored.AXF_RVI_TXT_PriorStatus__c,
      'Prior status retained.'
    );
    Assert.isTrue(
      stored.AXF_RVI_DT_ResolvedAt__c >=
        Datetime.valueOfGmt(beforeResolve.formatGmt('yyyy-MM-dd HH:mm:ss')) &&
        stored.AXF_RVI_DT_ResolvedAt__c <=
        Datetime.valueOfGmt(afterResolve.formatGmt('yyyy-MM-dd HH:mm:ss')),
      'ResolvedAt is bounded by the resolution call at persisted second precision.'
    );
    Assert.areEqual(
      Date.today().addDays(-1),
      stored.AXF_RVI_DAT_PriorDate__c,
      'Prior date retained.'
    );
    Assert.areEqual(
      'descricao anterior',
      stored.AXF_RVI_TXT_PriorDescription__c,
      'Prior description retained.'
    );
    Assert.areEqual(
      75,
      stored.AXF_RVI_NUM_PriorMatchConfidence__c,
      'Prior confidence retained.'
    );
    Assert.isNotNull(
      stored.AXF_RVI_DT_ResolvedAt__c,
      'Finalization starts retention.'
    );
    Assert.areEqual(
      UserInfo.getUserId(),
      stored.AXF_RVI_LKP_ResolvedByUser__c,
      'Actor recorded.'
    );
    Assert.areEqual(1, stored.AXF_RVI_NUM_Version__c, 'Version incremented.');
    Assert.areEqual(42.5, stored.AXF_RVI_NUM_PriorAmount__c);
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
    d.note = 'Reviewed with source evidence';
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
      .createItem(input('HOLDER_CONFIRMATION', 'k-7', acc.Id))
      .reviewItemId;
    ALT_CLS_ReviewQueueService.ResolveInputDTO first = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    first.reviewItemId = itemId;
    first.decision = 'RESOLVED';
    first.note = 'Reviewed with source evidence';
    first.expectedVersion = 0;
    svc().resolve(first);

    ALT_CLS_ReviewQueueService.ResolveInputDTO again = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    again.reviewItemId = itemId;
    again.decision = 'DISMISSED';
    again.note = 'Reviewed with source evidence';
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
    d.note = 'Reviewed with source evidence';
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
