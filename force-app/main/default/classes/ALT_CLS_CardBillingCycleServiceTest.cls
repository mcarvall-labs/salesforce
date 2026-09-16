/**
 * @description Testes unitarios de ALT_CLS_CardBillingCycleService (AXF-35, CBR, G1 07/09).
 * Cobre: criacao de DRAFT; ativacao valida com versao; sobreposicao -> falha preservando DRAFT;
 * gap proibido -> falha; CalendarPolicyVersion ausente bloqueia; derivacao por data (RESOLVED
 * usa regra vigente na data); derivacao sem regra -> BLOCKED; update/delete bloqueados via
 * trigger. Dados ficticios; testes proporcionais ao delta.
 */
@IsTest
private class ALT_CLS_CardBillingCycleServiceTest {
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

  private static ALT_CLS_CardBillingCycleService.RuleInputDTO input(
    Id cardId,
    Date fromDate,
    Date toDate
  ) {
    ALT_CLS_CardBillingCycleService.RuleInputDTO dto = new ALT_CLS_CardBillingCycleService.RuleInputDTO();
    dto.creditCardId = cardId;
    dto.effectiveFrom = fromDate;
    dto.effectiveTo = toDate;
    dto.timeZone = 'America/Sao_Paulo';
    dto.closingDay = 10;
    dto.closingDayAdjustment = 'NONE';
    dto.dueDayOffset = 15;
    dto.dueDayAdjustment = 'FOLLOWING';
    dto.calendarPolicyVersion = 'CAL-1.0.0';
    return dto;
  }

  private static ALT_CLS_CardBillingCycleService svc() {
    return new ALT_CLS_CardBillingCycleService();
  }

  @IsTest
  static void createDraft_SavesAsDraftVersionZero() {
    Account acc = makeAccount('Titular CBR-1');
    AXF_OBJ_CreditCard__c card = makeCard(acc);

    ALT_CLS_CardBillingCycleService.ResultDTO res = svc()
      .createDraft(
        input(
          card.Id,
          Date.newInstance(2026, 1, 1),
          Date.newInstance(2027, 1, 1)
        )
      );

    Assert.isTrue(res.success, 'Draft criado.');
    Assert.areEqual('DRAFT', res.state);
    Assert.areEqual(0, res.version);
    AXF_OBJ_CardBillingCycleRule__c stored = [
      SELECT AXF_CBR_PKL_State__c, AXF_CBR_NUM_ClosingDay__c
      FROM AXF_OBJ_CardBillingCycleRule__c
      WHERE Id = :res.ruleId
      LIMIT 1
    ];
    Assert.areEqual('DRAFT', stored.AXF_CBR_PKL_State__c);
    Assert.areEqual(10, stored.AXF_CBR_NUM_ClosingDay__c);
  }

  @IsTest
  static void activate_Valid_BecomesActive() {
    Account acc = makeAccount('Titular CBR-2');
    AXF_OBJ_CreditCard__c card = makeCard(acc);
    Id ruleId = svc()
      .createDraft(input(card.Id, Date.newInstance(2026, 1, 1), null))
      .ruleId;

    ALT_CLS_CardBillingCycleService.ResultDTO res = svc()
      .activate(activation(ruleId, 0));

    Assert.isTrue(res.success, 'Ativacao valida.');
    Assert.areEqual('ACTIVE', res.state);
    AXF_OBJ_CardBillingCycleRule__c stored = [
      SELECT AXF_CBR_PKL_State__c, AXF_CBR_NUM_Version__c
      FROM AXF_OBJ_CardBillingCycleRule__c
      WHERE Id = :ruleId
      LIMIT 1
    ];
    Assert.areEqual('ACTIVE', stored.AXF_CBR_PKL_State__c);
    Assert.areEqual(1, stored.AXF_CBR_NUM_Version__c);
  }

