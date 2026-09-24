/**
 * AXF-103 — motor único de projeção do cronograma (AD-6). Toda leitura de ocorrência,
 * de valor por ocorrência e de compromisso restante passa por aqui; nenhum consumidor
 * recalcula por conta própria.
 *
 * Regras que este motor garante:
 *  - Identidade de ocorrência = hash(tag de versão, chave do cronograma, sequência).
 *    Data e revisão nunca participam: mudar calendário, insumos ou janela não muda a
 *    identidade.
 *  - Definição vigente = maior revisão com sequência efetiva menor ou igual à sequência
 *    da ocorrência. Referência vigente = maior ordem econômica com sequência efetiva
 *    menor ou igual; confirmações válidas conflitantes na mesma ordem são AMBIGUOUS e
 *    bloqueiam a propagação.
 *  - Valor calculado reutiliza ALT_CLS_AmortizationSchedule (nenhuma fórmula nova) com a
 *    fórmula original completa e a sequência absoluta estável; ESTIMATED usa o valor de
 *    referência em vez de fórmula.
 *  - Persistidas e virtuais são disjuntas e contadas uma única vez; uma lacuna
 *    pós-rastreamento aparece como virtual, nunca duplicada com a persistida.
 *  - Vencidas e futuras são separadas; sequências abaixo do início do rastreamento
 *    permanecem desconhecidas e nunca são geradas nem somadas.
 *  - Nada é apresentado como total completo quando não é: recorrência indefinida, limite
 *    de avaliação ou divergência de versão devolvem estados explícitos.
 *
 * Acesso: as leituras usam SYSTEM_MODE para campos internos derivados e de evidência; a
 * autoridade do titular é conferida na porta de entrada (ALT_CLS_FinancialScheduleService),
 * que é o único comando público desta fatia. CRUD/FLS nativos continuam valendo para a
 * exposição declarativa dos permission sets.
 */
