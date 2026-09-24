/**
 * @description AXF-156 — financiamentos e parcelamentos com prazo definido ("Financiamentos").
 * Capacidade de negócio sobre o motor de cronogramas AXF-103: lista os cronogramas PRICE, SAC e
 * INSTALLMENT do contexto autorizado (sem contrato) com progresso (parcelas pagas/total), próximo
 * vencimento e saldo devedor; detalha as parcelas filhas (persistidas e virtuais até o total);
 * edita o valor da parcela de um parcelamento, encerra e quita antecipadamente pelos comandos da
 * porta única `ALT_CLS_FinancialScheduleService`, que só alteram parcelas futuras não realizadas.
 * Grupos legados da AXF-20 (lançamentos com `ScheduleGroupKey`, sem cronograma) aparecem somente
 * leitura, com o progresso calculado sobre as linhas existentes.
 *
 * Paga = alocação líquida ≥ obrigação (base corrente, ou magnitude), ou lançamento CONFIRMED.
 * Saldo devedor: PRICE/SAC = `ClosingBalance` da última parcela paga (ou o principal se nenhuma);
 * INSTALLMENT = soma das parcelas não pagas e não canceladas, inclusive as virtuais; quitado = 0.
 *
 * Leituras em USER_MODE dentro do escopo de `AXF_CLS_AuthorizedContextService`; comandos exigem o
 * mesmo gate de gestão da AXF-155 (Gestor). Falhas são códigos estáveis (`FinancingException`).
 */