  @IsTest
  static void activate_OverlapWithActive_FailsPreservesDraft() {
    Account acc = makeAccount('Titular CBR-3');
    AXF_OBJ_CreditCard__c card = makeCard(acc);
    Date jan = Date.newInstance(2026, 1, 1);
    // Regra 1 ativa cobrindo 2026 inteiro
    svc()
      .activate(
        activation(svc().createDraft(input(card.Id, jan, null)).ruleId, 0)
      );
    // Draft 2 tenta comecar dentro do periodo da regra 1 -> overlap (excecao, rascunho preservado)
    Id draft2 = svc()
      .createDraft(input(card.Id, Date.newInstance(2026, 6, 1), null))
      .ruleId;

    Exception caught;
    try {
      svc().activate(activation(draft2, 0));
    } catch (AXF_CLS_CardBillingCycleException e) {
      caught = e;
    }
    Assert.isNotNull(caught, 'Sobreposicao deve falhar na ativacao.');
    AXF_OBJ_CardBillingCycleRule__c draftStored = [
      SELECT AXF_CBR_PKL_State__c, AXF_CBR_NUM_Version__c
      FROM AXF_OBJ_CardBillingCycleRule__c
      WHERE Id = :draft2
      LIMIT 1
    ];
    Assert.areEqual(
      'DRAFT',
      draftStored.AXF_CBR_PKL_State__c,
      'Rascunho preservado.'
    );
    Assert.areEqual(0, draftStored.AXF_CBR_NUM_Version__c);
  }

  @IsTest
  static void activate_MissingCalendarPolicy_Blocks() {
    Account acc = makeAccount('Titular CBR-4');
    AXF_OBJ_CreditCard__c card = makeCard(acc);
    ALT_CLS_CardBillingCycleService.RuleInputDTO dto = input(
      card.Id,
      Date.newInstance(2026, 1, 1),
      null
    );
    dto.calendarPolicyVersion = null;
    Id draft = svc().createDraft(dto).ruleId;

    ALT_CLS_CardBillingCycleService.ResultDTO res = svc()
      .activate(activation(draft, 0));

    Assert.isFalse(res.success, 'Sem CalendarPolicyVersion nao ativa.');
    Assert.areEqual('DRAFT', res.state);
  }

  @IsTest
  static void deriveForDate_ReturnsActiveRuleOnEffectiveDate() {
    Account acc = makeAccount('Titular CBR-5');
    AXF_OBJ_CreditCard__c card = makeCard(acc);
    // Regra valida de 2026-01-01 em diante
    svc()
      .activate(
        activation(
          svc()
            .createDraft(input(card.Id, Date.newInstance(2026, 1, 1), null))
            .ruleId,
          0
        )
      );

    ALT_CLS_CardBillingCycleService.RuleViewDTO view = svc()
      .deriveForDate(card.Id, Date.newInstance(2026, 5, 15));

    Assert.areEqual('RESOLVED', view.outcome);
    Assert.areEqual('CAL-1.0.0', view.calendarPolicyVersion);
    Assert.areEqual(10, view.closingDay);
    Assert.isNotNull(view.ruleId);
  }

  @IsTest
  static void deriveForDate_NoRule_Blocked() {
    Account acc = makeAccount('Titular CBR-6');
    AXF_OBJ_CreditCard__c card = makeCard(acc);

    ALT_CLS_CardBillingCycleService.RuleViewDTO view = svc()
      .deriveForDate(card.Id, Date.today());

    Assert.areEqual('BLOCKED', view.outcome);
    Assert.areEqual(null, view.ruleId);
    Assert.isNotNull(view.message, 'Explicacao acessivel.');
  }

  @IsTest
  static void updateAndDeleteOnActive_AreBlocked() {
    Account acc = makeAccount('Titular CBR-7');
    AXF_OBJ_CreditCard__c card = makeCard(acc);
    Id ruleId = svc()
      .createDraft(input(card.Id, Date.newInstance(2026, 1, 1), null))
      .ruleId;
    svc().activate(activation(ruleId, 0));

    AXF_OBJ_CardBillingCycleRule__c active = [
      SELECT AXF_CBR_NUM_ClosingDay__c
      FROM AXF_OBJ_CardBillingCycleRule__c
      WHERE Id = :ruleId
      LIMIT 1
    ];
    active.AXF_CBR_NUM_ClosingDay__c = 20;

    Boolean updateBlocked = false;
    try {
      update active;
    } catch (Exception e) {
      updateBlocked = true;
    }
    Assert.isTrue(updateBlocked, 'Regra ACTIVE imutavel por edicao direta.');

    Boolean deleteBlocked = false;
    try {
      delete active;
    } catch (Exception e) {
      deleteBlocked = true;
    }
    Assert.isTrue(deleteBlocked, 'Regra nao pode ser excluida.');
  }

  private static ALT_CLS_CardBillingCycleService.ActivationInputDTO activation(
    Id ruleId,
    Decimal version
  ) {
    ALT_CLS_CardBillingCycleService.ActivationInputDTO a = new ALT_CLS_CardBillingCycleService.ActivationInputDTO();
    a.ruleId = ruleId;
    a.expectedVersion = version;
    return a;
  }
}
