/**
 * @description AXF-155 — despesas e receitas recorrentes sem fim definido ("Recorrências").
 * Capacidade de negócio sobre o motor de cronogramas AXF-103: cria a recorrência como cronograma
 * `ESTIMATED` com valor de referência, periodicidade semanal/quinzenal (`PeriodDays`) ou em meses,
 * origem obrigatória e geração ligada; lista as recorrências do contexto autorizado com as
 * ocorrências filhas e o status derivado das alocações; edita o valor e encerra pelos comandos
 * EDIT/TERMINATE do contrato AXF-103, que só alteram ocorrências futuras não realizadas.
 *
 * Leituras em USER_MODE dentro do escopo de `AXF_CLS_AuthorizedContextService`; comandos exigem
 * criação/edição do cronograma (Gestor) e delegam a escrita à porta única
 * `ALT_CLS_FinancialScheduleService`. Falhas são códigos estáveis (`RecurrenceException`), nunca
 * mensagens internas.
 */
public with sharing class ALT_CLS_RecurrenceService {
  public static final String METHOD_ESTIMATED = 'ESTIMATED';
  public static final String STATE_ACTIVE = 'ACTIVE';
  public static final String STATE_ENDED = 'ENDED';
  public static final String OCC_PLANNED = 'PLANNED';
  public static final String OCC_RECONCILED = 'RECONCILED';
  public static final String OCC_PARTIAL = 'PARTIAL';
  public static final String OCC_CANCELLED = 'CANCELLED';
  public static final String KIND_BANK = 'BANK_ACCOUNT';
  public static final String KIND_CARD = 'CREDIT_CARD';
  public static final String KIND_WALLET = 'WALLET';
  public static final String CODE_INVALID = 'INVALID_INPUT';
  public static final String CODE_NOT_ACCESSIBLE = 'NOT_ACCESSIBLE';
  public static final String CODE_NOT_ALLOWED = 'NOT_ALLOWED';
  public static final String CODE_CONFLICT = 'CONFLICT';
  public static final String CODE_UNAVAILABLE = 'UNAVAILABLE';
  public static final String CODE_TOO_LARGE = 'TOO_LARGE';
  public static final String CODE_REJECTED = 'REJECTED';
  public static final Integer MAX_RECURRENCES = 200;
  public static final Integer MAX_OCCURRENCES = 500;
  /**
   * Horizonte materializado: mês corrente mais onze; na periodicidade semanal, mais dez, para
   * que a janela inicial caiba sempre no limite de 50 ocorrências por transação.
   */
  public static final Integer HORIZON_MONTHS = 12;
  public static final Integer WEEKLY_HORIZON_MONTHS = 11;
  private static final Integer WEEKLY_DAYS = 7;
  private static final Integer MAX_NEXT_DUE_STEPS = 1200;
  private static final Set<String> DIRECTIONS = new Set<String>{
    'DEBIT',
    'CREDIT'
  };
  private static final Set<String> SUCCESS = new Set<String>{
    ALT_CLS_FinancialScheduleService.OUTCOME_CREATED,
    ALT_CLS_FinancialScheduleService.OUTCOME_REPLAY,
    ALT_CLS_FinancialScheduleService.OUTCOME_UPDATED,
    ALT_CLS_FinancialScheduleService.OUTCOME_TERMINATED
  };

  @TestVisible
  private static Boolean canManageOverride;

  public class RecurrenceException extends Exception {
  }

  public class HolderOption {
    public Id accountId;
    public String label;
  }

  public class SourceOption {
    public Id bankAccountId;
    public Id creditCardId;
    public String label;
    /** BANK_ACCOUNT | CREDIT_CARD | WALLET */
    public String kind;
    /** Moeda da origem: a recorrência usa a mesma. */
    public String currencyIsoCode;
  }

  public class RecurrenceView {
    public Id scheduleId;
    public Id holderId;
    public String holderLabel;
    public String description;
    /** DEBIT = despesa, CREDIT = receita. */
    public String direction;
    public String currencyIsoCode;
    /** Valor de referência vigente. */
    public Decimal amount;
    public Integer periodDays;
    public Integer periodMonths;
    public Date firstDueDate;
    public Id bankAccountId;
    public Id creditCardId;
    public String sourceKind;
    public String sourceLabel;
    public Date nextDueDate;
    /** Vencimento da última ocorrência persistida: limite superior do encerramento. */
    public Date lastDueDate;
    /** ACTIVE | ENDED */
    public String state;
    public Date terminationDate;
    public Long version;
  }

  public class OccurrenceView {
    public Id transactionId;
    public Integer sequence;
    public Date dueDate;
    public Decimal amount;
    /** PLANNED | RECONCILED | PARTIAL | CANCELLED */
    public String status;
  }

  public class DetailView {
    public RecurrenceView recurrence;
    public List<OccurrenceView> occurrences = new List<OccurrenceView>();
    /** Há mais ocorrências do que o teto de leitura. */
    public Boolean truncated = false;
    /** O status de alguma ocorrência não pôde ser verificado pelas alocações visíveis. */
    public Boolean unverified = false;
  }

  public class SourceQuery {
    public Id accountId;
  }

  public class DetailQuery {
    public Id scheduleId;
  }

  public class CreateRequest {
    public Id accountId;
    public String description;
    public String direction;
    public Decimal amount;
    public String currencyIsoCode;
    public Date firstDueDate;
    public Integer periodDays;
    public Integer periodMonths;
    public Id bankAccountId;
    public Id creditCardId;
    public String operationKey;
  }

  public class EditRequest {
    public Id scheduleId;
    public Decimal amount;
    public Long expectedVersion;
    public String operationKey;
  }

  public class TerminateRequest {
    public Id scheduleId;
    /** Padrão: hoje. */
    public Date terminationDate;
    public Long expectedVersion;
    public String operationKey;
  }

  public class CommandResult {
    public Id scheduleId;
    public Boolean replay = false;
    /** Ocorrências materializadas (criar), atualizadas (editar) ou canceladas (encerrar). */
    public Integer changedCount = 0;
    /** Ocorrências realizadas/conciliadas preservadas pelo comando. */
    public Integer protectedCount = 0;
  }

  // ------------------------------------------------------------ capacidades

  /** @description Criar, editar e encerrar exigem criação/edição do cronograma (Gestor). */
  public Boolean canManage() {
    if (canManageOverride != null) {
      return canManageOverride;
    }
    return ALT_CLS_FinancialScheduleService.canChangeSchedules();
  }

  public List<HolderOption> holders() {
    List<HolderOption> options = new List<HolderOption>();
    for (
      AXF_CLS_AuthorizedContextService.ContextView view : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      HolderOption option = new HolderOption();
      option.accountId = view.accountId;
      option.label = view.label;
      options.add(option);
    }
    return options;
  }

  /** @description Origens disponíveis (conta, carteira ou cartão) do titular autorizado. */
  public List<SourceOption> sources(SourceQuery query) {
    check(query != null && query.accountId != null, CODE_INVALID);
    check(holderLabels().containsKey(query.accountId), CODE_NOT_ACCESSIBLE);
    List<SourceOption> options = new List<SourceOption>();
    for (
      AXF_CLS_FinancialEntryService.FundingSourceOption source : AXF_CLS_FinancialEntryService.getFundingSources(
        query.accountId
      )
    ) {
      SourceOption option = new SourceOption();
      option.bankAccountId = source.bankAccountId;
      option.creditCardId = source.creditCardId;
      option.label = source.label;
      option.kind = source.creditCardId != null
        ? KIND_CARD
        : (source.wallet == true ? KIND_WALLET : KIND_BANK);
      option.currencyIsoCode = sourceCurrency(
        source.bankAccountId,
        source.creditCardId
      );
      options.add(option);
    }
    return options;
  }

  // ------------------------------------------------------------ leitura

  public List<RecurrenceView> listRecurrences() {
    Map<Id, String> holders = holderLabels();
    if (holders.isEmpty()) {
      return new List<RecurrenceView>();
    }
    return views(scheduleRows(holders.keySet(), null), holders);
  }

  public DetailView detail(DetailQuery query) {
    check(query != null && query.scheduleId != null, CODE_INVALID);
    Map<Id, String> holders = holderLabels();
    AXF_OBJ_FinancialSchedule__c row = requireRecurrence(
      query.scheduleId,
      holders
    );
    DetailView detail = new DetailView();
    detail.recurrence = views(
      new List<AXF_OBJ_FinancialSchedule__c>{ row },
      holders
    )[0];
    Integer probe = MAX_OCCURRENCES + 1;
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT
        Id,
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_PKL_ScheduleState__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :row.Id
      WITH USER_MODE
      ORDER BY AXF_FTX_NUM_Sequence__c ASC, Id ASC
      LIMIT :probe
    ];
    if (rows.size() > MAX_OCCURRENCES) {
      detail.truncated = true;
      rows.remove(rows.size() - 1);
    }
    Set<Id> ids = new Map<Id, AXF_OBJ_FinancialTransaction__c>(rows).keySet();
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(ids, unverified);
    detail.unverified = !unverified.isEmpty();
    for (AXF_OBJ_FinancialTransaction__c occurrence : rows) {
      OccurrenceView view = new OccurrenceView();
      view.transactionId = occurrence.Id;
      view.sequence = occurrence.AXF_FTX_NUM_Sequence__c == null
        ? null
        : occurrence.AXF_FTX_NUM_Sequence__c.intValue();
      view.dueDate = occurrence.AXF_FTX_DAT_DueDate__c;
      view.amount = occurrence.AXF_FTX_NUM_CurrentBasis__c != null
        ? occurrence.AXF_FTX_NUM_CurrentBasis__c
        : occurrence.AXF_FTX_NUM_Magnitude__c;
      view.status = occurrenceStatus(
        occurrence,
        view.amount,
        nets.get(occurrence.Id)
      );
      detail.occurrences.add(view);
    }
    return detail;
  }

  /**
   * @description Status da ocorrência: cancelada pelo encerramento; conciliada quando as alocações
   * cobrem a base (ou a ocorrência já nasceu realizada); parcial com alocação menor; prevista no
   * restante.
   */
  @TestVisible
  private static String occurrenceStatus(
    AXF_OBJ_FinancialTransaction__c row,
    Decimal basis,
    Decimal net
  ) {
    if (row.AXF_FTX_PKL_ScheduleState__c == OCC_CANCELLED) {
      return OCC_CANCELLED;
    }
    if (net != null && net > 0) {
      return (basis != null && net >= basis) ? OCC_RECONCILED : OCC_PARTIAL;
    }
    if (row.AXF_FTX_PKL_Status__c == 'CONFIRMED') {
      return OCC_RECONCILED;
    }
    return OCC_PLANNED;
  }

  // ------------------------------------------------------------ comandos

  public CommandResult create(CreateRequest request) {
    check(canManage(), CODE_NOT_ALLOWED);
    check(request != null, CODE_INVALID);
    check(request.accountId != null, CODE_INVALID);
    check(holderLabels().containsKey(request.accountId), CODE_NOT_ACCESSIBLE);
    String direction = request.direction == null
      ? null
      : request.direction.trim().toUpperCase();
    check(DIRECTIONS.contains(direction), CODE_INVALID);
    check(validAmount(request.amount), CODE_INVALID);
    check(
      request.currencyIsoCode != null &&
      Pattern.matches('[A-Za-z]{3}', request.currencyIsoCode.trim()),
      CODE_INVALID
    );
    check(request.firstDueDate != null, CODE_INVALID);
    check(validPeriod(request.periodDays, request.periodMonths), CODE_INVALID);
    Integer horizonMonths = request.periodDays == WEEKLY_DAYS
      ? WEEKLY_HORIZON_MONTHS
      : HORIZON_MONTHS;
    // Sem retroagir (nada anterior ao mês corrente é gerado) e sem janela vazia (o primeiro
    // vencimento cabe no horizonte materializado na criação).
    check(
      request.firstDueDate >= ALT_CLS_ScheduleCalendar.monthStart(today()) &&
        request.firstDueDate <=
        ALT_CLS_ScheduleCalendar.monthEndShifted(today(), horizonMonths - 1),
      CODE_INVALID
    );
    check(
      !String.isBlank(request.description) &&
      request.description.trim().length() <=
      ALT_CLS_FinancialScheduleService.MAX_DESCRIPTION_LENGTH,
      CODE_INVALID
    );
    check(validKey(request.operationKey), CODE_INVALID);
    check(
      (request.bankAccountId == null) != (request.creditCardId == null),
      CODE_INVALID
    );
    check(
      isAvailableSource(
        request.accountId,
        request.bankAccountId,
        request.creditCardId
      ),
      CODE_INVALID
    );
    // A recorrência é lançada na moeda da própria origem.
    String originCurrency = sourceCurrency(
      request.bankAccountId,
      request.creditCardId
    );
    check(
      String.isBlank(originCurrency) ||
      originCurrency.trim().toUpperCase() ==
      request.currencyIsoCode.trim().toUpperCase(),
      CODE_INVALID
    );

    ALT_CLS_FinancialScheduleService.CreateInput input = new ALT_CLS_FinancialScheduleService.CreateInput();
    input.accountId = request.accountId;
    input.direction = direction;
    input.currencyIsoCode = request.currencyIsoCode.trim().toUpperCase();
    input.method = METHOD_ESTIMATED;
    input.referenceAmount = request.amount;
    input.firstSequence = 1;
    input.firstDueDate = request.firstDueDate;
    input.periodDays = request.periodDays;
    input.periodMonths = request.periodMonths;
    input.horizonMonths = horizonMonths;
    input.bankAccountId = request.bankAccountId;
    input.creditCardId = request.creditCardId;
    input.description = request.description.trim();
    input.generationEnabled = true;
    input.streamKey = request.operationKey.trim();
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    requireSuccess(created.outcome);
    CommandResult result = new CommandResult();
    result.scheduleId = created.scheduleId;
    result.replay = created.replay == true;
    result.changedCount = created.occurrenceCount == null
      ? 0
      : created.occurrenceCount;
    return result;
  }

  public CommandResult editAmount(EditRequest request) {
    check(request != null && request.scheduleId != null, CODE_INVALID);
    requireRecurrence(request.scheduleId, holderLabels());
    check(canManage(), CODE_NOT_ALLOWED);
    check(validAmount(request.amount), CODE_INVALID);
    check(request.expectedVersion != null, CODE_INVALID);
    check(validKey(request.operationKey), CODE_INVALID);
    ALT_CLS_FinancialScheduleService.ChangeInput input = new ALT_CLS_FinancialScheduleService.ChangeInput();
    input.scheduleId = request.scheduleId;
    input.amount = request.amount;
    input.expectedVersion = request.expectedVersion;
    input.operationKey = request.operationKey;
    return changeResult(ALT_CLS_FinancialScheduleService.editAmount(input));
  }

  public CommandResult terminate(TerminateRequest request) {
    check(request != null && request.scheduleId != null, CODE_INVALID);
    requireRecurrence(request.scheduleId, holderLabels());
    check(canManage(), CODE_NOT_ALLOWED);
    check(request.expectedVersion != null, CODE_INVALID);
    check(validKey(request.operationKey), CODE_INVALID);
    Date terminationDate = request.terminationDate == null
      ? today()
      : request.terminationDate;
    // Nem o passado (vencidas não pagas continuam obrigações) nem além da última ocorrência
    // persistida (a geração pararia antes da data escolhida).
    Date lastDue = lastDueDates(new Set<Id>{ request.scheduleId })
      .get(request.scheduleId);
    check(
      terminationDate >= today() &&
        terminationDate <=
        (lastDue == null || lastDue < today() ? today() : lastDue),
      CODE_INVALID
    );
    ALT_CLS_FinancialScheduleService.ChangeInput input = new ALT_CLS_FinancialScheduleService.ChangeInput();
    input.scheduleId = request.scheduleId;
    input.terminationDate = terminationDate;
    input.expectedVersion = request.expectedVersion;
    input.operationKey = request.operationKey;
    return changeResult(
      ALT_CLS_FinancialScheduleService.terminateSchedule(input)
    );
  }

  private static CommandResult changeResult(
    ALT_CLS_FinancialScheduleService.ChangeResult changed
  ) {
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
      when 'INVALID', 'UNSUPPORTED', 'MULTI_HOLDER' {
        code = CODE_INVALID;
      }
      when 'TOO_LARGE' {
        code = CODE_TOO_LARGE;
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
    throw new RecurrenceException(code);
  }

  // ------------------------------------------------------------ apoio

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
   * @description Uma recorrência do contexto autorizado (raiz ACTIVE/ENDED, sem contrato, com
   * definição vigente estimada), ou NOT_ACCESSIBLE — inexistente e alheia são indistinguíveis.
   */
  private static AXF_OBJ_FinancialSchedule__c requireRecurrence(
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
      ' AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_PeriodDays__c,' +
      ' AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_PeriodMonths__c,' +
      ' AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_FirstSequence__c,' +
      ' AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_AnchorDay__c,' +
      ' AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_DAT_FirstDueDate__c,' +
      ' AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_TAL_InputCanonicalJson__c,' +
      ' AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_InitialReferenceAmount__c,' +
      ' AXF_FSC_LKP_ActiveReference__r.AXF_SRF_NUM_RecurringAmount__c' +
      ' FROM AXF_OBJ_FinancialSchedule__c' +
      ' WHERE AXF_FSC_LKP_Account__c IN :holderIds' +
      ' AND AXF_FSC_LKP_Contract__c = NULL' +
      ' AND AXF_FSC_PKL_State__c IN :states' +
      ' AND AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_PKL_Method__c = :method' +
      (scheduleId == null ? '' : ' AND Id = :scheduleId') +
      ' ORDER BY CreatedDate DESC, Id DESC LIMIT :maxRows';
    Map<String, Object> binds = new Map<String, Object>{
      'holderIds' => holderIds,
      'states' => states,
      'method' => METHOD_ESTIMATED,
      'maxRows' => MAX_RECURRENCES
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

  private List<RecurrenceView> views(
    List<AXF_OBJ_FinancialSchedule__c> rows,
    Map<Id, String> holders
  ) {
    List<RecurrenceView> result = new List<RecurrenceView>();
    if (rows.isEmpty()) {
      return result;
    }
    Set<Id> scheduleIds = new Map<Id, AXF_OBJ_FinancialSchedule__c>(rows)
      .keySet();
    Map<Id, Date> nextDue = persistedNextDue(scheduleIds);
    Map<Id, Date> lastDue = lastDueDates(scheduleIds);
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (AXF_OBJ_FinancialSchedule__c row : rows) {
      RecurrenceView view = new RecurrenceView();
      AXF_OBJ_ScheduleDefinition__c definition = row.AXF_FSC_LKP_ActiveDefinition__r;
      Map<String, Object> canonical = ALT_CLS_FinancialScheduleService.canonicalInputOf(
        definition
      );
      view.scheduleId = row.Id;
      view.holderId = row.AXF_FSC_LKP_Account__c;
      view.holderLabel = holders.get(row.AXF_FSC_LKP_Account__c);
      view.description = (String) canonical.get(
        ALT_CLS_FinancialScheduleService.INPUT_DESCRIPTION
      );
      view.direction = row.AXF_FSC_PKL_Direction__c;
      view.currencyIsoCode = row.AXF_FSC_TXT_CurrencyIsoCode__c;
      view.amount = (row.AXF_FSC_LKP_ActiveReference__r != null &&
        row.AXF_FSC_LKP_ActiveReference__r.AXF_SRF_NUM_RecurringAmount__c !=
        null)
        ? row.AXF_FSC_LKP_ActiveReference__r.AXF_SRF_NUM_RecurringAmount__c
        : definition.AXF_SDF_NUM_InitialReferenceAmount__c;
      view.periodDays = intOf(definition.AXF_SDF_NUM_PeriodDays__c);
      view.periodMonths = intOf(definition.AXF_SDF_NUM_PeriodMonths__c);
      view.firstDueDate = definition.AXF_SDF_DAT_FirstDueDate__c;
      view.bankAccountId = (Id) canonical.get(
        ALT_CLS_FinancialScheduleService.INPUT_BANK_ACCOUNT
      );
      view.creditCardId = (Id) canonical.get(
        ALT_CLS_FinancialScheduleService.INPUT_CREDIT_CARD
      );
      view.state = row.AXF_FSC_PKL_State__c;
      view.lastDueDate = lastDue.get(row.Id);
      view.terminationDate = row.AXF_FSC_DAT_TerminationDate__c;
      view.version = row.AXF_FSC_NUM_Version__c == null
        ? 0
        : row.AXF_FSC_NUM_Version__c.longValue();
      if (view.state == STATE_ACTIVE) {
        view.nextDueDate = nextDue.containsKey(row.Id)
          ? nextDue.get(row.Id)
          : virtualNextDue(definition);
      }
      if (view.bankAccountId != null) {
        bankIds.add(view.bankAccountId);
      }
      if (view.creditCardId != null) {
        cardIds.add(view.creditCardId);
      }
      result.add(view);
    }
    applySourceLabels(result, bankIds, cardIds);
    return result;
  }

  /** @description Próximo vencimento persistido ainda não realizado nem cancelado. */
  private Map<Id, Date> persistedNextDue(Set<Id> scheduleIds) {
    Map<Id, Date> nextDue = new Map<Id, Date>();
    Date today = today();
    for (AggregateResult row : [
      SELECT
        AXF_FTX_LKP_Schedule__c scheduleId,
        MIN(AXF_FTX_DAT_DueDate__c) nextDue
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c IN :scheduleIds
        AND AXF_FTX_DAT_DueDate__c >= :today
        AND AXF_FTX_PKL_Status__c != 'CONFIRMED'
        AND (AXF_FTX_PKL_ScheduleState__c = NULL
        OR AXF_FTX_PKL_ScheduleState__c != :OCC_CANCELLED)
      WITH USER_MODE
      GROUP BY AXF_FTX_LKP_Schedule__c
    ]) {
      nextDue.put((Id) row.get('scheduleId'), (Date) row.get('nextDue'));
    }
    return nextDue;
  }

  /** @description Vencimento da última ocorrência persistida, por cronograma. */
  private static Map<Id, Date> lastDueDates(Set<Id> scheduleIds) {
    Map<Id, Date> lastDue = new Map<Id, Date>();
    for (AggregateResult row : [
      SELECT
        AXF_FTX_LKP_Schedule__c scheduleId,
        MAX(AXF_FTX_DAT_DueDate__c) lastDue
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c IN :scheduleIds
      WITH USER_MODE
      GROUP BY AXF_FTX_LKP_Schedule__c
    ]) {
      lastDue.put((Id) row.get('scheduleId'), (Date) row.get('lastDue'));
    }
    return lastDue;
  }

  /** @description Moeda da conta/carteira ou do cartão de origem, ou nula se não informada. */
  private static String sourceCurrency(Id bankAccountId, Id creditCardId) {
    if (bankAccountId != null) {
      for (AXF_OBJ_BankAccount__c account : [
        SELECT AXF_BA_TXT_CurrencyIsoCode__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :bankAccountId
        WITH USER_MODE
        LIMIT 1
      ]) {
        return account.AXF_BA_TXT_CurrencyIsoCode__c;
      }
    }
    if (creditCardId != null) {
      for (AXF_OBJ_CreditCard__c card : [
        SELECT AXF_CC_TXT_CurrencyIsoCode__c
        FROM AXF_OBJ_CreditCard__c
        WHERE Id = :creditCardId
        WITH USER_MODE
        LIMIT 1
      ]) {
        return card.AXF_CC_TXT_CurrencyIsoCode__c;
      }
    }
    return null;
  }

  /**
   * @description Sem ocorrência persistida futura (reposição ainda não rodou), o próximo
   * vencimento é o primeiro nominal a partir de hoje, pelo mesmo calendário do motor.
   */
  private Date virtualNextDue(AXF_OBJ_ScheduleDefinition__c definition) {
    if (definition == null || definition.AXF_SDF_DAT_FirstDueDate__c == null) {
      return null;
    }
    Date today = today();
    Integer first = definition.AXF_SDF_NUM_FirstSequence__c == null
      ? 1
      : definition.AXF_SDF_NUM_FirstSequence__c.intValue();
    try {
      for (Integer step = 0; step < MAX_NEXT_DUE_STEPS; step++) {
        Date due = ALT_CLS_ScheduleCalendar.nominalDueDate(
          definition.AXF_SDF_DAT_FirstDueDate__c,
          first,
          intOf(definition.AXF_SDF_NUM_PeriodMonths__c),
          intOf(definition.AXF_SDF_NUM_PeriodDays__c),
          intOf(definition.AXF_SDF_NUM_AnchorDay__c),
          first + step
        );
        if (due >= today) {
          return due;
        }
      }
    } catch (ALT_CLS_ScheduleCalendar.CalendarException invalid) {
      return null;
    }
    return null;
  }

  private void applySourceLabels(
    List<RecurrenceView> views,
    Set<Id> bankIds,
    Set<Id> cardIds
  ) {
    Map<Id, String> labels = new Map<Id, String>();
    Map<Id, String> kinds = new Map<Id, String>();
    if (!bankIds.isEmpty()) {
      for (AXF_OBJ_BankAccount__c account : [
        SELECT
          Id,
          AXF_BA_TXT_InstitutionName__c,
          AXF_BA_LKP_BankInstitution__r.Name,
          AXF_BA_TXT_NumberMasked__c,
          AXF_BA_TXT_Type__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id IN :bankIds
        WITH USER_MODE
      ]) {
        Boolean wallet = 'WALLET'.equalsIgnoreCase(account.AXF_BA_TXT_Type__c);
        kinds.put(account.Id, wallet ? KIND_WALLET : KIND_BANK);
        labels.put(
          account.Id,
          join(
            wallet
              ? System.Label.AXF_BankStatement_wallet
              : (account.AXF_BA_LKP_BankInstitution__r == null
                  ? account.AXF_BA_TXT_InstitutionName__c
                  : account.AXF_BA_LKP_BankInstitution__r.Name),
            account.AXF_BA_TXT_NumberMasked__c
          )
        );
      }
    }
    if (!cardIds.isEmpty()) {
      for (AXF_OBJ_CreditCard__c card : [
        SELECT
          Id,
          AXF_CC_TXT_InstitutionName__c,
          AXF_CC_LKP_BankInstitution__r.Name,
          AXF_CC_TXT_LastFourMasked__c
        FROM AXF_OBJ_CreditCard__c
        WHERE Id IN :cardIds
        WITH USER_MODE
      ]) {
        kinds.put(card.Id, KIND_CARD);
        labels.put(
          card.Id,
          join(
            card.AXF_CC_LKP_BankInstitution__r == null
              ? card.AXF_CC_TXT_InstitutionName__c
              : card.AXF_CC_LKP_BankInstitution__r.Name,
            card.AXF_CC_TXT_LastFourMasked__c
          )
        );
      }
    }
    for (RecurrenceView view : views) {
      Id source = view.creditCardId != null
        ? view.creditCardId
        : view.bankAccountId;
      if (source != null) {
        view.sourceKind = kinds.get(source);
        view.sourceLabel = labels.get(source);
      }
    }
  }

  /**
   * @description Alocação líquida (APLICAÇÃO − REVERSÃO) por ocorrência. Com a capacidade de
   * vínculo usa o contrato verificado AXF-134; sem ela, a soma das alocações visíveis. Leitura
   * recusada deixa as ocorrências não verificadas, sem adivinhar.
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

  private static Boolean isAvailableSource(
    Id accountId,
    Id bankAccountId,
    Id creditCardId
  ) {
    for (
      AXF_CLS_FinancialEntryService.FundingSourceOption source : AXF_CLS_FinancialEntryService.getFundingSources(
        accountId
      )
    ) {
      if (
        (bankAccountId != null && source.bankAccountId == bankAccountId) ||
        (creditCardId != null &&
        source.creditCardId == creditCardId)
      ) {
        return true;
      }
    }
    return false;
  }

  private static Boolean validAmount(Decimal amount) {
    return amount != null &&
      amount > 0 &&
      amount <= ALT_CLS_FinancialScheduleService.MAX_AMOUNT &&
      amount == amount.setScale(ALT_CLS_FinancialScheduleService.MONEY_SCALE);
  }

  /** @description Exatamente uma periodicidade: 7/14 dias ou 1..120 meses. */
  private static Boolean validPeriod(Integer periodDays, Integer periodMonths) {
    if ((periodDays == null) == (periodMonths == null)) {
      return false;
    }
    if (periodDays != null) {
      return ALT_CLS_FinancialScheduleService.PERIOD_DAYS.contains(periodDays);
    }
    return periodMonths >= 1 &&
      periodMonths <= ALT_CLS_FinancialScheduleService.MAX_PERIOD_MONTHS;
  }

  private static Boolean validKey(String operationKey) {
    return !String.isBlank(operationKey) &&
      operationKey.trim().length() <=
      ALT_CLS_FinancialScheduleService.MAX_OPERATION_KEY_LENGTH;
  }

  private static String join(String first, String second) {
    return String.join(
        new List<String>{
          first == null ? '' : first,
          second == null ? '' : second
        },
        ' '
      )
      .trim();
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
      throw new RecurrenceException(code);
    }
  }
}
