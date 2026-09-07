/**
 * @description Motor de revisao e publicacao da agenda contratual (AXF-55).
 *
 * Fluxo (AC 1-4):
 * 1. createRun: cria/preview-run unico por Contrato+ACTIVE (ActiveScopeToken unico - impede
 *    geracoes concorrentes; run concorrente retorna o existente para "acompanhar"). Ocorrencias
 *    desejadas sao derivadas do TermVersion ACTIVE via ALT_CLS_ContractRemunerationService
 *    (calculo canonico ja testado: FIXED por parcelas com residual, MONTHLY com proration,
 *    HOURLY estimativa do termo) filtradas pelo horizonte informado.
 * 2. computePreview: classifica o delta (ADDED | PRESERVED | SUPERSEDED | BLOCKED) com totais e
 *    residual e persiste PreviewJson. NADA e publicado antes da confirmacao humana.
 * 3. publish: aplica somente ADDED (cria FTX ocorrencia PLANNED + ContractApplicationSnapshot via
 *    ALT_CLS_ContractSnapshotService) e SUPERSEDED (atualiza draft gerado intocado PLANNED).
 *    Confirmed/realized/reconciled/overridden sao sempre BLOCKED (nunca tocados). Watermark e
 *    complete-through sao gravados a cada item (checkpoint/retomada idempotente; AC 4).
 *
 * Sem Delete, sem perfil alterado, CRUD/FLS/sharing nativos (with sharing). Regras de politica
 * de agenda fora do TermVersion nao sao inventadas: entradas sem policy contratada permanecem
 * BLOCKED ate ratificacao (mockup Agenda/SPEC).
 */