public with sharing class ALT_CLS_FinancingService {
  public static final String STATE_ACTIVE = 'ACTIVE';
  public static final String STATE_ENDED = 'ENDED';
  /** Encerrado por quitação antecipada. */
  public static final String STATE_SETTLED = 'SETTLED';
  public static final String INST_PAID = 'PAID';
  public static final String INST_PARTIAL = 'PARTIAL';
  public static final String INST_PLANNED = 'PLANNED';
  public static final String INST_CANCELLED = 'CANCELLED';
  public static final String METHOD_PRICE = 'PRICE';
  public static final String METHOD_SAC = 'SAC';
  public static final String METHOD_INSTALLMENT = 'INSTALLMENT';
  public static final String CODE_INVALID = 'INVALID_INPUT';
  public static final String CODE_NOT_ACCESSIBLE = 'NOT_ACCESSIBLE';
  public static final String CODE_NOT_ALLOWED = 'NOT_ALLOWED';
  public static final String CODE_CONFLICT = 'CONFLICT';
  public static final String CODE_UNAVAILABLE = 'UNAVAILABLE';
  public static final String CODE_REJECTED = 'REJECTED';
  public static final Integer MAX_FINANCINGS = 200;
  /** Teto de linhas persistidas lidas pela lista; acima dele o progresso fica não verificado. */
  public static final Integer MAX_LIST_ROWS = 20000;
  public static final Integer MAX_LEGACY_ROWS = 5000;
  /** Teto de parcelas avaliadas por financiamento (o mesmo do motor de projeção). */
  public static final Integer MAX_INSTALLMENTS = ALT_CLS_ScheduleProjection.MAX_EVALUATED_SEQUENCES;
  public static final Set<String> METHODS = new Set<String>{
    METHOD_PRICE,
    METHOD_SAC,
    METHOD_INSTALLMENT
  };
  private static final Set<String> SUCCESS = new Set<String>{
    ALT_CLS_FinancialScheduleService.OUTCOME_UPDATED,
    ALT_CLS_FinancialScheduleService.OUTCOME_TERMINATED,
    ALT_CLS_FinancialScheduleService.OUTCOME_REPLAY
  };

  @TestVisible
  private static Boolean canManageOverride;

  public class FinancingException extends Exception {
  }

  public class FinancingView {
    public Id scheduleId;
    /** Chave do grupo legado AXF-20 (somente leitura); nula nos cronogramas gerenciados. */
    public String legacyKey;
    public Boolean legacy = false;
    public Id holderId;
    public String holderLabel;
    public String description;
    /** PRICE | SAC | INSTALLMENT */
    public String method;
    public String direction;
    public String currencyIsoCode;
    public Decimal principal;
    public Integer totalInstallments;
    public Integer paidCount = 0;
    public Date nextDueDate;
    public Decimal nextAmount;
    public Decimal outstandingBalance;
    /** ACTIVE | ENDED | SETTLED */
    public String state;
    public Date terminationDate;
    /** Vencimento da última parcela persistida: limite superior do encerramento. */
    public Date lastDueDate;
    public Long version;
    public Id settlementTransactionId;
    /** Editar valor: só parcelamento ativo gerenciado. */
    public Boolean canEdit = false;
    /** Encerrar e quitar: cronograma ativo gerenciado. */
    public Boolean canChange = false;
    /** O status de alguma parcela não pôde ser verificado pelas alocações visíveis. */
    public Boolean unverified = false;
  }

  public class InstallmentView {
    public Id transactionId;
    public Integer sequence;
    public Date dueDate;
    public Decimal amount;
    public Decimal principalPortion;
    public Decimal interestPortion;
    public Decimal closingBalance;
    /** PAID | PARTIAL | PLANNED | CANCELLED */
    public String status;
    /** Parcela ainda não materializada (projeção). */
    public Boolean projected = false;
    /** Valor ainda devido (valor menos alocação líquida); zero se paga ou cancelada. */
    public Decimal residual;
  }

  public class DetailView {
    public FinancingView financing;
    public List<InstallmentView> installments = new List<InstallmentView>();
    public Boolean truncated = false;
    public Boolean unverified = false;
  }

  public class DetailQuery {
    public Id scheduleId;
    public String legacyKey;
  }

  public class SettlementQuery {
    public Id scheduleId;
    public String legacyKey;
    /** Data da quitação para a sugestão; padrão hoje. */
    public Date settlementDate;
  }

  public class SettlementPreview {
    public Id scheduleId;
    /** Saldo devedor sem juros futuros (regra da lista); ajustável pelo usuário. */
    public Decimal suggestedAmount;
    public Date minDate;
    public Date maxDate;
    /** Data para a qual o valor sugerido foi calculado. */
    public Date settlementDate;
    public String currencyIsoCode;
    public Long version;
  }

  public class EditRequest {
    public Id scheduleId;
    public String legacyKey;
    public Decimal amount;
    public Long expectedVersion;
    public String operationKey;
  }

  public class TerminateRequest {
    public Id scheduleId;
    public String legacyKey;
    /** Padrão: hoje. */
    public Date terminationDate;
    public Long expectedVersion;
    public String operationKey;
  }

  public class SettleRequest {
    public Id scheduleId;
    public String legacyKey;
    public Decimal amount;
    public Date settlementDate;
    public Long expectedVersion;
    public String operationKey;
  }

  public class CommandResult {
    public Id scheduleId;
    public Boolean replay = false;
    /** Parcelas atualizadas (editar) ou canceladas (encerrar/quitar). */
    public Integer changedCount = 0;
    public Integer protectedCount = 0;
    public Id settlementTransactionId;
  }

  /** Estado calculado de um financiamento: parcelas, progresso, saldo. */
  private class Summary {
    List<InstallmentView> installments = new List<InstallmentView>();
    Boolean unverified = false;
  }

  // ------------------------------------------------------------ capacidades

  /** @description Editar, encerrar e quitar: mesmo gate de gestão da AXF-155 (Gestor). */
  public Boolean canManage() {
    if (canManageOverride != null) {
      return canManageOverride;
    }
    return ALT_CLS_FinancialScheduleService.canChangeSchedules();
  }

  // ------------------------------------------------------------ leitura

  public List<FinancingView> listFinancings() {
    Map<Id, String> holders = holderLabels();
    List<FinancingView> result = new List<FinancingView>();
    if (holders.isEmpty()) {
      return result;
    }
    List<AXF_OBJ_FinancialSchedule__c> roots = scheduleRows(
      holders.keySet(),
      null
    );
    if (!roots.isEmpty()) {
      Set<Id> scheduleIds = new Map<Id, AXF_OBJ_FinancialSchedule__c>(roots)
        .keySet();
      Map<Id, List<AXF_OBJ_ScheduleDefinition__c>> definitions = definitionsBySchedule(
        scheduleIds
      );
      Integer probe = MAX_LIST_ROWS + 1;
      List<AXF_OBJ_FinancialTransaction__c> rows = Database.queryWithBinds(
        installmentSoql('AXF_FTX_LKP_Schedule__c IN :scheduleIds') +
        ' ORDER BY AXF_FTX_LKP_Schedule__c, AXF_FTX_NUM_Sequence__c LIMIT :probe',
        new Map<String, Object>{
          'scheduleIds' => scheduleIds,
          'probe' => probe
        },
        AccessLevel.USER_MODE
      );
      Boolean cut = rows.size() > MAX_LIST_ROWS;
      if (cut) {
        rows.remove(rows.size() - 1);
      }
      Map<Id, List<AXF_OBJ_FinancialTransaction__c>> bySchedule = new Map<Id, List<AXF_OBJ_FinancialTransaction__c>>();
      for (AXF_OBJ_FinancialTransaction__c row : rows) {
        Id key = row.AXF_FTX_LKP_Schedule__c;
        if (!bySchedule.containsKey(key)) {
          bySchedule.put(key, new List<AXF_OBJ_FinancialTransaction__c>());
        }
        bySchedule.get(key).add(row);
      }
      Set<Id> unverified = new Set<Id>();
      Map<Id, Decimal> nets = nets(
        new Map<Id, AXF_OBJ_FinancialTransaction__c>(rows).keySet(),
        unverified
      );
      Map<Id, Id> settlements = settlements(scheduleIds);
      for (AXF_OBJ_FinancialSchedule__c root : roots) {
        List<AXF_OBJ_FinancialTransaction__c> own = bySchedule.containsKey(
            root.Id
          )
          ? bySchedule.get(root.Id)
          : new List<AXF_OBJ_FinancialTransaction__c>();
        FinancingView view = managedView(
          root,
          definitions.get(root.Id),
          own,
          nets,
          unverified,
          settlements.get(root.Id),
          holders
        );
        view.unverified = view.unverified || cut;
        result.add(view);
      }
    }
    result.addAll(legacyViews(holders, null));
    return result;
  }

  public DetailView detail(DetailQuery query) {
    check(query != null, CODE_INVALID);
    check(
      (query.scheduleId == null) != String.isBlank(query.legacyKey),
      CODE_INVALID
    );
    Map<Id, String> holders = holderLabels();
    DetailView detail = new DetailView();
    if (!String.isBlank(query.legacyKey)) {
      List<Summary> summaries = new List<Summary>();
      List<FinancingView> views = legacyViews(
        holders,
        query.legacyKey.trim(),
        summaries
      );
      check(views.size() == 1, CODE_NOT_ACCESSIBLE);
      detail.financing = views[0];
      detail.installments = summaries[0].installments;
      detail.unverified = summaries[0].unverified;
      return detail;
    }
    AXF_OBJ_FinancialSchedule__c root = requireFinancing(
      query.scheduleId,
      holders
    );
    Summary summary = new Summary();
    detail.financing = loadManaged(root, holders, summary);
    detail.installments = summary.installments;
    detail.unverified = summary.unverified;
    detail.truncated =
      detail.financing.totalInstallments != null &&
      summary.installments.size() < detail.financing.totalInstallments &&
      summary.installments.size() >= MAX_INSTALLMENTS;
    return detail;
  }

  /**
   * @description Prévia da quitação: valor sugerido = saldo devedor sem juros futuros e a janela de
   * datas aceita (hoje até o próximo vencimento não pago, ou o último persistido).
   */
  public SettlementPreview settlementPreview(SettlementQuery query) {
    check(query != null, CODE_INVALID);
    check(String.isBlank(query.legacyKey), CODE_NOT_ALLOWED);
    check(query.scheduleId != null, CODE_INVALID);
    Map<Id, String> holders = holderLabels();
    AXF_OBJ_FinancialSchedule__c root = requireFinancing(
      query.scheduleId,
      holders
    );
    check(canManage(), CODE_NOT_ALLOWED);
    Summary summary = new Summary();
    FinancingView view = loadManaged(root, holders, summary);
    check(view.canChange, CODE_NOT_ALLOWED);
    SettlementPreview preview = new SettlementPreview();
    preview.scheduleId = view.scheduleId;
    preview.minDate = today();
    preview.maxDate = settlementLimit(view);
    preview.settlementDate = query.settlementDate == null
      ? today()
      : query.settlementDate;
    check(
      preview.settlementDate >= preview.minDate &&
        preview.settlementDate <= preview.maxDate,
      CODE_INVALID
    );
    Decimal suggested = suggestedPayoff(
      view,
      summary.installments,
      preview.settlementDate
    );
    preview.suggestedAmount = (suggested != null &&
      suggested > 0)
      ? suggested
      : null;
    preview.currencyIsoCode = view.currencyIsoCode;
    preview.version = view.version;
    return preview;
  }

  // ------------------------------------------------------------ comandos

  public CommandResult editAmount(EditRequest request) {
    check(request != null, CODE_INVALID);
    FinancingView view = requireCommandTarget(
      request.scheduleId,
      request.legacyKey
    );
    Boolean replayOnly = endedRetry(view, request.operationKey);
    check(replayOnly || view.canEdit, CODE_NOT_ALLOWED);
    check(validAmount(request.amount), CODE_INVALID);
    check(request.expectedVersion != null, CODE_INVALID);
    check(validKey(request.operationKey), CODE_INVALID);
    ALT_CLS_FinancialScheduleService.ChangeInput input = new ALT_CLS_FinancialScheduleService.ChangeInput();
    input.scheduleId = request.scheduleId;
    input.amount = request.amount;
    input.expectedVersion = request.expectedVersion;
    input.operationKey = request.operationKey;
    return commandResult(
      ALT_CLS_FinancialScheduleService.editAmount(input),
      replayOnly
    );
  }

  public CommandResult terminate(TerminateRequest request) {
    check(request != null, CODE_INVALID);
    FinancingView view = requireCommandTarget(
      request.scheduleId,
      request.legacyKey
    );
    Boolean replayOnly = endedRetry(view, request.operationKey);
    check(replayOnly || view.canChange, CODE_NOT_ALLOWED);
    check(request.expectedVersion != null, CODE_INVALID);
    check(validKey(request.operationKey), CODE_INVALID);
    Date terminationDate = request.terminationDate == null
      ? today()
      : request.terminationDate;
    // Mesma janela da AXF-155: nem o passado (vencidas continuam obrigações), nem além da última
    // parcela persistida. Um reenvio sobre cronograma já encerrado vai direto à porta (replay).
    Date lastDue = view.lastDueDate;
    check(
      replayOnly ||
      (terminationDate >= today() &&
      terminationDate <=
      (lastDue == null || lastDue < today() ? today() : lastDue)),
      CODE_INVALID
    );
    ALT_CLS_FinancialScheduleService.ChangeInput input = new ALT_CLS_FinancialScheduleService.ChangeInput();
    input.scheduleId = request.scheduleId;
    input.terminationDate = terminationDate;
    input.expectedVersion = request.expectedVersion;
    input.operationKey = request.operationKey;
    return commandResult(
      ALT_CLS_FinancialScheduleService.terminateSchedule(input),
      replayOnly
    );
  }

  public CommandResult settle(SettleRequest request) {
    check(request != null, CODE_INVALID);
    FinancingView view = requireCommandTarget(
      request.scheduleId,
      request.legacyKey
    );
    Boolean replayOnly = endedRetry(view, request.operationKey);
    check(replayOnly || view.canChange, CODE_NOT_ALLOWED);
    check(validAmount(request.amount), CODE_INVALID);
    check(request.settlementDate != null, CODE_INVALID);
    check(request.expectedVersion != null, CODE_INVALID);
    check(validKey(request.operationKey), CODE_INVALID);
    check(
      replayOnly ||
      (request.settlementDate >= today() &&
      request.settlementDate <= settlementLimit(view)),
      CODE_INVALID
    );
    ALT_CLS_FinancialScheduleService.ChangeInput input = new ALT_CLS_FinancialScheduleService.ChangeInput();
    input.scheduleId = request.scheduleId;
    input.amount = request.amount;
    input.terminationDate = request.settlementDate;
    input.expectedVersion = request.expectedVersion;
    input.operationKey = request.operationKey;
    return commandResult(
      ALT_CLS_FinancialScheduleService.settleSchedule(input),
      replayOnly
    );
  }

  /**
   * @description Alvo de um comando: fora do contexto é NOT_ACCESSIBLE (inexistente e alheio são
   * indistinguíveis); sem gestão ou grupo legado é NOT_ALLOWED.
   */
  private FinancingView requireCommandTarget(Id scheduleId, String legacyKey) {
    Map<Id, String> holders = holderLabels();
    if (!String.isBlank(legacyKey)) {
      check(
        legacyViews(holders, legacyKey.trim()).size() == 1,
        CODE_NOT_ACCESSIBLE
      );
      throw new FinancingException(CODE_NOT_ALLOWED);
    }
    check(scheduleId != null, CODE_INVALID);
    AXF_OBJ_FinancialSchedule__c root = requireFinancing(scheduleId, holders);
    check(canManage(), CODE_NOT_ALLOWED);
    return loadManaged(root, holders, new Summary());
  }

  /**
   * @description Reenvio sobre cronograma já encerrado (por este mesmo comando): a porta resolve o
   * REPLAY pela identidade de operação; qualquer outro desfecho é NOT_ALLOWED (sem reativação).
   */
  private Boolean endedRetry(FinancingView view, String operationKey) {
    return view.state != STATE_ACTIVE &&
      canManage() &&
      !String.isBlank(operationKey);
  }

  private static CommandResult commandResult(
    ALT_CLS_FinancialScheduleService.ChangeResult changed,
    Boolean replayOnly
  ) {
    if (
      replayOnly &&
      changed.outcome != ALT_CLS_FinancialScheduleService.OUTCOME_REPLAY
    ) {
      throw new FinancingException(CODE_NOT_ALLOWED);
    }
    requireSuccess(changed.outcome);
    CommandResult result = new CommandResult();
    result.scheduleId = changed.scheduleId;
    result.replay = changed.replay == true;
    result.changedCount =
      (changed.updatedCount == null ? 0 : changed.updatedCount) +
      (changed.cancelledCount == null ? 0 : changed.cancelledCount);
    result.protectedCount = changed.protectedCount == null
      ? 0
      : changed.protectedCount;
    result.settlementTransactionId = changed.settlementTransactionId;
    return result;
  }

  /** @description Traduz o desfecho da porta de escrita num código estável da tela. */
  @TestVisible
  private static void requireSuccess(String outcome) {
    if (SUCCESS.contains(outcome)) {
      return;
    }
    String code;
    switch on outcome {
      when 'INVALID' {
        code = CODE_INVALID;
      }
      when 'UNSUPPORTED' {
        code = CODE_NOT_ALLOWED;
      }
      when 'FORBIDDEN', 'NOT_FOUND' {
        code = CODE_NOT_ACCESSIBLE;
      }
      when 'CONFLICT' {
        code = CODE_CONFLICT;
      }
      when 'UNAVAILABLE' {
        code = CODE_UNAVAILABLE;
      }
      when else {
        code = CODE_REJECTED;
      }
    }
    throw new FinancingException(code);
  }

  // ------------------------------------------------------------ cálculo

  /** @description Um financiamento gerenciado, lido por completo (detalhe e comandos). */
  private FinancingView loadManaged(
    AXF_OBJ_FinancialSchedule__c root,
    Map<Id, String> holders,
    Summary summary
  ) {
    Set<Id> scheduleIds = new Set<Id>{ root.Id };
    Integer probe = MAX_INSTALLMENTS + 1;
    List<AXF_OBJ_FinancialTransaction__c> rows = Database.queryWithBinds(
      installmentSoql('AXF_FTX_LKP_Schedule__c IN :scheduleIds') +
      ' ORDER BY AXF_FTX_NUM_Sequence__c LIMIT :probe',
      new Map<String, Object>{ 'scheduleIds' => scheduleIds, 'probe' => probe },
      AccessLevel.USER_MODE
    );
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(
      new Map<Id, AXF_OBJ_FinancialTransaction__c>(rows).keySet(),
      unverified
    );
    List<AXF_OBJ_ScheduleDefinition__c> definitions = definitionsBySchedule(
        scheduleIds
      )
      .get(root.Id);
    return managedView(
      root,
      definitions,
      rows,
      nets,
      unverified,
      settlements(scheduleIds).get(root.Id),
      holders,
      summary
    );
  }

  private FinancingView managedView(
    AXF_OBJ_FinancialSchedule__c root,
    List<AXF_OBJ_ScheduleDefinition__c> definitions,
    List<AXF_OBJ_FinancialTransaction__c> rows,
    Map<Id, Decimal> nets,
    Set<Id> unverified,
    Id settlementId,
    Map<Id, String> holders
  ) {
    return managedView(
      root,
      definitions,
      rows,
      nets,
      unverified,
      settlementId,
      holders,
      new Summary()
    );
  }

  private FinancingView managedView(
    AXF_OBJ_FinancialSchedule__c root,
    List<AXF_OBJ_ScheduleDefinition__c> definitions,
    List<AXF_OBJ_FinancialTransaction__c> rows,
    Map<Id, Decimal> nets,
    Set<Id> unverified,
    Id settlementId,
    Map<Id, String> holders,
    Summary summary
  ) {
    AXF_OBJ_ScheduleDefinition__c active = root.AXF_FSC_LKP_ActiveDefinition__r;
    Map<String, Object> canonical = ALT_CLS_FinancialScheduleService.canonicalInputOf(
      active
    );
    FinancingView view = new FinancingView();
    view.scheduleId = root.Id;
    view.holderId = root.AXF_FSC_LKP_Account__c;
    view.holderLabel = holders.get(root.AXF_FSC_LKP_Account__c);
    view.description = (String) canonical.get(
      ALT_CLS_FinancialScheduleService.INPUT_DESCRIPTION
    );
    view.method = active.AXF_SDF_PKL_Method__c;
    view.direction = root.AXF_FSC_PKL_Direction__c;
    view.currencyIsoCode = root.AXF_FSC_TXT_CurrencyIsoCode__c;
    view.principal = active.AXF_SDF_NUM_Principal__c;
    view.totalInstallments = intOf(active.AXF_SDF_NUM_TotalInstallments__c);
    view.terminationDate = root.AXF_FSC_DAT_TerminationDate__c;
    view.version = root.AXF_FSC_NUM_Version__c == null
      ? 0
      : root.AXF_FSC_NUM_Version__c.longValue();
    view.settlementTransactionId = settlementId;
    view.state = root.AXF_FSC_PKL_State__c == STATE_ACTIVE
      ? STATE_ACTIVE
      : (settlementId != null ? STATE_SETTLED : STATE_ENDED);
    view.canChange = view.state == STATE_ACTIVE && canManage();
    view.canEdit = view.canChange && view.method == METHOD_INSTALLMENT;

    Map<Integer, AXF_OBJ_FinancialTransaction__c> persisted = new Map<Integer, AXF_OBJ_FinancialTransaction__c>();
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      persisted.put(row.AXF_FTX_NUM_Sequence__c.intValue(), row);
      if (
        row.AXF_FTX_DAT_DueDate__c != null &&
        (view.lastDueDate == null ||
        row.AXF_FTX_DAT_DueDate__c > view.lastDueDate)
      ) {
        view.lastDueDate = row.AXF_FTX_DAT_DueDate__c;
      }
    }
    Integer trackingStart = root.AXF_FSC_NUM_TrackingStartSequence__c == null
      ? 1
      : root.AXF_FSC_NUM_TrackingStartSequence__c.intValue();
    Integer first = intOf(active.AXF_SDF_NUM_FirstSequence__c);
    Integer last = (first == null ||
      view.totalInstallments == null)
      ? trackingStart - 1
      : first + view.totalInstallments - 1;
    last = Math.min(last, trackingStart + MAX_INSTALLMENTS - 1);
    Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>> formulas = new Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>>();
    List<AXF_OBJ_ScheduleDefinition__c> revisions = (definitions == null)
      ? new List<AXF_OBJ_ScheduleDefinition__c>{ active }
      : definitions;

    for (Integer sequence = trackingStart; sequence <= last; sequence++) {
      AXF_OBJ_FinancialTransaction__c row = persisted.get(sequence);
      InstallmentView line = (row == null)
        ? virtualLine(revisions, sequence, formulas, view.terminationDate)
        : persistedLine(row, nets.get(row.Id));
      if (line == null) {
        continue;
      }
      if (row != null && unverified.contains(row.Id)) {
        summary.unverified = true;
      }
      summary.installments.add(line);
    }
    view.unverified = summary.unverified;
    applyProgress(view, summary.installments, nets);
    return view;
  }

  /** @description Parcela virtual (além da janela): mesma definição vigente e fórmula do motor. */
  private static InstallmentView virtualLine(
    List<AXF_OBJ_ScheduleDefinition__c> definitions,
    Integer sequence,
    Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>> formulas,
    Date terminationDate
  ) {
    AXF_OBJ_ScheduleDefinition__c definition = ALT_CLS_ScheduleProjection.effectiveDefinition(
      definitions,
      sequence
    );
    if (definition == null) {
      return null;
    }
    List<ALT_CLS_AmortizationSchedule.Occurrence> formula = formulas.get(
      definition.Id
    );
    if (formula == null) {
      formula = ALT_CLS_ScheduleProjection.generateOccurrences(definition);
      formulas.put(definition.Id, formula);
    }
    Integer first = intOf(definition.AXF_SDF_NUM_FirstSequence__c);
    Integer index = sequence - (first == null ? 1 : first);
    if (index < 0 || index >= formula.size()) {
      return null;
    }
    ALT_CLS_AmortizationSchedule.Occurrence occurrence = formula[index];
    InstallmentView line = new InstallmentView();
    line.sequence = sequence;
    line.projected = true;
    try {
      line.dueDate = ALT_CLS_ScheduleCalendar.nominalDueDate(
        definition.AXF_SDF_DAT_FirstDueDate__c,
        first == null ? 1 : first,
        intOf(definition.AXF_SDF_NUM_PeriodMonths__c),
        intOf(definition.AXF_SDF_NUM_PeriodDays__c),
        intOf(definition.AXF_SDF_NUM_AnchorDay__c),
        sequence
      );
    } catch (ALT_CLS_ScheduleCalendar.CalendarException invalid) {
      return null;
    }
    line.amount = occurrence.payment;
    Boolean calculated =
      definition.AXF_SDF_PKL_Method__c == METHOD_PRICE ||
      definition.AXF_SDF_PKL_Method__c == METHOD_SAC;
    if (calculated) {
      line.principalPortion = occurrence.principalPortion;
      line.interestPortion = occurrence.interestPortion;
      line.closingBalance = occurrence.closingBalance;
    }
    // Predicado do encerramento: parcelas virtuais após a data estão logicamente canceladas.
    line.status = (terminationDate != null &&
      line.dueDate > terminationDate)
      ? INST_CANCELLED
      : INST_PLANNED;
    return line;
  }

  private static InstallmentView persistedLine(
    AXF_OBJ_FinancialTransaction__c row,
    Decimal net
  ) {
    InstallmentView line = new InstallmentView();
    line.transactionId = row.Id;
    line.sequence = row.AXF_FTX_NUM_Sequence__c == null
      ? null
      : row.AXF_FTX_NUM_Sequence__c.intValue();
    line.dueDate = row.AXF_FTX_DAT_DueDate__c;
    line.amount = row.AXF_FTX_NUM_CurrentBasis__c != null
      ? row.AXF_FTX_NUM_CurrentBasis__c
      : row.AXF_FTX_NUM_Magnitude__c;
    Boolean calculated =
      row.AXF_FTX_PKL_Modality__c == METHOD_PRICE ||
      row.AXF_FTX_PKL_Modality__c == METHOD_SAC;
    if (calculated) {
      line.principalPortion = row.AXF_FTX_NUM_PrincipalPortion__c;
      line.interestPortion = row.AXF_FTX_NUM_InterestPortion__c;
      line.closingBalance = row.AXF_FTX_NUM_ClosingBalance__c;
    }
    line.status = installmentStatus(row, line.amount, net);
    return line;
  }

  /**
   * @description Paga quando as alocações líquidas cobrem a obrigação ou o lançamento está
   * CONFIRMED; parcial com alocação menor; cancelada pelo encerramento; prevista no restante.
   */
  @TestVisible
  private static String installmentStatus(
    AXF_OBJ_FinancialTransaction__c row,
    Decimal obligation,
    Decimal net
  ) {
    if (row.AXF_FTX_PKL_ScheduleState__c == INST_CANCELLED) {
      return INST_CANCELLED;
    }
    if (row.AXF_FTX_PKL_Status__c == 'CONFIRMED') {
      return INST_PAID;
    }
    if (net != null && net > 0) {
      return (obligation != null &&
        net >= obligation)
        ? INST_PAID
        : INST_PARTIAL;
    }
    return INST_PLANNED;
  }

  /**
   * @description Progresso, próximo vencimento e saldo devedor a partir das parcelas calculadas.
   * PRICE/SAC: `ClosingBalance` da parcela imediatamente anterior à primeira não paga (principal se a
   * primeira não está paga; saldo da última paga se nenhuma resta). INSTALLMENT: soma das não pagas e
   * não canceladas (residual das parciais). Quitado: só as parcelas não pagas que continuaram devidas
   * (vencimento até a data da quitação) e o vencimento mais antigo delas.
   */
  private static void applyProgress(
    FinancingView view,
    List<InstallmentView> installments,
    Map<Id, Decimal> nets
  ) {
    Date today = today();
    Decimal lastPaidClosing;
    Decimal beforeFirstUnpaid;
    Boolean foundUnpaid = false;
    Boolean first = true;
    Decimal previousClosing;
    Decimal remaining = 0;
    InstallmentView earliestUnpaid;
    view.paidCount = 0;
    for (InstallmentView line : installments) {
      line.residual = 0;
      if (line.status == INST_PAID) {
        view.paidCount++;
        if (line.closingBalance != null) {
          lastPaidClosing = line.closingBalance;
        }
      } else if (line.status != INST_CANCELLED) {
        Decimal net = (line.transactionId == null)
          ? null
          : nets.get(line.transactionId);
        line.residual = Math.max(
          (line.amount == null ? 0 : line.amount) -
          (net == null || net < 0 ? 0 : net),
          0
        );
        remaining += line.residual;
        if (!foundUnpaid) {
          foundUnpaid = true;
          beforeFirstUnpaid = first ? view.principal : previousClosing;
        }
        if (earliestUnpaid == null) {
          earliestUnpaid = line;
        }
        if (
          view.nextDueDate == null &&
          line.dueDate != null &&
          line.dueDate >= today
        ) {
          view.nextDueDate = line.dueDate;
          view.nextAmount = line.amount;
        }
      }
      previousClosing = line.closingBalance;
      first = false;
    }
    if (view.state == STATE_SETTLED) {
      view.outstandingBalance = remaining.setScale(2);
      view.nextDueDate = earliestUnpaid == null ? null : earliestUnpaid.dueDate;
      view.nextAmount = earliestUnpaid == null ? null : earliestUnpaid.amount;
      return;
    }
    if (view.state != STATE_ACTIVE) {
      view.nextDueDate = null;
      view.nextAmount = null;
    }
    Decimal balance;
    if (view.method == METHOD_PRICE || view.method == METHOD_SAC) {
      balance = foundUnpaid
        ? beforeFirstUnpaid
        : (lastPaidClosing != null ? lastPaidClosing : view.principal);
      if (balance == null) {
        balance = remaining;
      }
    } else {
      balance = remaining;
    }
    view.outstandingBalance = balance.setScale(2);
  }

  /**
   * @description Quitação sugerida para a data, sem juros futuros e sem contar de novo o que continua
   * devido: parcelas com vencimento até a data permanecem obrigações (o TERMINATE só cancela as
   * posteriores). PRICE/SAC = `ClosingBalance` da última parcela com vencimento até a data (paga ou
   * não; principal se nenhuma); INSTALLMENT = soma das parcelas posteriores não pagas e não canceladas.
   */
  @TestVisible
  private static Decimal suggestedPayoff(
    FinancingView view,
    List<InstallmentView> installments,
    Date settlementDate
  ) {
    Boolean calculated =
      view.method == METHOD_PRICE ||
      view.method == METHOD_SAC;
    Decimal closing = view.principal;
    Decimal after = 0;
    for (InstallmentView line : installments) {
      if (line.dueDate == null) {
        continue;
      }
      if (line.dueDate <= settlementDate) {
        if (line.closingBalance != null) {
          closing = line.closingBalance;
        }
      } else if (line.residual != null) {
        after += line.residual;
      }
    }
    Decimal suggested = calculated ? closing : after;
    return suggested == null ? null : suggested.setScale(2);
  }

  /** @description Limite da data de quitação: próximo vencimento não pago, ou o último persistido. */
  private static Date settlementLimit(FinancingView view) {
    Date limitDate = view.nextDueDate != null
      ? view.nextDueDate
      : view.lastDueDate;
    return (limitDate == null || limitDate < today()) ? today() : limitDate;
  }

  // ------------------------------------------------------------ legados

  private List<FinancingView> legacyViews(
    Map<Id, String> holders,
    String legacyKey
  ) {
    return legacyViews(holders, legacyKey, new List<Summary>());
  }

  /**
   * @description Grupos AXF-20 anteriores ao cronograma gerenciado: lançamentos PRICE/SAC/
   * INSTALLMENT com `ScheduleGroupKey`, sem cronograma nem contrato. Somente leitura; nunca adotados.
   */
  private List<FinancingView> legacyViews(
    Map<Id, String> holders,
    String legacyKey,
    List<Summary> summaries
  ) {
    List<FinancingView> views = new List<FinancingView>();
    if (holders.isEmpty()) {
      return views;
    }
    Set<Id> holderIds = holders.keySet();
    Set<String> methods = METHODS;
    Integer probe = MAX_LEGACY_ROWS + 1;
    String filter =
      'AXF_FTX_LKP_Schedule__c = NULL AND AXF_FTX_LKP_Contract__c = NULL' +
      ' AND AXF_FTX_TXT_ScheduleGroupKey__c != NULL' +
      ' AND AXF_FTX_NUM_Sequence__c != NULL' +
      ' AND AXF_FTX_PKL_Modality__c IN :methods' +
      ' AND AXF_FTX_LKP_Account__c IN :holderIds' +
      (legacyKey == null
        ? ''
        : ' AND AXF_FTX_TXT_ScheduleGroupKey__c = :legacyKey');
    Map<String, Object> binds = new Map<String, Object>{
      'methods' => methods,
      'holderIds' => holderIds,
      'probe' => probe
    };
    if (legacyKey != null) {
      binds.put('legacyKey', legacyKey);
    }
    List<AXF_OBJ_FinancialTransaction__c> rows = Database.queryWithBinds(
      installmentSoql(filter) +
      ' ORDER BY AXF_FTX_TXT_ScheduleGroupKey__c, AXF_FTX_NUM_Sequence__c LIMIT :probe',
      binds,
      AccessLevel.USER_MODE
    );
    Boolean cut = rows.size() > MAX_LEGACY_ROWS;
    if (cut) {
      rows.remove(rows.size() - 1);
    }
    if (rows.isEmpty()) {
      return views;
    }
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(
      new Map<Id, AXF_OBJ_FinancialTransaction__c>(rows).keySet(),
      unverified
    );
    Map<String, List<AXF_OBJ_FinancialTransaction__c>> groups = new Map<String, List<AXF_OBJ_FinancialTransaction__c>>();
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      String key = row.AXF_FTX_TXT_ScheduleGroupKey__c;
      if (!groups.containsKey(key)) {
        groups.put(key, new List<AXF_OBJ_FinancialTransaction__c>());
      }
      groups.get(key).add(row);
    }
    for (String key : groups.keySet()) {
      List<AXF_OBJ_FinancialTransaction__c> groupRows = groups.get(key);
      AXF_OBJ_FinancialTransaction__c head = groupRows[0];
      FinancingView view = new FinancingView();
      view.legacy = true;
      view.legacyKey = key;
      view.holderId = head.AXF_FTX_LKP_Account__c;
      view.holderLabel = holders.get(head.AXF_FTX_LKP_Account__c);
      view.description = head.AXF_FTX_TXT_Description__c;
      view.method = head.AXF_FTX_PKL_Modality__c;
      view.direction = head.AXF_FTX_PKL_Direction__c;
      view.currencyIsoCode = head.AXF_FTX_TXT_CurrencyIsoCode__c;
      view.totalInstallments = groupRows.size();
      view.state = STATE_ACTIVE;
      view.version = 0;
      Summary summary = new Summary();
      Decimal principal = 0;
      for (AXF_OBJ_FinancialTransaction__c row : groupRows) {
        summary.installments.add(persistedLine(row, nets.get(row.Id)));
        summary.unverified = summary.unverified || unverified.contains(row.Id);
        principal += row.AXF_FTX_NUM_PrincipalPortion__c == null
          ? 0
          : row.AXF_FTX_NUM_PrincipalPortion__c;
        if (
          row.AXF_FTX_DAT_DueDate__c != null &&
          (view.lastDueDate == null ||
          row.AXF_FTX_DAT_DueDate__c > view.lastDueDate)
        ) {
          view.lastDueDate = row.AXF_FTX_DAT_DueDate__c;
        }
      }
      view.principal = principal;
      view.unverified = summary.unverified || cut;
      applyProgress(view, summary.installments, nets);
      views.add(view);
      summaries.add(summary);
    }
    return views;
  }

  // ------------------------------------------------------------ apoio

  private static String installmentSoql(String whereClause) {
    return 'SELECT Id, AXF_FTX_LKP_Schedule__c, AXF_FTX_LKP_Account__c, AXF_FTX_NUM_Sequence__c,' +
      ' AXF_FTX_DAT_DueDate__c, AXF_FTX_NUM_CurrentBasis__c, AXF_FTX_NUM_Magnitude__c,' +
      ' AXF_FTX_PKL_Status__c, AXF_FTX_PKL_ScheduleState__c, AXF_FTX_PKL_Modality__c,' +
      ' AXF_FTX_NUM_PrincipalPortion__c, AXF_FTX_NUM_InterestPortion__c,' +
      ' AXF_FTX_NUM_ClosingBalance__c, AXF_FTX_TXT_ScheduleGroupKey__c,' +
      ' AXF_FTX_TXT_Description__c, AXF_FTX_PKL_Direction__c, AXF_FTX_TXT_CurrencyIsoCode__c' +
      ' FROM AXF_OBJ_FinancialTransaction__c WHERE ' +
      whereClause +
      (whereClause.contains('AXF_FTX_NUM_Sequence__c')
        ? ''
        : ' AND AXF_FTX_NUM_Sequence__c != NULL');
  }

  /** @description Titulares autorizados, por Id, com o rótulo exibido. */
  private static Map<Id, String> holderLabels() {
    Map<Id, String> labels = new Map<Id, String>();
    for (
      AXF_CLS_AuthorizedContextService.ContextView view : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      if (view.accountId != null) {
        labels.put(view.accountId, view.label);
      }
    }
    return labels;
  }

  /**
   * @description Um financiamento gerenciado do contexto autorizado, ou NOT_ACCESSIBLE —
   * inexistente e alheio são indistinguíveis.
   */
  private static AXF_OBJ_FinancialSchedule__c requireFinancing(
    Id scheduleId,
    Map<Id, String> holders
  ) {
    List<AXF_OBJ_FinancialSchedule__c> rows = holders.isEmpty()
      ? new List<AXF_OBJ_FinancialSchedule__c>()
      : scheduleRows(holders.keySet(), scheduleId);
    check(rows.size() == 1, CODE_NOT_ACCESSIBLE);
    return rows[0];
  }

  private static List<AXF_OBJ_FinancialSchedule__c> scheduleRows(
    Set<Id> holderIds,
    Id scheduleId
  ) {
    Set<String> states = new Set<String>{ STATE_ACTIVE, STATE_ENDED };
    String soql =
      'SELECT Id, AXF_FSC_LKP_Account__c, AXF_FSC_PKL_Direction__c, AXF_FSC_TXT_CurrencyIsoCode__c,' +
      ' AXF_FSC_PKL_State__c, AXF_FSC_DAT_TerminationDate__c, AXF_FSC_NUM_Version__c,' +
      ' AXF_FSC_NUM_TrackingStartSequence__c,' +
      ' AXF_FSC_LKP_ActiveDefinition__c,' +
      definitionFields('AXF_FSC_LKP_ActiveDefinition__r.') +
      ' FROM AXF_OBJ_FinancialSchedule__c' +
      ' WHERE AXF_FSC_LKP_Account__c IN :holderIds' +
      ' AND AXF_FSC_LKP_Contract__c = NULL' +
      ' AND AXF_FSC_PKL_State__c IN :states' +
      ' AND AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_PKL_Method__c IN :methods' +
      (scheduleId == null ? '' : ' AND Id = :scheduleId') +
      ' ORDER BY CreatedDate DESC, Id DESC LIMIT :maxRows';
    Map<String, Object> binds = new Map<String, Object>{
      'holderIds' => holderIds,
      'states' => states,
      'methods' => METHODS,
      'maxRows' => MAX_FINANCINGS
    };
    if (scheduleId != null) {
      binds.put('scheduleId', scheduleId);
    }
    return (List<AXF_OBJ_FinancialSchedule__c>) Database.queryWithBinds(
      soql,
      binds,
      AccessLevel.USER_MODE
    );
  }

  private static String definitionFields(String prefix) {
    List<String> fields = new List<String>{
      'Id',
      'AXF_SDF_NUM_Revision__c',
      'AXF_SDF_NUM_EffectiveSequence__c',
      'AXF_SDF_PKL_Method__c',
      'AXF_SDF_NUM_TotalInstallments__c',
      'AXF_SDF_NUM_FirstSequence__c',
      'AXF_SDF_DAT_FirstDueDate__c',
      'AXF_SDF_NUM_AnchorDay__c',
      'AXF_SDF_NUM_PeriodMonths__c',
      'AXF_SDF_NUM_PeriodDays__c',
      'AXF_SDF_NUM_Principal__c',
      'AXF_SDF_NUM_PeriodRate__c',
      'AXF_SDF_NUM_FixedValue__c',
      'AXF_SDF_NUM_RecurringFee__c',
      'AXF_SDF_NUM_UpfrontFee__c',
      'AXF_SDF_TAL_InputCanonicalJson__c'
    };
    List<String> prefixed = new List<String>();
    for (String field : fields) {
      prefixed.add(prefix + field);
    }
    return ' ' + String.join(prefixed, ', ');
  }

  /** @description Todas as revisões de definição de cada cronograma, em ordem de revisão. */
  private static Map<Id, List<AXF_OBJ_ScheduleDefinition__c>> definitionsBySchedule(
    Set<Id> scheduleIds
  ) {
    Map<Id, List<AXF_OBJ_ScheduleDefinition__c>> result = new Map<Id, List<AXF_OBJ_ScheduleDefinition__c>>();
    for (
      AXF_OBJ_ScheduleDefinition__c row : (List<AXF_OBJ_ScheduleDefinition__c>) Database.queryWithBinds(
        'SELECT AXF_SDF_LKP_Schedule__c,' +
          definitionFields('') +
          ' FROM AXF_OBJ_ScheduleDefinition__c WHERE AXF_SDF_LKP_Schedule__c IN :scheduleIds' +
          ' ORDER BY AXF_SDF_NUM_Revision__c ASC',
        new Map<String, Object>{ 'scheduleIds' => scheduleIds },
        AccessLevel.USER_MODE
      )
    ) {
      Id key = row.AXF_SDF_LKP_Schedule__c;
      if (!result.containsKey(key)) {
        result.put(key, new List<AXF_OBJ_ScheduleDefinition__c>());
      }
      result.get(key).add(row);
    }
    return result;
  }

  /**
   * @description Lançamento de quitação por cronograma, lido do ResultJson do recibo TERMINATE da
   * quitação (AXF-156).
   */
  private static Map<Id, Id> settlements(Set<Id> scheduleIds) {
    Map<Id, Id> result = new Map<Id, Id>();
    for (AXF_OBJ_ScheduleChange__c receipt : [
      SELECT AXF_SCH_LKP_Schedule__c, AXF_SCH_TAL_ResultJson__c
      FROM AXF_OBJ_ScheduleChange__c
      WHERE
        AXF_SCH_LKP_Schedule__c IN :scheduleIds
        AND AXF_SCH_PKL_Operation__c = :ALT_CLS_FinancialScheduleService.OPERATION_TERMINATE
      WITH USER_MODE
    ]) {
      if (String.isBlank(receipt.AXF_SCH_TAL_ResultJson__c)) {
        continue;
      }
      try {
        Object value = ((Map<String, Object>) JSON.deserializeUntyped(
            receipt.AXF_SCH_TAL_ResultJson__c
          ))
          .get('settlementTransactionId');
        if (value instanceof String && !String.isBlank((String) value)) {
          result.put(
            receipt.AXF_SCH_LKP_Schedule__c,
            Id.valueOf((String) value)
          );
        }
      } catch (Exception malformed) {
        continue;
      }
    }
    return result;
  }

  /**
   * @description Alocação líquida (APLICAÇÃO − REVERSÃO) por parcela: contrato verificado AXF-134
   * quando há a capacidade de vínculo; sem ela, a soma das alocações visíveis. Leitura recusada
   * deixa as parcelas não verificadas, sem adivinhar.
   */
  private static Map<Id, Decimal> nets(Set<Id> ids, Set<Id> unverified) {
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    if (ids.isEmpty()) {
      return result;
    }
    try {
      return new ALT_CLS_SourceLinkService().netOfTargets(ids, unverified);
    } catch (ALT_CLS_SourceLinkService.SourceLinkException withoutCapability) {
      result = new Map<Id, Decimal>();
    }
    Integer cap = ALT_CLS_SourceLinkService.MAX_ALLOCATION_ROWS;
    try {
      List<AXF_OBJ_ReconciliationAllocation__c> rows = [
        SELECT
          AXF_RA_LKP_FinancialTransaction__c,
          AXF_RA_PKL_Kind__c,
          AXF_RA_NUM_Magnitude__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_FinancialTransaction__c IN :ids
        WITH USER_MODE
        LIMIT :cap
      ];
      if (rows.size() >= cap) {
        unverified.addAll(ids);
        return new Map<Id, Decimal>();
      }
      for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
        Id key = row.AXF_RA_LKP_FinancialTransaction__c;
        Decimal sign = row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1;
        result.put(
          key,
          (result.containsKey(key) ? result.get(key) : 0) +
          sign * row.AXF_RA_NUM_Magnitude__c
        );
      }
    } catch (Exception refused) {
      unverified.addAll(ids);
      return new Map<Id, Decimal>();
    }
    return result;
  }

  private static Boolean validAmount(Decimal amount) {
    return amount != null &&
      amount > 0 &&
      amount <= ALT_CLS_FinancialScheduleService.MAX_AMOUNT &&
      amount == amount.setScale(ALT_CLS_FinancialScheduleService.MONEY_SCALE);
  }

  private static Boolean validKey(String operationKey) {
    return !String.isBlank(operationKey) &&
      operationKey.trim().length() <=
      ALT_CLS_FinancialScheduleService.MAX_OPERATION_KEY_LENGTH;
  }

  private static Integer intOf(Decimal value) {
    return value == null ? null : value.intValue();
  }

  /** Mesma data da porta de escrita: janela, comandos e validações concordam. */
  private static Date today() {
    return ALT_CLS_FinancialScheduleService.today();
  }

  private static void check(Boolean valid, String code) {
    if (valid != true) {
      throw new FinancingException(code);
    }
  }
}