public with sharing class ALT_CLS_ScheduleProjection {
  public static final String OUTCOME_OK = 'OK';
  public static final String OUTCOME_STALE = 'STALE';
  public static final String OUTCOME_NOT_FOUND = 'NOT_FOUND';
  public static final String OUTCOME_INVALID = 'INVALID';
  public static final String OUTCOME_AMBIGUOUS = 'AMBIGUOUS';
  public static final String OUTCOME_UNSUPPORTED = 'UNSUPPORTED';
  public static final String OUTCOME_FORBIDDEN = 'FORBIDDEN';

  public static final String METHOD_ESTIMATED = 'ESTIMATED';
  public static final String METHOD_INSTALLMENT = 'INSTALLMENT';
  public static final String METHOD_RECURRING = 'RECURRING';
  public static final String KIND_COMPENSATION = 'COMPENSATION';
  public static final String STATE_CANCELLED = 'CANCELLED';
  public static final String STATUS_CONFIRMED = 'CONFIRMED';

  /** Tag de versão da identidade de ocorrência. Alterá-la troca todas as identidades. */
  public static final String OCCURRENCE_TAG = 'axf103-occ-v1';
  /** Preâmbulo versionado do token de idempotência de 36 caracteres do FTX. */
  public static final String CLIENT_REQUEST_PREFIX = 'AXF1';
  public static final Integer CLIENT_REQUEST_LENGTH = 36;

  /**
   * Teto de avaliação de uma leitura. Não é uma afirmação de capacidade da plataforma:
   * acima dele a leitura devolve continuação explícita em vez de truncar um total como
   * completo.
   */
  public static final Integer MAX_EVALUATED_SEQUENCES = 1000;

  public class ProjectionException extends Exception {
  }

  public class ProjectionInput {
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public Date asOfDate;
    @AuraEnabled
    public Integer throughSequence;
  }

  public class OccurrenceLine {
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public String occurrenceKey;
    @AuraEnabled
    public Date nominalDueDate;
    @AuraEnabled
    public Date effectiveDueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Boolean persisted = false;
    @AuraEnabled
    public Boolean estimated = false;
    @AuraEnabled
    public Boolean confirmed = false;
    @AuraEnabled
    public Boolean overdue = false;
    @AuraEnabled
    public Id definitionId;
    @AuraEnabled
    public Id referenceId;
    @AuraEnabled
    public Id transactionId;
  }

  public class ProjectionResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public String scheduleKey;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Date asOfDate;
    @AuraEnabled
    public Integer trackingStartSequence;
    @AuraEnabled
    public Integer throughSequence;
    @AuraEnabled
    public Integer evaluatedCount = 0;
    @AuraEnabled
    public Integer persistedCount = 0;
    @AuraEnabled
    public Integer virtualCount = 0;
    @AuraEnabled
    public Integer overdueCount = 0;
    @AuraEnabled
    public Integer futureCount = 0;
    @AuraEnabled
    public Integer unconfirmedCount = 0;
    @AuraEnabled
    public Decimal overdueTotal = 0;
    @AuraEnabled
    public Decimal futureTotal = 0;
    @AuraEnabled
    public Decimal totalRemaining = 0;
    @AuraEnabled
    public Boolean estimated = false;
    /** Todos os componentes do total são estimados: nenhum valor confirmado o sustenta. */
    @AuraEnabled
    public Boolean fullyEstimated = false;
    /** Soma dos componentes confirmados (não estimados) dentro da faixa avaliada. */
    @AuraEnabled
    public Decimal confirmedTotal = 0;
    /** Soma dos componentes estimados dentro da faixa avaliada. */
    @AuraEnabled
    public Decimal estimatedTotal = 0;
    /** Meses de calendário do horizonte lido, persistidos na raiz do cronograma. */
    @AuraEnabled
    public Integer horizonMonths;
    /** Último dia do mês do horizonte: fim do mês corrente mais `horizonMonths - 1`. */
    @AuraEnabled
    public Date horizonEndDate;
    /** Quantidade de ocorrências com vencimento efetivo dentro do horizonte. */
    @AuraEnabled
    public Integer horizonCount = 0;
    /** Total explícito do horizonte solicitado (L43), sempre exposto — nunca implícito. */
    @AuraEnabled
    public Decimal horizonTotal = 0;
    /**
     * O total devolvido cobre integralmente a faixa avaliada: nenhuma recorrência indefinida,
     * nenhum truncamento de avaliação ou paginação. É a completude de COBERTURA.
     */
    @AuraEnabled
    public Boolean coverageComplete = false;
    /**
     * `complete` é a única leitura que um consumidor faz do total: ele só é verdadeiro quando a
     * cobertura é completa E existe ao menos um componente confirmado. Um total integralmente
     * estimado nunca é apresentado como completo (L46).
     */
    @AuraEnabled
    public Boolean complete = false;
    @AuraEnabled
    public Boolean unbounded = false;
    @AuraEnabled
    public Integer continuationSequence;
    @AuraEnabled
    public Long capturedProjectionRevision;
    @AuraEnabled
    public Long capturedFinancialVersion;
    /**
     * Ponteiros VIGENTES capturados na leitura. Eles participam da rechecagem de quem ESCREVE:
     * um ponteiro de definição trocado entre a leitura e o lock produziria linhas apontando para a
     * definição antiga sob a etiqueta da revisão nova, e é essa comparação que devolve STALE.
     */
    @AuraEnabled
    public Id capturedActiveDefinition;
    @AuraEnabled
    public Id capturedActiveReference;
    /** Fronteira de encerramento capturada na leitura, comparada na rechecagem. */
    @AuraEnabled
    public Date capturedTerminationDate;
    @AuraEnabled
    public Long recheckedProjectionRevision;
    @AuraEnabled
    public Long recheckedFinancialVersion;
    @AuraEnabled
    public Date recheckedTerminationDate;
    @AuraEnabled
    public List<OccurrenceLine> lines = new List<OccurrenceLine>();
  }

  /** Hook de teste: simula a releitura de versões após as leituras persistidas. */
  @TestVisible
  private static AXF_OBJ_FinancialSchedule__c recheckOverride;

  /**
   * Autoridade de titular deste motor. O motor lê com SYSTEM_MODE por causa dos campos
   * internos derivados e de evidência, então ele NÃO pode ser alcançável como atalho de
   * leitura: `project()` confere a autoridade do titular antes de devolver qualquer dado.
   */
  @TestVisible
  private static Set<Id> authorizedOverride;

  /**
   * Seam de teste do predicado de encerramento. O encerramento efetivo é entregue pela fatia
   * seguinte (recibo SCH TERMINATE); aqui o predicado do leitor já existe e é coberto, mas
   * `AXF_FSC_DAT_TerminationDate__c` só é gravável pelo serviço autorizado.
   */
  @TestVisible
  private static Date terminationOverride;

  /** Limite efetivo de magnitude já em uso (Number(16,2)); não alarga metadado existente. */
  public static final Decimal MAX_EFFECTIVE_AMOUNT = 99999999999999.99;

  public static ProjectionResult project(ProjectionInput input) {
    ProjectionResult result = new ProjectionResult();
    if (input == null || input.scheduleId == null) {
      return fail(result, OUTCOME_INVALID, 'Cronograma é obrigatório.');
    }
    if (input.throughSequence != null && input.throughSequence < 1) {
      // Um pedido de paginação inválido não é ignorado em silêncio devolvendo o total completo.
      return fail(
        result,
        OUTCOME_INVALID,
        'A sequência limite da paginação deve ser maior ou igual a 1.'
      );
    }

    List<AXF_OBJ_FinancialSchedule__c> roots = [
      SELECT
        Id,
        AXF_FSC_EXI_ScheduleKey__c,
        AXF_FSC_PKL_State__c,
        AXF_FSC_PKL_Direction__c,
        AXF_FSC_TXT_CurrencyIsoCode__c,
        AXF_FSC_LKP_Account__c,
        AXF_FSC_NUM_TrackingStartSequence__c,
        AXF_FSC_NUM_HorizonMonths__c,
        AXF_FSC_NUM_ProjectionRevision__c,
        AXF_FSC_NUM_AppliedRevision__c,
        AXF_FSC_NUM_FinancialVersion__c,
        AXF_FSC_DAT_TerminationDate__c,
        AXF_FSC_LKP_ActiveDefinition__c,
        AXF_FSC_LKP_ActiveReference__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :input.scheduleId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (roots.isEmpty()) {
      return fail(
        result,
        OUTCOME_NOT_FOUND,
        'Cronograma não encontrado neste escopo.'
      );
    }

    AXF_OBJ_FinancialSchedule__c root = roots[0];
    result.scheduleId = root.Id;
    if (!isAuthorized(root.AXF_FSC_LKP_Account__c)) {
      return fail(
        result,
        OUTCOME_FORBIDDEN,
        'Você não tem acesso a esta entidade titular.'
      );
    }
    result.scheduleKey = root.AXF_FSC_EXI_ScheduleKey__c;
    result.state = root.AXF_FSC_PKL_State__c;
    result.direction = root.AXF_FSC_PKL_Direction__c;
    result.currencyIsoCode = root.AXF_FSC_TXT_CurrencyIsoCode__c;
    result.capturedProjectionRevision = revisionOf(root);
    result.capturedFinancialVersion = financialVersionOf(root);
    result.capturedActiveDefinition = root.AXF_FSC_LKP_ActiveDefinition__c;
    result.capturedActiveReference = root.AXF_FSC_LKP_ActiveReference__c;
    Date asOf = (input.asOfDate == null) ? Date.today() : input.asOfDate;
    result.asOfDate = asOf;
    Integer horizon = (root.AXF_FSC_NUM_HorizonMonths__c == null)
      ? 12
      : root.AXF_FSC_NUM_HorizonMonths__c.intValue();
    Integer trackingStart = (root.AXF_FSC_NUM_TrackingStartSequence__c == null)
      ? 1
      : root.AXF_FSC_NUM_TrackingStartSequence__c.intValue();
    result.trackingStartSequence = trackingStart;
    result.horizonMonths = horizon;
    Date horizonEnd = ALT_CLS_ScheduleCalendar.monthEndShifted(
      asOf,
      horizon - 1
    );
    result.horizonEndDate = horizonEnd;

    List<AXF_OBJ_ScheduleDefinition__c> definitions = [
      SELECT
        Id,
        AXF_SDF_NUM_Revision__c,
        AXF_SDF_NUM_EffectiveSequence__c,
        AXF_SDF_PKL_Method__c,
        AXF_SDF_NUM_TotalInstallments__c,
        AXF_SDF_NUM_FirstSequence__c,
        AXF_SDF_DAT_FirstDueDate__c,
        AXF_SDF_NUM_AnchorDay__c,
        AXF_SDF_NUM_PeriodMonths__c,
        AXF_SDF_NUM_PeriodDays__c,
        AXF_SDF_NUM_Principal__c,
        AXF_SDF_NUM_PeriodRate__c,
        AXF_SDF_NUM_FixedValue__c,
        AXF_SDF_NUM_RecurringFee__c,
        AXF_SDF_NUM_UpfrontFee__c,
        AXF_SDF_NUM_InitialReferenceAmount__c
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE AXF_SDF_LKP_Schedule__c = :root.Id
      WITH SYSTEM_MODE
      ORDER BY AXF_SDF_NUM_Revision__c ASC
    ];
    if (definitions.isEmpty()) {
      return fail(
        result,
        OUTCOME_INVALID,
        'O cronograma não possui definição vigente; nada pode ser projetado.'
      );
    }

    List<AXF_OBJ_ScheduleReference__c> references = [
      SELECT
        Id,
        AXF_SRF_NUM_EconomicSequence__c,
        AXF_SRF_NUM_EffectiveSequence__c,
        AXF_SRF_NUM_RecurringAmount__c,
        AXF_SRF_PKL_Kind__c,
        AXF_SRF_LKP_Compensates__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE AXF_SRF_LKP_Schedule__c = :root.Id
      WITH SYSTEM_MODE
      ORDER BY AXF_SRF_NUM_EconomicSequence__c ASC, Id ASC
    ];

    List<AXF_OBJ_FinancialTransaction__c> persistedRows = [
      SELECT
        Id,
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_EXI_OccurrenceKey__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_DAT_NominalDueDate__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_BOL_BasisFrozen__c,
        AXF_FTX_CHK_IsEstimated__c,
        AXF_FTX_PKL_ScheduleState__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_LKP_ScheduleReference__c,
        AXF_FTX_LKP_ScheduleDefinition__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :root.Id
      WITH SYSTEM_MODE
    ];
    Map<Integer, AXF_OBJ_FinancialTransaction__c> persisted = new Map<Integer, AXF_OBJ_FinancialTransaction__c>();
    Integer highestPersisted = 0;
    for (AXF_OBJ_FinancialTransaction__c row : persistedRows) {
      if (row.AXF_FTX_NUM_Sequence__c == null) {
        continue;
      }
      Integer sequence = row.AXF_FTX_NUM_Sequence__c.intValue();
      if (sequence < trackingStart) {
        // Histórico pré-rastreamento permanece desconhecido: nunca é somado nem listado.
        continue;
      }
      if (persisted.containsKey(sequence)) {
        // Duas linhas persistidas para a mesma identidade (cronograma, sequência): a leitura
        // não escolhe uma delas arbitrariamente nem soma as duas.
        return fail(
          result,
          OUTCOME_INVALID,
          'Há mais de uma ocorrência persistida para a mesma identidade (sequência ' +
            sequence +
            '). Resolva a duplicidade antes de ler o compromisso restante.'
        );
      }
      persisted.put(sequence, row);
      if (sequence > highestPersisted) {
        highestPersisted = sequence;
      }
    }

    Integer lastCovered = lastCoveredSequence(definitions);
    Boolean unbounded = lastCovered == null;
    result.unbounded = unbounded;

    Integer upperBound = (lastCovered == null)
      ? trackingStart + MAX_EVALUATED_SEQUENCES - 1
      : Math.max(lastCovered, highestPersisted);
    Integer evaluationCap = trackingStart + MAX_EVALUATED_SEQUENCES - 1;
    Boolean truncated = false;
    if (upperBound > evaluationCap) {
      upperBound = evaluationCap;
      truncated = true;
    }
    if (
      input.throughSequence != null &&
      input.throughSequence > 0 &&
      input.throughSequence < upperBound
    ) {
      upperBound = input.throughSequence;
      truncated = true;
    }
    result.throughSequence = upperBound;

    if (
      isAmbiguous(references, upperBound) ||
      isAmbiguous(references, lastCovered)
    ) {
      return fail(
        result,
        OUTCOME_AMBIGUOUS,
        'Há confirmações de referência conflitantes na mesma ordem econômica. O total fica bloqueado até a resolução explícita.'
      );
    }

    Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>> formulas = new Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>>();
    Date terminationDate = (terminationOverride != null)
      ? terminationOverride
      : root.AXF_FSC_DAT_TerminationDate__c;
    result.capturedTerminationDate = terminationDate;
    Integer lastEvaluatedSequence = trackingStart - 1;
    // Referências retiradas: uma compensação identifica a referência que ela neutraliza, e essa
    // referência não pode continuar sendo selecionada nem continuar fornecendo valor estimado.
    Set<Id> compensatedReferences = compensatedReferenceIds(references);
    Set<Id> scheduleDefinitionIds = new Set<Id>();
    for (AXF_OBJ_ScheduleDefinition__c definition : definitions) {
      scheduleDefinitionIds.add(definition.Id);
    }
    Set<Id> scheduleReferenceIds = new Set<Id>();
    for (AXF_OBJ_ScheduleReference__c reference : references) {
      scheduleReferenceIds.add(reference.Id);
    }

    for (Integer sequence = trackingStart; sequence <= upperBound; sequence++) {
      AXF_OBJ_ScheduleDefinition__c definition = resolveDefinition(
        definitions,
        sequence
      );
      if (definition == null) {
        // Uma sequência rastreada sem definição efetiva não é omitida em silêncio: omitir
        // deixaria o resultado rotulado completo com uma lacuna dentro do intervalo.
        return fail(
          result,
          OUTCOME_INVALID,
          'Não há definição efetiva para a sequência ' +
            sequence +
            ' dentro do intervalo rastreado; a projeção não é apresentada como completa.'
        );
      }
      Integer definitionLast = lastSequenceOf(definition);
      if (definitionLast != null && sequence > definitionLast) {
        if (lastCovered != null && sequence >= lastCovered) {
          break;
        }
        continue;
      }

      Date nominal;
      try {
        nominal = ALT_CLS_ScheduleCalendar.nominalDueDate(
          definition.AXF_SDF_DAT_FirstDueDate__c,
          definition.AXF_SDF_NUM_FirstSequence__c == null
            ? 1
            : definition.AXF_SDF_NUM_FirstSequence__c.intValue(),
          definition.AXF_SDF_NUM_PeriodMonths__c == null
            ? null
            : definition.AXF_SDF_NUM_PeriodMonths__c.intValue(),
          // AXF-155: periodicidade em dias (sem âncora) quando a definição a declara.
          definition.AXF_SDF_NUM_PeriodDays__c == null
            ? null
            : definition.AXF_SDF_NUM_PeriodDays__c.intValue(),
          definition.AXF_SDF_NUM_AnchorDay__c == null
            ? null
            : definition.AXF_SDF_NUM_AnchorDay__c.intValue(),
          sequence
        );
      } catch (ALT_CLS_ScheduleCalendar.CalendarException calendar) {
        return fail(
          result,
          OUTCOME_INVALID,
          'Definição vigente inválida para a sequência ' +
            sequence +
            ': ' +
            calendar.getMessage()
        );
      }

      AXF_OBJ_FinancialTransaction__c row = persisted.get(sequence);
      if (unbounded && row == null && nominal > horizonEnd) {
        // Recorrência indefinida: devolve o horizonte solicitado, nunca um total de vida.
        break;
      }
      // A fronteira do encerramento é comparada pelo vencimento EFETIVO: o `dueDate` do FTX é a
      // autoridade (o nominal preserva apenas a âncora do mês).
      Date effectiveDueDate = (row == null ||
        row.AXF_FTX_DAT_DueDate__c == null)
        ? nominal
        : row.AXF_FTX_DAT_DueDate__c;
      if (terminationDate != null && effectiveDueDate > terminationDate) {
        // Obrigações futuras elegíveis são logicamente CANCELLED pelo predicado da revisão,
        // persistidas ou virtuais. Base congelada ou ocorrência confirmada permanece protegida.
        Boolean protectedRow =
          row != null &&
          (row.AXF_FTX_BOL_BasisFrozen__c == true ||
          row.AXF_FTX_PKL_Status__c == STATUS_CONFIRMED);
        if (!protectedRow) {
          continue;
        }
      }
      if (row != null && row.AXF_FTX_PKL_ScheduleState__c == STATE_CANCELLED) {
        continue;
      }

      // A sequência só é uma identidade quando a linha persistida carrega a identidade
      // calculada para essa posição, e os ponteiros de definição/referência pertencem a ESTE
      // cronograma: uma linha sob outra identidade não conta como a esperada.
      if (row != null) {
        String expectedKey = occurrenceKey(result.scheduleKey, sequence);
        if (row.AXF_FTX_EXI_OccurrenceKey__c != expectedKey) {
          return fail(
            result,
            OUTCOME_INVALID,
            'A ocorrência persistida da sequência ' +
              sequence +
              ' não carrega a identidade calculada para esta posição; o compromisso restante não é apresentado como completo.'
          );
        }
        if (
          row.AXF_FTX_LKP_ScheduleDefinition__c != null &&
          !scheduleDefinitionIds.contains(row.AXF_FTX_LKP_ScheduleDefinition__c)
        ) {
          return fail(
            result,
            OUTCOME_INVALID,
            'A ocorrência persistida da sequência ' +
              sequence +
              ' aponta uma definição que não pertence a este cronograma.'
          );
        }
        if (
          row.AXF_FTX_LKP_ScheduleReference__c != null &&
          !scheduleReferenceIds.contains(row.AXF_FTX_LKP_ScheduleReference__c)
        ) {
          return fail(
            result,
            OUTCOME_INVALID,
            'A ocorrência persistida da sequência ' +
              sequence +
              ' aponta uma referência que não pertence a este cronograma.'
          );
        }
      }

      AXF_OBJ_ScheduleReference__c reference = resolveReference(
        references,
        sequence,
        compensatedReferences
      );
      Decimal resolved = resolvedAmount(
        definition,
        reference,
        sequence,
        formulas
      );
      if (resolved == null) {
        return fail(
          result,
          OUTCOME_UNSUPPORTED,
          'A definição vigente não produz valor para a sequência ' +
            sequence +
            '.'
        );
      }

      OccurrenceLine line = new OccurrenceLine();
      line.sequence = sequence;
      line.occurrenceKey = occurrenceKey(result.scheduleKey, sequence);
      line.nominalDueDate = nominal;
      line.definitionId = definition.Id;
      line.referenceId = (reference == null) ? null : reference.Id;
      if (row == null) {
        line.amount = resolved;
        line.effectiveDueDate = nominal;
        line.estimated = true;
        line.confirmed = false;
      } else {
        line.persisted = true;
        line.transactionId = row.Id;
        line.effectiveDueDate = effectiveDueDate;
        // Base corrente persistida; sem ela, a magnitude original imutável é a base congelada
        // de uma ocorrência já referenciada/adotada — a referência do cronograma não a
        // substitui nem a recalcula.
        line.amount = (row.AXF_FTX_NUM_CurrentBasis__c != null)
          ? row.AXF_FTX_NUM_CurrentBasis__c
          : row.AXF_FTX_NUM_Magnitude__c;
        line.confirmed =
          row.AXF_FTX_PKL_Status__c == STATUS_CONFIRMED &&
          row.AXF_FTX_CHK_IsEstimated__c != true;
        line.estimated =
          definition.AXF_SDF_PKL_Method__c == METHOD_ESTIMATED ||
          !line.confirmed;
      }
      if (
        line.amount == null ||
        line.amount > MAX_EFFECTIVE_AMOUNT ||
        line.amount < 0
      ) {
        return fail(
          result,
          OUTCOME_INVALID,
          'Valor fora do limite efetivo de magnitude para a sequência ' +
            sequence +
            '.'
        );
      }
      line.overdue = line.effectiveDueDate < asOf;

      result.lines.add(line);
      lastEvaluatedSequence = sequence;
      result.evaluatedCount++;
      if (line.persisted) {
        result.persistedCount++;
      } else {
        result.virtualCount++;
      }
      if (!line.confirmed) {
        result.unconfirmedCount++;
      }
      if (line.estimated) {
        result.estimated = true;
        result.estimatedTotal += line.amount;
      } else {
        result.confirmedTotal += line.amount;
      }
      if (line.effectiveDueDate <= horizonEnd) {
        result.horizonCount++;
        result.horizonTotal += line.amount;
      }
      if (line.overdue) {
        result.overdueCount++;
        result.overdueTotal += line.amount;
      } else {
        result.futureCount++;
        result.futureTotal += line.amount;
      }
    }

    result.overdueTotal = result.overdueTotal.setScale(2);
    result.futureTotal = result.futureTotal.setScale(2);
    result.estimatedTotal = result.estimatedTotal.setScale(2);
    result.confirmedTotal = result.confirmedTotal.setScale(2);
    result.horizonTotal = result.horizonTotal.setScale(2);
    result.totalRemaining = (result.overdueTotal + result.futureTotal)
      .setScale(2);
    result.coverageComplete = !unbounded && !truncated;
    result.fullyEstimated =
      result.evaluatedCount > 0 &&
      result.confirmedTotal == 0;
    // Um total integralmente estimado nunca é devolvido como completo: `complete` é a leitura
    // que um consumidor faz do total, e a cobertura completa é exposta separadamente.
    result.complete = result.coverageComplete && !result.fullyEstimated;
    if (!result.coverageComplete) {
      result.continuationSequence = lastEvaluatedSequence + 1;
    }

    AXF_OBJ_FinancialSchedule__c rechecked = recheck(root.Id);
    result.recheckedProjectionRevision = revisionOf(rechecked);
    result.recheckedFinancialVersion = financialVersionOf(rechecked);
    // O seam de teste representa a fronteira de encerramento vigente: com ele ativo, é ele que a
    // rechecagem observa — a divergência real continua sendo detectada pelo campo persistido.
    result.recheckedTerminationDate = (terminationOverride != null)
      ? terminationOverride
      : terminationOf(rechecked);
    if (
      rechecked == null ||
      result.recheckedProjectionRevision != result.capturedProjectionRevision ||
      result.recheckedFinancialVersion != result.capturedFinancialVersion ||
      result.recheckedTerminationDate != result.capturedTerminationDate
    ) {
      result.lines = new List<OccurrenceLine>();
      result.overdueTotal = null;
      result.futureTotal = null;
      result.totalRemaining = null;
      result.horizonTotal = null;
      result.estimatedTotal = null;
      result.confirmedTotal = null;
      result.complete = false;
      result.coverageComplete = false;
      return fail(
        result,
        OUTCOME_STALE,
        'A revisão do cronograma mudou durante a leitura. Nenhum total é devolvido como completo.'
      );
    }

    result.outcome = OUTCOME_OK;
    if (result.evaluatedCount == 0) {
      // Total zero legítimo: nada resta porque as ocorrências rastreadas foram encerradas ou
      // canceladas pelo predicado da revisão — não é o mesmo que uma leitura sem cobertura.
      result.overdueTotal = 0.00;
      result.futureTotal = 0.00;
      result.totalRemaining = 0.00;
      result.horizonTotal = 0.00;
      result.estimatedTotal = 0.00;
      result.confirmedTotal = 0.00;
      result.message = 'Nenhuma obrigação restante: as ocorrências rastreadas foram encerradas ou canceladas.';
      return result;
    }
    result.message =
      result.evaluatedCount +
      ' ocorrência(s) projetada(s) — ' +
      result.overdueCount +
      ' vencida(s) e ' +
      result.futureCount +
      ' futura(s).';
    return result;
  }

  /**
   * @description AXF-156 — a MESMA seleção de definição vigente deste motor, exposta aos leitores
   * que resolvem as parcelas virtuais de vários cronogramas numa só leitura (lista de
   * financiamentos), sem uma seleção paralela.
   */
  public static AXF_OBJ_ScheduleDefinition__c effectiveDefinition(
    List<AXF_OBJ_ScheduleDefinition__c> definitions,
    Integer sequence
  ) {
    return resolveDefinition(definitions, sequence);
  }

  /**
   * @description Define a revisão de definição vigente para uma sequência: a maior revisão
   * cuja sequência efetiva não ultrapassa a sequência pedida.
   */
  @TestVisible
  private static AXF_OBJ_ScheduleDefinition__c resolveDefinition(
    List<AXF_OBJ_ScheduleDefinition__c> definitions,
    Integer sequence
  ) {
    AXF_OBJ_ScheduleDefinition__c selected;
    for (AXF_OBJ_ScheduleDefinition__c candidate : definitions) {
      Integer effective = (candidate.AXF_SDF_NUM_EffectiveSequence__c == null)
        ? 1
        : candidate.AXF_SDF_NUM_EffectiveSequence__c.intValue();
      if (effective > sequence) {
        continue;
      }
      if (
        selected == null ||
        revisionValue(candidate.AXF_SDF_NUM_Revision__c) >=
        revisionValue(selected.AXF_SDF_NUM_Revision__c)
      ) {
        selected = candidate;
      }
    }
    return selected;
  }

  /**
   * @description Referências retiradas por uma compensação. A compensação identifica a
   * referência neutralizada pelo campo `Compensates`; ela deixa de ser selecionável e deixa de
   * fornecer valor estimado, para não inflar o total.
   */
  private static Set<Id> compensatedReferenceIds(
    List<AXF_OBJ_ScheduleReference__c> references
  ) {
    Set<Id> compensated = new Set<Id>();
    for (AXF_OBJ_ScheduleReference__c candidate : references) {
      if (
        candidate.AXF_SRF_PKL_Kind__c == KIND_COMPENSATION &&
        candidate.AXF_SRF_LKP_Compensates__c != null
      ) {
        compensated.add(candidate.AXF_SRF_LKP_Compensates__c);
      }
    }
    return compensated;
  }

  /**
   * @description Referência vigente para uma sequência: a maior ordem econômica com sequência
   * efetiva não superior à sequência pedida. Compensações identificam referências retiradas e
   * não participam da seleção — nem elas, nem a referência que elas neutralizam.
   */
  @TestVisible
  private static AXF_OBJ_ScheduleReference__c resolveReference(
    List<AXF_OBJ_ScheduleReference__c> references,
    Integer sequence
  ) {
    return resolveReference(
      references,
      sequence,
      compensatedReferenceIds(references)
    );
  }

  private static AXF_OBJ_ScheduleReference__c resolveReference(
    List<AXF_OBJ_ScheduleReference__c> references,
    Integer sequence,
    Set<Id> compensatedReferences
  ) {
    AXF_OBJ_ScheduleReference__c selected;
    for (AXF_OBJ_ScheduleReference__c candidate : references) {
      if (candidate.AXF_SRF_PKL_Kind__c == KIND_COMPENSATION) {
        continue;
      }
      if (compensatedReferences.contains(candidate.Id)) {
        continue;
      }
      Integer effective = (candidate.AXF_SRF_NUM_EffectiveSequence__c == null)
        ? 1
        : candidate.AXF_SRF_NUM_EffectiveSequence__c.intValue();
      if (effective > sequence) {
        continue;
      }
      Integer economic = (candidate.AXF_SRF_NUM_EconomicSequence__c == null)
        ? 0
        : candidate.AXF_SRF_NUM_EconomicSequence__c.intValue();
      if (selected == null) {
        selected = candidate;
        continue;
      }
      Integer best = (selected.AXF_SRF_NUM_EconomicSequence__c == null)
        ? 0
        : selected.AXF_SRF_NUM_EconomicSequence__c.intValue();
      if (economic > best) {
        selected = candidate;
      }
    }
    return selected;
  }

  /**
   * @description Detecta confirmações válidas conflitantes na mesma ordem econômica: duas
   * confirmações na MESMA ordem econômica conflitam, mesmo com o mesmo valor, porque a ordem
   * econômica é a autoridade de precedência e nenhuma delas vence a outra. Carimbo de tempo não
   * decide essa precedência; uma retirada por compensação sai da disputa.
   */
  @TestVisible
  private static Boolean isAmbiguous(
    List<AXF_OBJ_ScheduleReference__c> references,
    Integer throughSequence
  ) {
    if (throughSequence == null) {
      return false;
    }
    Set<Id> compensated = compensatedReferenceIds(references);
    Map<Integer, Integer> confirmations = new Map<Integer, Integer>();
    for (AXF_OBJ_ScheduleReference__c candidate : references) {
      if (candidate.AXF_SRF_PKL_Kind__c == KIND_COMPENSATION) {
        continue;
      }
      if (compensated.contains(candidate.Id)) {
        continue;
      }
      Integer effective = (candidate.AXF_SRF_NUM_EffectiveSequence__c == null)
        ? 1
        : candidate.AXF_SRF_NUM_EffectiveSequence__c.intValue();
      if (effective > throughSequence) {
        continue;
      }
      Integer economic = (candidate.AXF_SRF_NUM_EconomicSequence__c == null)
        ? 0
        : candidate.AXF_SRF_NUM_EconomicSequence__c.intValue();
      Integer count = confirmations.get(economic);
      confirmations.put(economic, (count == null) ? 1 : count + 1);
    }
    for (Integer count : confirmations.values()) {
      if (count > 1) {
        return true;
      }
    }
    return false;
  }

  /**
   * @description Última sequência coberta pelas definições; nulo quando há recorrência
   * indefinida, que nunca produz um total de vida finito.
   */
  @TestVisible
  private static Integer lastCoveredSequence(
    List<AXF_OBJ_ScheduleDefinition__c> definitions
  ) {
    Integer last;
    for (AXF_OBJ_ScheduleDefinition__c definition : definitions) {
      Integer candidate = lastSequenceOf(definition);
      if (candidate == null) {
        return null;
      }
      if (last == null || candidate > last) {
        last = candidate;
      }
    }
    return last;
  }

  /** @description Última sequência descrita por uma definição, ou nulo se indefinida. */
  @TestVisible
  private static Integer lastSequenceOf(
    AXF_OBJ_ScheduleDefinition__c definition
  ) {
    if (
      definition.AXF_SDF_NUM_TotalInstallments__c == null ||
      definition.AXF_SDF_NUM_FirstSequence__c == null
    ) {
      return null;
    }
    return definition.AXF_SDF_NUM_FirstSequence__c.intValue() +
      definition.AXF_SDF_NUM_TotalInstallments__c.intValue() -
      1;
  }

  /** @description Identidade determinística da ocorrência (64 hex minúsculos). */
  public static String occurrenceKey(String scheduleKey, Integer sequence) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{ OCCURRENCE_TAG, scheduleKey, sequence }
    );
  }

  /**
   * @description Token determinístico de 36 caracteres derivado da chave completa da
   * ocorrência (preâmbulo versionado de 4 caracteres mais 32 hex). A chave completa continua
   * sendo a autoridade: colisão de chave truncada com identidade diferente é CONFLICT, nunca
   * replay bem-sucedido.
   */
  public static String clientRequestId(String fullOccurrenceKey) {
    if (String.isBlank(fullOccurrenceKey)) {
      throw new ProjectionException(
        'A chave completa da ocorrência é obrigatória.'
      );
    }
    String truncated = fullOccurrenceKey.substring(0, 32);
    return CLIENT_REQUEST_PREFIX + truncated;
  }

  /** @description Valor resolvido de uma ocorrência, pela fórmula aprovada ou pela referência. */
  private static Decimal resolvedAmount(
    AXF_OBJ_ScheduleDefinition__c definition,
    AXF_OBJ_ScheduleReference__c reference,
    Integer sequence,
    Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>> formulas
  ) {
    String method = definition.AXF_SDF_PKL_Method__c;
    if (method == METHOD_ESTIMATED) {
      if (
        reference != null &&
        reference.AXF_SRF_NUM_RecurringAmount__c != null
      ) {
        return reference.AXF_SRF_NUM_RecurringAmount__c.setScale(2);
      }
      return (definition.AXF_SDF_NUM_InitialReferenceAmount__c == null)
        ? null
        : definition.AXF_SDF_NUM_InitialReferenceAmount__c.setScale(2);
    }

    List<ALT_CLS_AmortizationSchedule.Occurrence> occurrences = formulas.get(
      definition.Id
    );
    if (occurrences == null) {
      occurrences = generateOccurrences(definition);
      formulas.put(definition.Id, occurrences);
    }
    if (occurrences.isEmpty()) {
      return null;
    }
    Integer firstSequence = (definition.AXF_SDF_NUM_FirstSequence__c == null)
      ? 1
      : definition.AXF_SDF_NUM_FirstSequence__c.intValue();
    Integer index = sequence - firstSequence;
    if (index < 0 || index >= occurrences.size()) {
      return null;
    }
    return occurrences[index].payment;
  }

  /**
   * @description Gera uma única vez, por definição, as ocorrências da fórmula aprovada. A
   * autoridade da fórmula é ALT_CLS_AmortizationSchedule; nenhuma parcela é recalculada por
   * consumidor.
   *
   * Pública porque a MATERIALIZAÇÃO da reposição rolante (fatia 2) precisa das mesmas porções da
   * criação a partir da definição JÁ PERSISTIDA: a autoridade de decomposição continua sendo uma
   * só, e a porta de escrita não reimplementa a fórmula.
   */
  public static List<ALT_CLS_AmortizationSchedule.Occurrence> generateOccurrences(
    AXF_OBJ_ScheduleDefinition__c definition
  ) {
    List<ALT_CLS_AmortizationSchedule.Occurrence> empty = new List<ALT_CLS_AmortizationSchedule.Occurrence>();
    Integer installments = (definition.AXF_SDF_NUM_TotalInstallments__c == null)
      ? null
      : definition.AXF_SDF_NUM_TotalInstallments__c.intValue();
    if (
      installments == null ||
      installments < 1 ||
      definition.AXF_SDF_DAT_FirstDueDate__c == null
    ) {
      return empty;
    }
    ALT_CLS_AmortizationSchedule.ScheduleInput input = new ALT_CLS_AmortizationSchedule.ScheduleInput();
    input.modality = definition.AXF_SDF_PKL_Method__c;
    // AXF-156: uma revisão de parcelamento com valor fixo (edição do valor da parcela) usa a
    // fórmula aprovada de valor fixo por ocorrência (política §4), sem fórmula nova.
    if (
      input.modality == METHOD_INSTALLMENT &&
      definition.AXF_SDF_NUM_FixedValue__c != null
    ) {
      input.modality = METHOD_RECURRING;
    }
    input.principal = definition.AXF_SDF_NUM_Principal__c;
    input.installments = installments;
    input.periodRate = definition.AXF_SDF_NUM_PeriodRate__c;
    input.firstDueDate = definition.AXF_SDF_DAT_FirstDueDate__c;
    input.fixedValue = definition.AXF_SDF_NUM_FixedValue__c;
    input.flatFeePerInstallment = definition.AXF_SDF_NUM_RecurringFee__c;
    input.upfrontFee = definition.AXF_SDF_NUM_UpfrontFee__c;
    ALT_CLS_AmortizationSchedule.ScheduleResult generated = ALT_CLS_AmortizationSchedule.generate(
      input
    );
    if (generated.outcome != 'OK') {
      return empty;
    }
    return generated.occurrences;
  }

  /**
   * @description Autoridade do titular (AXF-3). Sem ela o motor seria um atalho de leitura:
   * ele lê com SYSTEM_MODE e a visibilidade nativa sozinha não é uma autorização.
   */
  private static Boolean isAuthorized(Id accountId) {
    if (accountId == null) {
      return false;
    }
    if (authorizedOverride != null) {
      return authorizedOverride.contains(accountId);
    }
    for (
      AXF_CLS_AuthorizedContextService.ContextView view : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      if (view.accountId == accountId) {
        return true;
      }
    }
    return false;
  }

  private static AXF_OBJ_FinancialSchedule__c recheck(Id scheduleId) {
    if (recheckOverride != null) {
      return recheckOverride;
    }
    List<AXF_OBJ_FinancialSchedule__c> rows = [
      SELECT
        Id,
        AXF_FSC_NUM_ProjectionRevision__c,
        AXF_FSC_NUM_FinancialVersion__c,
        AXF_FSC_DAT_TerminationDate__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :scheduleId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static Long revisionOf(AXF_OBJ_FinancialSchedule__c row) {
    if (row == null || row.AXF_FSC_NUM_ProjectionRevision__c == null) {
      return 0;
    }
    return row.AXF_FSC_NUM_ProjectionRevision__c.longValue();
  }

  private static Long financialVersionOf(AXF_OBJ_FinancialSchedule__c row) {
    if (row == null || row.AXF_FSC_NUM_FinancialVersion__c == null) {
      return 0;
    }
    return row.AXF_FSC_NUM_FinancialVersion__c.longValue();
  }

  /**
   * Fronteira de encerramento lida: participa da rechecagem de versão junto de
   * ProjectionRevision e FinancialVersion. Se o predicado de encerramento mudar entre a leitura
   * capturada e a rechecagem, o total não volta rotulado completo.
   */
  private static Date terminationOf(AXF_OBJ_FinancialSchedule__c row) {
    return (row == null) ? null : row.AXF_FSC_DAT_TerminationDate__c;
  }

  private static Long revisionValue(Decimal value) {
    return (value == null) ? 0 : value.longValue();
  }

  /**
   * @description Encerra a leitura sem resultado utilizável. Nenhum desfecho que não seja OK
   * devolve total: um parcial nunca é apresentado como completo.
   */
  private static ProjectionResult fail(
    ProjectionResult result,
    String outcome,
    String message
  ) {
    result.outcome = outcome;
    result.message = message;
    result.lines = new List<OccurrenceLine>();
    result.evaluatedCount = 0;
    result.persistedCount = 0;
    result.virtualCount = 0;
    result.overdueCount = 0;
    result.futureCount = 0;
    result.unconfirmedCount = 0;
    result.overdueTotal = null;
    result.futureTotal = null;
    result.totalRemaining = null;
    result.horizonTotal = null;
    result.estimatedTotal = null;
    result.confirmedTotal = null;
    result.horizonCount = 0;
    result.fullyEstimated = false;
    result.complete = false;
    result.coverageComplete = false;
    return result;
  }
}