public with sharing class ALT_CLS_ContractAgendaService {
  public static final String STATE_PREVIEW = 'PREVIEW';
  public static final String STATE_APPLYING = 'APPLYING';
  public static final String STATE_COMPLETE = 'COMPLETE';
  public static final String STATE_FAILED = 'FAILED';

  public static final String ACTION_ADDED = 'ADDED';
  public static final String ACTION_PRESERVED = 'PRESERVED';
  public static final String ACTION_SUPERSEDED = 'SUPERSEDED';
  public static final String ACTION_BLOCKED = 'BLOCKED';

  public static final String FTX_STATUS_PLANNED = 'PLANNED';
  public static final String FTX_STATUS_CONFIRMED = 'CONFIRMED';

  public class RunInputDTO {
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public Id termVersionId;
    @AuraEnabled
    public Date horizonFrom;
    @AuraEnabled
    public Date horizonThrough;
  }

  public class AgendaItemDTO {
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public String occurrenceKey;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String action;
    @AuraEnabled
    public String reason;
  }

  public class RunResultDTO {
    @AuraEnabled
    public Id runId;
    @AuraEnabled
    public Boolean created;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<AgendaItemDTO> items;
    @AuraEnabled
    public Integer added;
    @AuraEnabled
    public Integer preserved;
    @AuraEnabled
    public Integer superseded;
    @AuraEnabled
    public Integer blocked;
    @AuraEnabled
    public Decimal totalAdded;
    @AuraEnabled
    public Decimal totalResidual;
  }

  // ------------------------------------------------------------------
  // 1. Criar / reutilizar run da agenda
  // ------------------------------------------------------------------
  public RunResultDTO createRun(RunInputDTO input) {
    if (input == null || input.contractId == null || input.termVersionId == null) {
      throw new AXF_CLS_ContractException('Contrato, TermVersion e obrigatorios.');
    }
    if (input.horizonFrom == null || input.horizonThrough == null) {
      throw new AXF_CLS_ContractException('Horizonte (de/ate) e obrigatorio.');
    }
    if (input.horizonThrough < input.horizonFrom) {
      throw new AXF_CLS_ContractException('Horizonte invalido (ate antes de de).');
    }

    ContractContext ctx = loadContext(input.contractId, input.termVersionId);

    String scopeToken = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'csr-scope-v1', ctx.contractKey, 'ACTIVE' }
    );

    // Run concorrente ativo: oferece acompanhar o existente (AC 1).
    AXF_OBJ_ContractScheduleRun__c active = findRunByToken(scopeToken);
    if (active != null) {
      return toResult(active, null, false);
    }

    // Replay/retomada: mesmos inputs retornam o run original (G6).
    String occurrenceKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        'csr-v1',
        ctx.contractKey,
        String.valueOf(ctx.termRevision),
        input.horizonFrom,
        input.horizonThrough
      }
    );
    AXF_OBJ_ContractScheduleRun__c byKey = findRunByOccurrenceKey(occurrenceKey);
    if (byKey != null) {
      return toResult(byKey, null, false);
    }

    AXF_OBJ_ContractScheduleRun__c run = new AXF_OBJ_ContractScheduleRun__c();
    run.AXF_CSR_LKP_Contract__c = ctx.contractId;
    run.AXF_CSR_LKP_TermVersion__c = ctx.termVersionId;
    run.AXF_CSR_EXI_ActiveScopeToken__c = scopeToken;
    run.AXF_CSR_EXI_OccurrenceKey__c = occurrenceKey;
    run.AXF_CSR_EXI_InputHash__c = buildInputHash(ctx, input);
    run.AXF_CSR_PKL_State__c = STATE_PREVIEW;
    run.AXF_CSR_DAT_HorizonFrom__c = input.horizonFrom;
    run.AXF_CSR_DAT_HorizonThrough__c = input.horizonThrough;
    run.AXF_CSR_TXT_CorrelationId__c = correlationId();
    run.AXF_CSR_TXT_Watermark__c = '';
    run.AXF_CSR_NUM_Version__c = 0;
    run.OwnerId = ctx.contractOwnerId;
    insert run;

    return toResult(run, null, true);
  }

  // ------------------------------------------------------------------
  // 2. Previa delta (nada publicado)
  // ------------------------------------------------------------------
  public RunResultDTO computePreview(Id runId) {
    AXF_OBJ_ContractScheduleRun__c run = loadRun(runId);
    if (run.AXF_CSR_PKL_State__c == STATE_COMPLETE) {
      throw new AXF_CLS_ContractException('Run ja concluida.');
    }

    ContractContext ctx = loadContext(
      run.AXF_CSR_LKP_Contract__c,
      run.AXF_CSR_LKP_TermVersion__c
    );

    List<AgendaItemDTO> items = classifyDelta(ctx, run);

    // Persiste apenas a previa; nenhuma ocorrencia muda (AC 2).
    run.AXF_CSR_PKL_State__c = STATE_PREVIEW;
    run.AXF_CSR_NUM_Added__c = count(items, ACTION_ADDED);
    run.AXF_CSR_NUM_Preserved__c = count(items, ACTION_PRESERVED);
    run.AXF_CSR_NUM_Superseded__c = count(items, ACTION_SUPERSEDED);
    run.AXF_CSR_NUM_Blocked__c = count(items, ACTION_BLOCKED);
    run.AXF_CSR_TAL_PreviewJson__c = serializePreview(ctx, run, items);
    update run;

    return toResult(run, items, false);
  }

  // ------------------------------------------------------------------
  // 3. Publicar apos confirmacao humana (AC 2/3/4)
  // ------------------------------------------------------------------
  public RunResultDTO publish(Id runId) {
    AXF_OBJ_ContractScheduleRun__c run = loadRun(runId);
    if (run.AXF_CSR_PKL_State__c != STATE_PREVIEW) {
      throw new AXF_CLS_ContractException(
        'Publicacao requer previa confirmada (estado PREVIEW).'
      );
    }

    ContractContext ctx = loadContext(
      run.AXF_CSR_LKP_Contract__c,
      run.AXF_CSR_LKP_TermVersion__c
    );

    run.AXF_CSR_PKL_State__c = STATE_APPLYING;
    update run;

    List<AgendaItemDTO> items = classifyDelta(ctx, run);
    Integer added = 0;
    Integer preserved = 0;
    Integer superseded = 0;
    Integer blocked = 0;
    Date completeThrough = run.AXF_CSR_DAT_HorizonFrom__c;
    Map<String, AXF_OBJ_FinancialTransaction__c> existing = loadExisting(ctx);

    for (AgendaItemDTO item : items) {
      if (item.action == ACTION_ADDED) {
        applyAdded(ctx, run, item);
        added++;
        run.AXF_CSR_TXT_Watermark__c = item.occurrenceKey;
      } else if (item.action == ACTION_PRESERVED) {
        preserved++;
      } else if (item.action == ACTION_SUPERSEDED) {
        AXF_OBJ_FinancialTransaction__c target = existing.get(item.occurrenceKey);
        if (target != null && isSupersedeAllowed(target, ctx)) {
          target.AXF_FTX_NUM_Magnitude__c = item.amount;
          target.AXF_FTX_DAT_DueDate__c = item.dueDate;
          target.AXF_FTX_DAT_PurchaseDate__c = item.dueDate;
          update target;
          superseded++;
          run.AXF_CSR_TXT_Watermark__c = item.occurrenceKey;
        } else {
          blocked++;
        }
      } else {
        blocked++;
      }
      if (item.dueDate != null && (completeThrough == null || item.dueDate > completeThrough)) {
        completeThrough = item.dueDate;
      }
    }

    run.AXF_CSR_NUM_Added__c = added;
    run.AXF_CSR_NUM_Preserved__c = preserved;
    run.AXF_CSR_NUM_Superseded__c = superseded;
    run.AXF_CSR_NUM_Blocked__c = blocked;
    run.AXF_CSR_DAT_CompleteThrough__c = completeThrough;
    run.AXF_CSR_PKL_State__c = STATE_COMPLETE;
    run.AXF_CSR_EXI_ActiveScopeToken__c = null; // libera nova geracao do mesmo contrato
    run.AXF_CSR_NUM_Version__c = (run.AXF_CSR_NUM_Version__c == null ? 0 : run.AXF_CSR_NUM_Version__c) + 1;
    update run;

    RunResultDTO result = toResult(run, null, false);
    result.message = added + ' adicionada(s); ' + superseded + ' superseded; ' + blocked + ' bloqueada(s).';
    return result;
  }

  // ------------------------------------------------------------------
  // classificacao
  // ------------------------------------------------------------------
  private List<AgendaItemDTO> classifyDelta(ContractContext ctx, AXF_OBJ_ContractScheduleRun__c run) {
    List<AgendaItemDTO> desired = desiredItems(ctx, run);
    Map<String, AXF_OBJ_FinancialTransaction__c> existing = loadExisting(ctx);
    List<AgendaItemDTO> result = new List<AgendaItemDTO>();

    for (AgendaItemDTO item : desired) {
      AXF_OBJ_FinancialTransaction__c current = existing.get(item.occurrenceKey);
      if (current == null) {
        item.action = ACTION_ADDED;
      } else if (isProtected(current, ctx)) {
        item.action = ACTION_BLOCKED;
        item.reason = 'PROTECTED';
      } else if (sameContent(current, item)) {
        item.action = ACTION_PRESERVED;
      } else {
        item.action = ACTION_SUPERSEDED;
      }
      result.add(item);
    }
    return result;
  }

  private List<AgendaItemDTO> desiredItems(ContractContext ctx, AXF_OBJ_ContractScheduleRun__c run) {
    List<AgendaItemDTO> items = new List<AgendaItemDTO>();
    Date horizonStart = run.AXF_CSR_DAT_HorizonFrom__c;
    Date horizonEnd = run.AXF_CSR_DAT_HorizonThrough__c;

    ALT_CLS_ContractRemunerationService rem = new ALT_CLS_ContractRemunerationService();
    ALT_CLS_ContractRemunerationService.TermVersionInputDTO input = new ALT_CLS_ContractRemunerationService.TermVersionInputDTO();
    input.contractId = ctx.contractId;
    input.termVersionId = ctx.termVersionId;
    input.revision = ctx.termRevision;
    input.remunerationModel = ctx.model;
    input.currencyIsoCode = ctx.currencyIsoCode;
    input.effectiveFrom = ctx.effectiveFrom;
    input.effectiveTo = ctx.effectiveTo;
    input.contractedAmount = ctx.contractedAmount;
    input.rate = ctx.rate;
    input.hoursQuantity = ctx.hoursQuantity;
    input.installments = ctx.installments == null ? 0 : ctx.installments;
    input.proportionalityPolicy = ctx.proportionalityPolicy;
    input.timeZone = ctx.timeZone;
    input.calendarPolicy = ctx.calendarPolicy;

    ALT_CLS_ContractRemunerationService.ScheduleCalculationResultDTO calc = rem.calculateSchedule(input);
    if (calc == null || calc.scheduleItems == null) {
      throw new AXF_CLS_ContractException('Nao foi possivel calcular a agenda do termo.');
    }

    for (ALT_CLS_ContractRemunerationService.ScheduleItemDTO raw : calc.scheduleItems) {
      if (raw.dueDate == null || raw.dueDate < horizonStart || raw.dueDate > horizonEnd) {
        continue;
      }
      AgendaItemDTO item = new AgendaItemDTO();
      item.sequence = raw.installmentNumber;
      item.dueDate = raw.dueDate;
      item.amount = raw.amount;
      item.occurrenceKey = occurrenceKey(ctx, raw.installmentNumber);
      items.add(item);
    }
    return items;
  }

  private Map<String, AXF_OBJ_FinancialTransaction__c> loadExisting(ContractContext ctx) {
    Map<String, AXF_OBJ_FinancialTransaction__c> resultByKey = new Map<String, AXF_OBJ_FinancialTransaction__c>();
    for (AXF_OBJ_FinancialTransaction__c ftx : [
      SELECT
        Id,
        AXF_FTX_EXI_PlanIdentityHash__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_LKP_ContractApplicationSnapshot__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Contract__c = :ctx.contractId
        AND AXF_FTX_LKP_ContractTermVersion__c = :ctx.termVersionId
        AND AXF_FTX_EXI_PlanIdentityHash__c != null
    ]) {
      resultByKey.put(ftx.AXF_FTX_EXI_PlanIdentityHash__c, ftx);
    }
    return resultByKey;
  }

  private Boolean isProtected(
    AXF_OBJ_FinancialTransaction__c ftx,
    ContractContext ctx
  ) {
    if (ftx.AXF_FTX_PKL_Status__c != FTX_STATUS_PLANNED) {
      return true; // CONFIRMED ou estados futuros (realizado/conciliado)
    }
    return hasActiveOverride(ftx);
  }

  private Boolean hasActiveOverride(AXF_OBJ_FinancialTransaction__c ftx) {
    if (ftx.AXF_FTX_LKP_ContractApplicationSnapshot__c == null) {
      return false;
    }
    AXF_OBJ_ContractApplicationSnapshot__c cas = [
      SELECT Id, AXF_CAS_TAL_FieldProvenance__c
      FROM AXF_OBJ_ContractApplicationSnapshot__c
      WHERE Id = :ftx.AXF_FTX_LKP_ContractApplicationSnapshot__c
      LIMIT 1
    ];
    if (cas == null) {
      return false;
    }
    Map<String, String> provenance = ALT_CLS_ContractSnapshotService.parseProvenance(
      cas.AXF_CAS_TAL_FieldProvenance__c
    );
    for (String field : provenance.keySet()) {
      if (provenance.get(field) == ALT_CLS_ContractSnapshotService.PROV_OVERRIDDEN) {
        return true;
      }
    }
    return false;
  }

  private Boolean sameContent(
    AXF_OBJ_FinancialTransaction__c ftx,
    AgendaItemDTO item
  ) {
    Boolean sameAmount = ftx.AXF_FTX_NUM_Magnitude__c == item.amount;
    Boolean sameDue = ftx.AXF_FTX_DAT_DueDate__c == item.dueDate;
    return sameAmount && sameDue;
  }

  private Boolean isSupersedeAllowed(
    AXF_OBJ_FinancialTransaction__c ftx,
    ContractContext ctx
  ) {
    return ftx.AXF_FTX_PKL_Status__c == FTX_STATUS_PLANNED && !hasActiveOverride(ftx);
  }

  // ------------------------------------------------------------------
  // aplicacao
  // ------------------------------------------------------------------
  private void applyAdded(
    ContractContext ctx,
    AXF_OBJ_ContractScheduleRun__c run,
    AgendaItemDTO item
  ) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c();
    ftx.AXF_FTX_LKP_Account__c = ctx.accountId;
    ftx.AXF_FTX_NUM_Magnitude__c = item.amount;
    ftx.AXF_FTX_PKL_Direction__c = ctx.direction;
    ftx.AXF_FTX_TXT_CurrencyIsoCode__c = ctx.currencyIsoCode;
    ftx.AXF_FTX_DAT_PurchaseDate__c = item.dueDate;
    ftx.AXF_FTX_DAT_DueDate__c = item.dueDate;
    ftx.AXF_FTX_PKL_Status__c = FTX_STATUS_PLANNED;
    ftx.AXF_FTX_TXT_ScheduleGroupKey__c = agendaGroupKey(run);
    ftx.AXF_FTX_EXI_PlanIdentityHash__c = item.occurrenceKey;
    ftx.AXF_FTX_EXI_ClientRequestId__c = left(item.occurrenceKey, 36);
    insert ftx;

    // CAS imutavel 1:1 da aplicacao do termo (AXF-57); idempotente por identidade.
    ALT_CLS_ContractSnapshotService snapService = new ALT_CLS_ContractSnapshotService();
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO snapInput = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    snapInput.financialTransactionId = ftx.Id;
    snapInput.termVersionId = ctx.termVersionId;
    snapService.applyToOccurrence(snapInput);
  }

  // ------------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------------
  private String occurrenceKey(ContractContext ctx, Integer sequence) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        'ftx-agenda-v1',
        ctx.contractKey,
        String.valueOf(ctx.termRevision),
        sequence
      }
    );
  }

  private String agendaGroupKey(AXF_OBJ_ContractScheduleRun__c run) {
    return 'agenda-' + left(run.AXF_CSR_EXI_OccurrenceKey__c, 20);
  }

  private String buildInputHash(ContractContext ctx, RunInputDTO input) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        'csr-input-v1',
        ctx.contractKey,
        String.valueOf(ctx.termRevision),
        input.horizonFrom,
        input.horizonThrough
      }
    );
  }

  private String correlationId() {
    String s = String.valueOf(Datetime.now().getTime());
    return left(AXF_CLS_IdentityFraming.sha256Hex(s), 36);
  }

  private String serializePreview(
    ContractContext ctx,
    AXF_OBJ_ContractScheduleRun__c run,
    List<AgendaItemDTO> items
  ) {
    Map<String, Object> root = new Map<String, Object>();
    root.put('schemaVersion', 1);
    root.put('contractKey', ctx.contractKey);
    root.put('termRevision', ctx.termRevision);
    root.put('model', ctx.model);
    root.put('currencyIsoCode', ctx.currencyIsoCode);
    root.put('horizonFrom', String.valueOf(run.AXF_CSR_DAT_HorizonFrom__c));
    root.put('horizonThrough', String.valueOf(run.AXF_CSR_DAT_HorizonThrough__c));
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    Decimal totalAdded = 0;
    Decimal totalResidual = 0;
    for (AgendaItemDTO item : items) {
      Map<String, Object> row = new Map<String, Object>();
      row.put('sequence', item.sequence);
      row.put('occurrenceKey', item.occurrenceKey);
      row.put('dueDate', String.valueOf(item.dueDate));
      row.put('amount', item.amount);
      row.put('action', item.action);
      row.put('reason', item.reason);
      rows.add(row);
      if (item.action == ACTION_ADDED) {
        totalAdded += item.amount == null ? 0 : item.amount;
      }
    }
    root.put('items', rows);
    root.put('totalAdded', totalAdded);
    root.put('totalResidual', totalResidual);
    return JSON.serialize(root);
  }

  private String left(String value, Integer size) {
    if (value == null) {
      return null;
    }
    return value.length() <= size ? value : value.substring(0, size);
  }

  private Integer count(List<AgendaItemDTO> items, String action) {
    Integer n = 0;
    for (AgendaItemDTO item : items) {
      if (item.action == action) {
        n++;
      }
    }
    return n;
  }

  private RunResultDTO toResult(
    AXF_OBJ_ContractScheduleRun__c run,
    List<AgendaItemDTO> items,
    Boolean created
  ) {
    RunResultDTO result = new RunResultDTO();
    result.runId = run.Id;
    result.created = created;
    result.state = run.AXF_CSR_PKL_State__c;
    result.message = 'Run em ' + run.AXF_CSR_PKL_State__c + '.';
    result.items = items == null ? new List<AgendaItemDTO>() : items;
    result.added = run.AXF_CSR_NUM_Added__c == null ? 0 : Integer.valueOf(run.AXF_CSR_NUM_Added__c);
    result.preserved = run.AXF_CSR_NUM_Preserved__c == null ? 0 : Integer.valueOf(run.AXF_CSR_NUM_Preserved__c);
    result.superseded = run.AXF_CSR_NUM_Superseded__c == null ? 0 : Integer.valueOf(run.AXF_CSR_NUM_Superseded__c);
    result.blocked = run.AXF_CSR_NUM_Blocked__c == null ? 0 : Integer.valueOf(run.AXF_CSR_NUM_Blocked__c);
    return result;
  }

  private AXF_OBJ_ContractScheduleRun__c findRunByToken(String token) {
    List<AXF_OBJ_ContractScheduleRun__c> runs = [
      SELECT
        Id,
        AXF_CSR_PKL_State__c,
        AXF_CSR_NUM_Added__c,
        AXF_CSR_NUM_Preserved__c,
        AXF_CSR_NUM_Superseded__c,
        AXF_CSR_NUM_Blocked__c
      FROM AXF_OBJ_ContractScheduleRun__c
      WHERE AXF_CSR_EXI_ActiveScopeToken__c = :token
      LIMIT 1
    ];
    return runs.isEmpty() ? null : runs[0];
  }

  private AXF_OBJ_ContractScheduleRun__c findRunByOccurrenceKey(String key) {
    List<AXF_OBJ_ContractScheduleRun__c> runs = [
      SELECT
        Id,
        AXF_CSR_PKL_State__c,
        AXF_CSR_NUM_Added__c,
        AXF_CSR_NUM_Preserved__c,
        AXF_CSR_NUM_Superseded__c,
        AXF_CSR_NUM_Blocked__c
      FROM AXF_OBJ_ContractScheduleRun__c
      WHERE AXF_CSR_EXI_OccurrenceKey__c = :key
      LIMIT 1
    ];
    return runs.isEmpty() ? null : runs[0];
  }

  private AXF_OBJ_ContractScheduleRun__c loadRun(Id runId) {
    List<AXF_OBJ_ContractScheduleRun__c> runs = [
      SELECT
        Id,
        AXF_CSR_LKP_Contract__c,
        AXF_CSR_LKP_TermVersion__c,
        AXF_CSR_EXI_ActiveScopeToken__c,
        AXF_CSR_EXI_OccurrenceKey__c,
        AXF_CSR_EXI_InputHash__c,
        AXF_CSR_PKL_State__c,
        AXF_CSR_DAT_HorizonFrom__c,
        AXF_CSR_DAT_HorizonThrough__c,
        AXF_CSR_TAL_PreviewJson__c,
        AXF_CSR_NUM_Added__c,
        AXF_CSR_NUM_Preserved__c,
        AXF_CSR_NUM_Superseded__c,
        AXF_CSR_NUM_Blocked__c,
        AXF_CSR_TXT_Watermark__c,
        AXF_CSR_DAT_CompleteThrough__c,
        AXF_CSR_TXT_CorrelationId__c,
        AXF_CSR_NUM_Version__c
      FROM AXF_OBJ_ContractScheduleRun__c
      WHERE Id = :runId
      LIMIT 1
    ];
    if (runs.isEmpty()) {
      throw new AXF_CLS_ContractException('Run da agenda nao encontrado.');
    }
    return runs[0];
  }

  private ContractContext loadContext(Id contractId, Id termVersionId) {
    List<AXF_OBJ_Contract__c> contracts = [
      SELECT
        Id,
        OwnerId,
        AXF_CTR_LKP_Account__c,
        AXF_CTR_EXI_ContractKey__c,
        AXF_CTR_PKL_Type__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
      LIMIT 1
    ];
    if (contracts.isEmpty()) {
      throw new AXF_CLS_ContractException('Contrato nao encontrado.');
    }
    AXF_OBJ_Contract__c contract = contracts[0];

    List<AXF_OBJ_ContractTermVersion__c> terms = [
      SELECT
        Id,
        AXF_CTV_LKP_Contract__c,
        AXF_CTV_NUM_Revision__c,
        AXF_CTV_PKL_Status__c,
        AXF_CTV_PKL_RemunerationModel__c,
        AXF_CTV_TXT_CurrencyIsoCode__c,
        AXF_CTV_DAT_EffectiveFrom__c,
        AXF_CTV_DAT_EffectiveTo__c,
        AXF_CTV_CUR_ContractedAmount__c,
        AXF_CTV_CUR_Rate__c,
        AXF_CTV_NUM_HoursQuantity__c,
        AXF_CTV_NUM_Installments__c,
        AXF_CTV_PKL_ProportionalityPolicy__c,
        AXF_CTV_TXT_TimeZone__c,
        AXF_CTV_TXT_CalendarPolicy__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :termVersionId
      LIMIT 1
    ];
    if (terms.isEmpty() || terms[0].AXF_CTV_LKP_Contract__c != contractId) {
      throw new AXF_CLS_ContractException('TermVersion invalida para o contrato.');
    }
    if (terms[0].AXF_CTV_PKL_Status__c != 'ACTIVE') {
      throw new AXF_CLS_ContractException('Somente TermVersion ACTIVE gera agenda.');
    }

    ContractContext ctx = new ContractContext();
    ctx.contractId = contractId;
    ctx.contractOwnerId = contract.OwnerId;
    ctx.accountId = contract.AXF_CTR_LKP_Account__c;
    ctx.contractKey = contract.AXF_CTR_EXI_ContractKey__c;
    ctx.contractType = contract.AXF_CTR_PKL_Type__c;
    ctx.direction = 'EXPENSE'.equalsIgnoreCase(ctx.contractType) ? 'DEBIT' : 'CREDIT';
    ctx.termVersionId = termVersionId;
    ctx.termRevision = terms[0].AXF_CTV_NUM_Revision__c == null ? 0 : terms[0].AXF_CTV_NUM_Revision__c.longValue();
    ctx.model = terms[0].AXF_CTV_PKL_RemunerationModel__c;
    ctx.currencyIsoCode = terms[0].AXF_CTV_TXT_CurrencyIsoCode__c;
    ctx.effectiveFrom = terms[0].AXF_CTV_DAT_EffectiveFrom__c;
    ctx.effectiveTo = terms[0].AXF_CTV_DAT_EffectiveTo__c;
    ctx.contractedAmount = terms[0].AXF_CTV_CUR_ContractedAmount__c;
    ctx.rate = terms[0].AXF_CTV_CUR_Rate__c;
    ctx.hoursQuantity = terms[0].AXF_CTV_NUM_HoursQuantity__c;
    ctx.installments = terms[0].AXF_CTV_NUM_Installments__c == null ? null : Integer.valueOf(terms[0].AXF_CTV_NUM_Installments__c);
    ctx.proportionalityPolicy = terms[0].AXF_CTV_PKL_ProportionalityPolicy__c;
    ctx.timeZone = terms[0].AXF_CTV_TXT_TimeZone__c;
    ctx.calendarPolicy = terms[0].AXF_CTV_TXT_CalendarPolicy__c;
    return ctx;
  }

  private class ContractContext {
    public Id contractId;
    public Id contractOwnerId;
    public Id accountId;
    public String contractKey;
    public String contractType;
    public String direction;
    public Id termVersionId;
    public Long termRevision;
    public String model;
    public String currencyIsoCode;
    public Date effectiveFrom;
    public Date effectiveTo;
    public Decimal contractedAmount;
    public Decimal rate;
    public Decimal hoursQuantity;
    public Integer installments;
    public String proportionalityPolicy;
    public String timeZone;
    public String calendarPolicy;
  }
}
