/**
 * AXF-103 — porta única de escrita e de leitura autorizada do cronograma financeiro.
 *
 * Comando de criação atômico: raiz, definição imutável (e referência, no método estimado),
 * recibo de operação e a janela inicial delimitada são persistidos na mesma transação.
 * Nunca as 360 parcelas: a leitura projeta o restante pelo motor único.
 *
 * Invariantes aplicadas aqui:
 *  - Serialização holder-first: `Account FOR UPDATE` antes de qualquer lock descendente.
 *  - Uma schedule por transação; comando multi-titular é rejeitado antes de qualquer escrita.
 *  - Identidades determinísticas: chave do cronograma, chave de ocorrência e chave da
 *    operação (hash do payload canônico versionado, ordenação estável, nulo explícito).
 *  - Replay equivalente devolve o ResultJson original autorizado; payload alterado na mesma
 *    identidade é CONFLICT. Uma colisão de chave única nunca vira sucesso arbitrário.
 *  - Nada abaixo de TrackingStartSequence é gerado nem somado.
 *  - Estouro de valor é rejeitado antes da escrita, sem alargar metadado existente: o limite
 *    efetivo de magnitude continua sendo o Number(16,2) já em uso.
 *
 * Acesso: a autorização é a autoridade do titular (AXF-3), conferida antes de ler ou
 * escrever; as operações internas usam access mode explícito.
 */
public with sharing class ALT_CLS_FinancialScheduleService {
  public static final String OUTCOME_CREATED = 'CREATED';
  public static final String OUTCOME_REPLAY = 'REPLAY';
  public static final String OUTCOME_CONFLICT = 'CONFLICT';
  public static final String OUTCOME_INVALID = 'INVALID';
  public static final String OUTCOME_FORBIDDEN = 'FORBIDDEN';
  public static final String OUTCOME_UNAVAILABLE = 'UNAVAILABLE';
  public static final String OUTCOME_TOO_LARGE = 'TOO_LARGE';
  public static final String OUTCOME_MULTI_HOLDER = 'MULTI_HOLDER';

  public static final String SCHEDULE_TAG = 'axf103-sch-v1';
  public static final String DEFINITION_TAG = 'axf103-sdf-v1';
  public static final String REFERENCE_TAG = 'axf103-srf-v1';
  public static final String PAYLOAD_TAG = 'axf103-payload-v1';
  public static final String OPERATION_TAG = 'axf103-op-v1';

  public static final String METHOD_ESTIMATED = 'ESTIMATED';
  public static final String STATE_ACTIVE = 'ACTIVE';
  public static final String STATE_DRAFT = 'DRAFT';
  public static final String OPEN_STATE = 'OPEN';
  public static final String SCOPE_FROM_SEQUENCE = 'FROM_SEQUENCE';
  public static final String OPERATION_CREATE = 'CREATE';

  /** Limite de engenharia para a janela inicial gravada numa transação. */
  public static final Integer MAX_INITIAL_WINDOW = 50;
  /**
   * Periodicidade máxima aceita, em meses. Mantém o deslocamento de sequências dentro do limite
   * de sanidade do calendário puro, em vez de confiar em estouro aritmético.
   */
  public static final Integer MAX_PERIOD_MONTHS = 120;
  /** Meses da janela rolante: mês corrente mais onze. */
  public static final Integer DEFAULT_HORIZON_MONTHS = 12;
  /**
   * Teto do horizonte. Materializar além do mês corrente mais onze exige aprovação humana,
   * então o comando aceita o parâmetro mas nunca o deixa passar deste valor.
   */
  public static final Integer MAX_HORIZON_MONTHS = 12;
  /** Limite efetivo de magnitude já em uso (Number(16,2)); não alarga metadado existente. */
  public static final Decimal MAX_AMOUNT = ALT_CLS_ScheduleProjection.MAX_EFFECTIVE_AMOUNT;
  public static final Integer MONEY_SCALE = 2;
  public static final Integer RATE_SCALE = 10;
  /** Limite dos campos de texto longo desta fatia. */
  public static final Integer MAX_TAL_LENGTH = 32768;
  /** Revisão de projeção produzida pelo recibo de CREATE. */
  public static final Long CREATE_REVISION = 1;

  private static final Set<String> DIRECTIONS = new Set<String>{
    'CREDIT',
    'DEBIT'
  };
  private static final Set<String> METHODS = new Set<String>{
    'RECURRING',
    'INSTALLMENT',
    'PRICE',
    'SAC',
    'ESTIMATED'
  };

  public class ServiceException extends Exception {
  }

  public class CreateInput {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public String method;
    /** Total de parcelas do cronograma; nulo apenas em recorrência indefinida. */
    @AuraEnabled
    public Integer totalInstallments;
    /** Sequência absoluta de FirstDueDate. */
    @AuraEnabled
    public Integer firstSequence;
    @AuraEnabled
    public Date firstDueDate;
    /** Parcela corrente informada no cadastro e o seu vencimento. */
    @AuraEnabled
    public Integer trackingStartSequence;
    @AuraEnabled
    public Date trackingDueDate;
    @AuraEnabled
    public Integer anchorDay;
    @AuraEnabled
    public Integer periodMonths;
    /**
     * Horizonte materializado em meses de calendário (mês corrente mais N-1). Padrão 12 e
     * nunca acima de 12: materializar além do mês corrente mais onze exige aprovação humana.
     */
    @AuraEnabled
    public Integer horizonMonths;
    @AuraEnabled
    public Decimal principal;
    @AuraEnabled
    public Decimal periodRate;
    @AuraEnabled
    public Decimal fixedValue;
    @AuraEnabled
    public Decimal recurringFee;
    @AuraEnabled
    public Decimal upfrontFee;
    @AuraEnabled
    public Decimal referenceAmount;
    @AuraEnabled
    public String timeZone;
    @AuraEnabled
    public String reason;
    /** Chave de agrupamento legada de AXF-20, preservada na adoção. */
    @AuraEnabled
    public String legacyGroupKey;
  }

  public class CreateResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public String scheduleKey;
    @AuraEnabled
    public Id definitionId;
    @AuraEnabled
    public Id referenceId;
    @AuraEnabled
    public Id changeId;
    @AuraEnabled
    public String changeKey;
    @AuraEnabled
    public Integer occurrenceCount = 0;
    @AuraEnabled
    public Integer firstMaterializedSequence;
    @AuraEnabled
    public Integer lastMaterializedSequence;
    @AuraEnabled
    public Integer trackingStartSequence;
    @AuraEnabled
    public Long projectionRevision;
    @AuraEnabled
    public Long financialVersion;
    @AuraEnabled
    public Boolean replay = false;
  }

  @TestVisible
  private static Set<Id> authorizedOverride;
  @TestVisible
  private static Integer windowLimitOverride;

  /** Observa se o lock do titular já foi adquirido; usado para provar a ordem do comando. */
  @TestVisible
  private static Boolean lastRunLockedHolder = false;

  /** Força a identidade de ocorrência gravada, para exercitar o caminho de falha de DML. */
  @TestVisible
  private static String forcedOccurrenceKey;

  private static final String WINDOW_LIMIT_PREFIX = 'A janela inicial exigiria ';

  /**
   * Capacidade de escrita liberada apenas durante o comando autorizado deste serviço. Visível ao
   * teste apenas para permitir montar evidência já confirmada (recibo/definição existentes) e
   * exercitar o replay e a rechecagem pós-lock; nenhum consumidor a habilita em runtime.
   */
  @TestVisible
  private static Boolean writing = false;

  /**
   * @description Capacidade somente-leitura para os handlers de trigger: campos derivados,
   * contadores e ponteiros do cronograma não são editáveis por comando direto. O chamador não
   * consegue habilitar a escrita.
   */
  public static Boolean isWriting() {
    return writing;
  }

  /**
   * @description Identidade determinística do cronograma para um comando, sem executá-lo.
   * Permite a um consumidor autorizado calcular as identidades de ocorrência que o comando
   * vai usar (inclusive para detectar colisões de identidade truncada).
   */
  public static String previewScheduleKey(CreateInput input) {
    return normalize(input).scheduleKey;
  }

  /**
   * @description Hash do payload canônico que o comando vai usar, sem executá-lo. Permite a um
   * chamador autorizado (e aos testes) reconstruir a identidade de operação enquadrada.
   */
  public static String previewPayloadHash(CreateInput input) {
    return normalize(input).payloadHash;
  }

  /**
   * @description Identidade de operação enquadrada (hash do payload canônico versionado) que o
   * comando vai usar, sem executá-lo. É por ela que o replay é resolvido primeiro.
   */
  public static String previewOperationKey(CreateInput input) {
    return normalize(input).operationKey;
  }

  /**
   * @description Guarda de tamanho da janela inicial. Separada do comando para ser exercitada
   * contra o valor REAL de MAX_INITIAL_WINDOW, e não apenas contra uma sobreposição menor.
   */
  @TestVisible
  private static void enforceWindowLimit(Integer count) {
    Integer cap = (windowLimitOverride == null)
      ? MAX_INITIAL_WINDOW
      : Math.min(MAX_INITIAL_WINDOW, windowLimitOverride);
    if (count == null || count <= cap) {
      return;
    }
    throw new ServiceException(
      WINDOW_LIMIT_PREFIX +
        count +
        ' ocorrências; o limite por transação é ' +
        cap +
        '. Reduza `horizonMonths` (aceito entre 1 e ' +
        MAX_HORIZON_MONTHS +
        ') ou aumente `periodMonths` para caber menos ocorrências na janela.'
    );
  }

  /**
   * @description Comando de criação atômico. Uma schedule por transação.
   */
  public static CreateResult createSchedule(CreateInput input) {
    CreateResult result = new CreateResult();
    lastRunLockedHolder = false;
    if (input == null || input.accountId == null) {
      return fail(
        result,
        OUTCOME_INVALID,
        'Titular é obrigatório para criar um cronograma.'
      );
    }
    if (!isAuthorized(input.accountId)) {
      return fail(
        result,
        OUTCOME_FORBIDDEN,
        'Você não tem acesso a esta entidade titular.'
      );
    }
    // Autoridade de escrita do próprio usuário, não apenas do titular: o acesso de classe não
    // é granular por método, então o comando confere o CRUD de criação do objeto raiz. Um
    // perfil somente-leitura (Participante) é recusado aqui.
    if (
      !AXF_OBJ_FinancialSchedule__c.SObjectType.getDescribe().isCreateable()
    ) {
      return fail(
        result,
        OUTCOME_FORBIDDEN,
        'Você não tem permissão para criar cronogramas financeiros.'
      );
    }

    Normalized normalized;
    try {
      normalized = normalize(input);
    } catch (ServiceException invalid) {
      return fail(result, OUTCOME_INVALID, invalid.getMessage());
    } catch (ALT_CLS_ScheduleCalendar.CalendarException invalidCalendar) {
      return fail(result, OUTCOME_INVALID, invalidCalendar.getMessage());
    }
    result.scheduleKey = normalized.scheduleKey;
    result.changeKey = normalized.operationKey;
    result.trackingStartSequence = normalized.trackingStartSequence;

    // Replay autorizado: identidade de operação antes de qualquer verificação de versão.
    CreateResult replay = replayOrConflict(
      normalized.scheduleKey,
      normalized.operationKey,
      normalized.payloadHash
    );
    if (replay != null) {
      return replay;
    }

    // A janela e os valores da fórmula são calculados ANTES de qualquer lock: trabalho de CPU
    // não pode acontecer com a linha do titular travada.
    List<MaterializedOccurrence> window;
    try {
      window = buildWindow(normalized);
      enforceWindowLimit(window.size());
      if (window.isEmpty()) {
        // Criar sem nenhuma ocorrência e sem `ThroughSequence` devolveria CREATED com um
        // cronograma vazio, sem sinalização alguma.
        throw new ServiceException(
          'A primeira sequência rastreada vence depois do fim do mês corrente mais onze: nenhuma ocorrência seria materializada. Informe um vencimento dentro da janela ou aumente `periodMonths`.'
        );
      }
    } catch (ServiceException rejected) {
      return fail(
        result,
        rejected.getMessage().startsWith(WINDOW_LIMIT_PREFIX)
          ? OUTCOME_TOO_LARGE
          : OUTCOME_INVALID,
        rejected.getMessage()
      );
    } catch (ALT_CLS_ScheduleCalendar.CalendarException invalidCalendar) {
      return fail(result, OUTCOME_INVALID, invalidCalendar.getMessage());
    } catch (System.MathException invalidFormula) {
      return fail(
        result,
        OUTCOME_INVALID,
        'A fórmula aprovada estourou a precisão numérica para estes insumos: ' +
        invalidFormula.getMessage()
      );
    }

    // Serialização holder-first: o titular é o primeiro lock, antes de qualquer descendente.
    lastRunLockedHolder = true;
    List<SObject> holders = Database.queryWithBinds(
      'SELECT Id FROM Account WHERE Id = :holderId FOR UPDATE',
      new Map<String, Object>{ 'holderId' => input.accountId },
      AccessLevel.USER_MODE
    );
    if (holders.size() != 1) {
      return fail(
        result,
        OUTCOME_UNAVAILABLE,
        'O titular não está disponível para escrita neste momento.'
      );
    }
    // A releitura do recibo após o lock evita gravar sobre uma operação já confirmada.
    CreateResult afterLock = replayOrConflict(
      normalized.scheduleKey,
      normalized.operationKey,
      normalized.payloadHash
    );
    if (afterLock != null) {
      return afterLock;
    }

    // Integridade e autoridade do contrato informado, sob o lock do titular já adquirido: o
    // contrato é o lock descendente seguinte, na mesma ordem usada pelos escritores financeiros
    // existentes. Um cronograma nunca aponta o contrato de outro titular, de outra moeda, nem um
    // contrato inexistente — e a validação acontece antes de qualquer escrita.
    if (input.contractId != null) {
      CreateResult contractFailure = lockAndValidateContract(
        input.contractId,
        input.accountId,
        normalized.currencyIsoCode
      );
      if (contractFailure != null) {
        return contractFailure;
      }
    }

    Savepoint checkpoint = Database.setSavepoint();
    try {
      writing = true;
      AXF_OBJ_FinancialSchedule__c root = new AXF_OBJ_FinancialSchedule__c(
        AXF_FSC_EXI_ScheduleKey__c = normalized.scheduleKey,
        AXF_FSC_LKP_Account__c = input.accountId,
        AXF_FSC_LKP_Contract__c = input.contractId,
        AXF_FSC_TXT_CurrencyIsoCode__c = normalized.currencyIsoCode,
        AXF_FSC_PKL_Direction__c = normalized.direction,
        AXF_FSC_PKL_State__c = STATE_DRAFT,
        AXF_FSC_NUM_Version__c = 0,
        AXF_FSC_NUM_TrackingStartSequence__c = normalized.trackingStartSequence,
        AXF_FSC_NUM_ProjectionRevision__c = 0,
        AXF_FSC_NUM_AppliedRevision__c = 0,
        AXF_FSC_NUM_FinancialVersion__c = 0,
        AXF_FSC_NUM_HorizonMonths__c = normalized.horizonMonths,
        AXF_FSC_TXT_LegacyGroupKey__c = normalized.legacyGroupKey
      );
      Database.insert(
        new List<AXF_OBJ_FinancialSchedule__c>{ root },
        AccessLevel.SYSTEM_MODE
      );

      AXF_OBJ_ScheduleDefinition__c definition = new AXF_OBJ_ScheduleDefinition__c(
        AXF_SDF_EXI_DefinitionKey__c = normalized.definitionKey,
        AXF_SDF_LKP_Schedule__c = root.Id,
        AXF_SDF_NUM_Revision__c = 1,
        AXF_SDF_NUM_EffectiveSequence__c = normalized.firstSequence,
        AXF_SDF_PKL_Method__c = normalized.method,
        AXF_SDF_NUM_TotalInstallments__c = normalized.totalInstallments,
        AXF_SDF_NUM_FirstSequence__c = normalized.firstSequence,
        AXF_SDF_DAT_FirstDueDate__c = normalized.firstDueDate,
        AXF_SDF_NUM_AnchorDay__c = normalized.anchorDay,
        AXF_SDF_NUM_PeriodMonths__c = normalized.periodMonths,
        AXF_SDF_TXT_TimeZone__c = normalized.timeZone,
        AXF_SDF_NUM_Principal__c = normalized.principal,
        AXF_SDF_NUM_PeriodRate__c = normalized.periodRate,
        AXF_SDF_NUM_FixedValue__c = normalized.fixedValue,
        AXF_SDF_NUM_RecurringFee__c = normalized.recurringFee,
        AXF_SDF_NUM_UpfrontFee__c = normalized.upfrontFee,
        AXF_SDF_TXT_FormulaVersion__c = ALT_CLS_AmortizationSchedule.POLICY_VERSION,
        AXF_SDF_TAL_InputCanonicalJson__c = normalized.canonicalJson,
        AXF_SDF_NUM_InitialReferenceAmount__c = normalized.referenceAmount
      );
      Database.insert(
        new List<AXF_OBJ_ScheduleDefinition__c>{ definition },
        AccessLevel.SYSTEM_MODE
      );

      AXF_OBJ_ScheduleReference__c reference;
      if (normalized.method == METHOD_ESTIMATED) {
        reference = new AXF_OBJ_ScheduleReference__c(
          AXF_SRF_EXI_ReferenceKey__c = normalized.referenceKey,
          AXF_SRF_LKP_Schedule__c = root.Id,
          AXF_SRF_NUM_EconomicSequence__c = 1,
          AXF_SRF_NUM_EffectiveSequence__c = normalized.firstSequence,
          AXF_SRF_NUM_RecurringAmount__c = normalized.referenceAmount,
          AXF_SRF_PKL_Kind__c = 'INITIAL',
          // A referência inicial nasce confirmada pelo próprio comando autorizado: as colunas de
          // confirmação de um objeto de evidência imutável não podem ficar permanentemente nulas.
          AXF_SRF_DT_ConfirmedAt__c = System.now(),
          AXF_SRF_LKP_ConfirmedBy__c = UserInfo.getUserId()
        );
        Database.insert(
          new List<AXF_OBJ_ScheduleReference__c>{ reference },
          AccessLevel.SYSTEM_MODE
        );
      }

      List<AXF_OBJ_FinancialTransaction__c> occurrences = new List<AXF_OBJ_FinancialTransaction__c>();
      for (MaterializedOccurrence occurrence : window) {
        occurrences.add(
          toFinancialTransaction(
            occurrence,
            root.Id,
            definition.Id,
            reference == null ? null : reference.Id,
            normalized,
            input
          )
        );
      }
      if (!occurrences.isEmpty()) {
        Database.insert(occurrences, AccessLevel.SYSTEM_MODE);
      }

      root.AXF_FSC_LKP_ActiveDefinition__c = definition.Id;
      root.AXF_FSC_LKP_ActiveReference__c = (reference == null)
        ? null
        : reference.Id;
      root.AXF_FSC_PKL_State__c = STATE_ACTIVE;
      root.AXF_FSC_NUM_ProjectionRevision__c = CREATE_REVISION;
      root.AXF_FSC_NUM_AppliedRevision__c = CREATE_REVISION;
      root.AXF_FSC_NUM_FinancialVersion__c = 1;
      Database.update(
        new List<AXF_OBJ_FinancialSchedule__c>{ root },
        AccessLevel.SYSTEM_MODE
      );

      result.scheduleId = root.Id;
      result.definitionId = definition.Id;
      result.referenceId = (reference == null) ? null : reference.Id;
      result.occurrenceCount = occurrences.size();
      result.firstMaterializedSequence = window.isEmpty()
        ? null
        : window[0].sequence;
      result.lastMaterializedSequence = window.isEmpty()
        ? null
        : window[window.size() - 1].sequence;
      result.projectionRevision = CREATE_REVISION;
      result.financialVersion = 1;
      result.outcome = OUTCOME_CREATED;

      // ResultJson é o resultado autorizado devolvido no replay. O Id do próprio recibo não
      // participa: um recibo é imutável e não pode ser atualizado depois de inserido.
      AXF_OBJ_ScheduleChange__c receipt = new AXF_OBJ_ScheduleChange__c(
        AXF_SCH_EXI_OperationKey__c = normalized.operationKey,
        AXF_SCH_TXT_PayloadHash__c = normalized.payloadHash,
        AXF_SCH_LKP_Schedule__c = root.Id,
        AXF_SCH_PKL_Operation__c = OPERATION_CREATE,
        AXF_SCH_NUM_Revision__c = CREATE_REVISION,
        AXF_SCH_PKL_Scope__c = SCOPE_FROM_SEQUENCE,
        AXF_SCH_NUM_FromSequence__c = normalized.trackingStartSequence,
        AXF_SCH_NUM_ThroughSequence__c = result.lastMaterializedSequence,
        AXF_SCH_BOL_IncludeManualOverrides__c = false,
        AXF_SCH_TAL_ResultJson__c = JSON.serialize(result),
        AXF_SCH_LKP_Actor__c = UserInfo.getUserId(),
        AXF_SCH_DT_CommittedAt__c = System.now(),
        AXF_SCH_TAL_Reason__c = input.reason
      );
      Database.insert(
        new List<AXF_OBJ_ScheduleChange__c>{ receipt },
        AccessLevel.SYSTEM_MODE
      );
      result.changeId = receipt.Id;
    } catch (DmlException failure) {
      Database.rollback(checkpoint);
      // Colisão de chave única: rollback e releitura autorizada, nunca sucesso arbitrário.
      CreateResult recovered = replayOrConflict(
        normalized.scheduleKey,
        normalized.operationKey,
        normalized.payloadHash
      );
      if (recovered != null) {
        return recovered;
      }
      // Colisão de identidade TRUNCADA (token de 36 caracteres) com identidade completa
      // diferente é CONFLICT: nunca sucesso, e não é uma indisponibilidade genérica.
      if (hasTruncatedIdentityCollision(window, normalized.scheduleKey)) {
        return fail(
          result,
          OUTCOME_CONFLICT,
          'A identidade truncada de idempotência já pertence a uma ocorrência de identidade completa diferente. Nada foi gravado.'
        );
      }
      return fail(
        result,
        OUTCOME_UNAVAILABLE,
        'Não foi possível gravar o cronograma: ' +
        sanitize(failure.getDmlType(0))
      );
    } catch (System.MathException failure) {
      Database.rollback(checkpoint);
      return fail(
        result,
        OUTCOME_INVALID,
        'A fórmula aprovada estourou a precisão numérica para estes insumos.'
      );
    } catch (ALT_CLS_ScheduleCalendar.CalendarException failure) {
      Database.rollback(checkpoint);
      return fail(result, OUTCOME_INVALID, failure.getMessage());
    } catch (ALT_CLS_ScheduleProjection.ProjectionException failure) {
      Database.rollback(checkpoint);
      return fail(result, OUTCOME_INVALID, failure.getMessage());
    } catch (ServiceException failure) {
      Database.rollback(checkpoint);
      return fail(result, OUTCOME_INVALID, failure.getMessage());
    } finally {
      writing = false;
    }

    result.message =
      'Cronograma criado com ' +
      result.occurrenceCount +
      ' ocorrência(s) na janela inicial.';
    return result;
  }

  /**
   * @description Comando em lote. Devolve UM resultado por entrada, alinhado por índice com a
   * entrada correspondente e carregando a identidade do próprio cronograma: um único resultado
   * para N entradas faz um chamador que associa por índice ler o desfecho errado. Rejeita
   * multi-titular e mais de uma schedule por transação antes de qualquer escrita — a
   * serialização é por titular, não um all-or-nothing global.
   */
  public static List<CreateResult> createSchedules(List<CreateInput> inputs) {
    if (inputs == null || inputs.isEmpty()) {
      return new List<CreateResult>{
        fail(
          new CreateResult(),
          OUTCOME_INVALID,
          'Nenhum cronograma informado.'
        )
      };
    }
    Set<Id> holders = new Set<Id>();
    for (CreateInput input : inputs) {
      if (input != null && input.accountId != null) {
        holders.add(input.accountId);
      }
    }
    if (holders.size() > 1) {
      return rejectPerInput(
        inputs,
        OUTCOME_MULTI_HOLDER,
        'Um comando por transação opera um único titular. Particione por titular e relate a conclusão por titular.'
      );
    }
    if (inputs.size() > 1) {
      return rejectPerInput(
        inputs,
        OUTCOME_INVALID,
        'Uma schedule por transação de geração.'
      );
    }
    return new List<CreateResult>{ createSchedule(inputs[0]) };
  }

  /**
   * @description Um desfecho por entrada, cada um com a identidade do cronograma que aquela
   * entrada descreve. Nenhuma escrita acontece: a recusa é da transação inteira, mas o relato é
   * por entrada.
   */
  private static List<CreateResult> rejectPerInput(
    List<CreateInput> inputs,
    String outcome,
    String message
  ) {
    List<CreateResult> results = new List<CreateResult>();
    for (CreateInput input : inputs) {
      CreateResult result = new CreateResult();
      if (input != null && input.accountId != null) {
        result.trackingStartSequence = input.trackingStartSequence;
        try {
          Normalized normalized = normalize(input);
          result.scheduleKey = normalized.scheduleKey;
          result.changeKey = normalized.operationKey;
        } catch (Exception rejectedInput) {
          // Uma entrada inválida por si só continua sendo relatada por entrada, sem identidade
          // inventada: o desfecho da transação é o mesmo e nada foi escrito.
          result.scheduleKey = null;
          result.changeKey = null;
        }
      }
      results.add(fail(result, outcome, message));
    }
    return results;
  }

  /**
   * @description Leitura autorizada do compromisso restante pelo motor único de projeção.
   */
  public static ALT_CLS_ScheduleProjection.ProjectionResult readProjection(
    ALT_CLS_ScheduleProjection.ProjectionInput input
  ) {
    ALT_CLS_ScheduleProjection.ProjectionResult denied = new ALT_CLS_ScheduleProjection.ProjectionResult();
    denied.overdueTotal = null;
    denied.futureTotal = null;
    denied.totalRemaining = null;
    if (input == null || input.scheduleId == null) {
      denied.outcome = ALT_CLS_ScheduleProjection.OUTCOME_INVALID;
      denied.message = 'Cronograma é obrigatório.';
      return denied;
    }
    Id holderId = holderOf(input.scheduleId);
    if (holderId == null) {
      denied.scheduleId = input.scheduleId;
      denied.outcome = ALT_CLS_ScheduleProjection.OUTCOME_NOT_FOUND;
      denied.message = 'Cronograma não encontrado neste escopo.';
      return denied;
    }
    if (!isAuthorized(holderId)) {
      denied.scheduleId = input.scheduleId;
      denied.outcome = ALT_CLS_ScheduleProjection.OUTCOME_FORBIDDEN;
      denied.message = 'Você não tem acesso a esta entidade titular.';
      return denied;
    }
    return ALT_CLS_ScheduleProjection.project(input);
  }

  /** @description Titular do cronograma, ou nulo quando não visível neste escopo. */
  public static Id holderOf(Id scheduleId) {
    List<AXF_OBJ_FinancialSchedule__c> rows = [
      SELECT Id, AXF_FSC_LKP_Account__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :scheduleId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].AXF_FSC_LKP_Account__c;
  }

  // --- normalização e validação -------------------------------------------

  private class Normalized {
    String direction;
    String currencyIsoCode;
    String method;
    Integer totalInstallments;
    Integer firstSequence;
    Date firstDueDate;
    Integer trackingStartSequence;
    Integer anchorDay;
    Integer periodMonths;
    Integer horizonMonths;
    String timeZone;
    String legacyGroupKey;
    Id contractId;
    Decimal principal;
    Decimal periodRate;
    Decimal fixedValue;
    Decimal recurringFee;
    Decimal upfrontFee;
    Decimal referenceAmount;
    String scheduleKey;
    String definitionKey;
    String referenceKey;
    String payloadHash;
    String operationKey;
    String canonicalJson;
  }

  private class MaterializedOccurrence {
    Integer sequence;
    Date nominalDueDate;
    Decimal amount;
    /** Decomposição devolvida pela fórmula aprovada; nula em ESTIMATED, que não tem fórmula. */
    Decimal principalPortion;
    Decimal interestPortion;
    Decimal feePortion;
    Decimal closingBalance;
    Boolean roundingResidual = false;
  }

  private static Normalized normalize(CreateInput input) {
    Normalized value = new Normalized();

    value.direction = String.isBlank(input.direction)
      ? null
      : input.direction.trim().toUpperCase();
    if (value.direction == null || !DIRECTIONS.contains(value.direction)) {
      throw new ServiceException('Natureza (CREDIT/DEBIT) inválida.');
    }
    value.currencyIsoCode = String.isBlank(input.currencyIsoCode)
      ? null
      : input.currencyIsoCode.trim().toUpperCase();
    if (
      value.currencyIsoCode == null ||
      !Pattern.matches('[A-Z]{3}', value.currencyIsoCode)
    ) {
      throw new ServiceException('Moeda ISO de 3 letras é obrigatória.');
    }
    value.method = String.isBlank(input.method)
      ? null
      : input.method.trim().toUpperCase();
    if (value.method == null || !METHODS.contains(value.method)) {
      throw new ServiceException(
        'Método deve ser RECURRING, INSTALLMENT, PRICE, SAC ou ESTIMATED.'
      );
    }

    value.firstSequence = (input.firstSequence == null)
      ? 1
      : input.firstSequence;
    if (value.firstSequence < 1) {
      throw new ServiceException(
        'Sequência inicial deve ser maior ou igual a 1.'
      );
    }
    value.trackingStartSequence = (input.trackingStartSequence == null)
      ? value.firstSequence
      : input.trackingStartSequence;
    if (value.trackingStartSequence < value.firstSequence) {
      throw new ServiceException(
        'A sequência inicial de rastreamento não pode ser anterior à sequência inicial da definição.'
      );
    }
    value.periodMonths = (input.periodMonths == null) ? 1 : input.periodMonths;
    if (value.periodMonths < 1) {
      throw new ServiceException('Periodicidade deve ser de pelo menos 1 mês.');
    }
    if (value.periodMonths > MAX_PERIOD_MONTHS) {
      throw new ServiceException(
        'Periodicidade deve estar entre 1 e ' + MAX_PERIOD_MONTHS + ' meses.'
      );
    }
    value.horizonMonths = (input.horizonMonths == null)
      ? DEFAULT_HORIZON_MONTHS
      : input.horizonMonths;
    if (value.horizonMonths < 1 || value.horizonMonths > MAX_HORIZON_MONTHS) {
      throw new ServiceException(
        'O horizonte deve estar entre 1 e ' +
          MAX_HORIZON_MONTHS +
          ' meses: materializar além do mês corrente mais onze exige aprovação humana.'
      );
    }
    // Texto que participa da identidade do cronograma e do hash do payload é normalizado:
    // espaços em volta e cadeia vazia não podem criar uma identidade diferente.
    value.timeZone = blankToNull(input.timeZone);
    value.legacyGroupKey = blankToNull(input.legacyGroupKey);
    value.contractId = input.contractId;
    if (value.legacyGroupKey != null && value.legacyGroupKey.length() > 24) {
      throw new ServiceException(
        'Chave legada do cronograma excede 24 caracteres.'
      );
    }
    if (value.timeZone != null && value.timeZone.length() > 80) {
      throw new ServiceException('Fuso horário excede 80 caracteres.');
    }

    value.anchorDay = input.anchorDay;
    if (value.anchorDay == null) {
      // A âncora é a autoridade de calendário da DEFINIÇÃO e a definição nasce no primeiro
      // vencimento: derivá-la da parcela corrente usaria um dia já recortado pelo mês curto e
      // recusaria pares coerentes com âncora 29/30/31 cuja parcela corrente cai em fevereiro.
      Date anchorSource = (input.firstDueDate != null)
        ? input.firstDueDate
        : input.trackingDueDate;
      if (anchorSource == null) {
        throw new ServiceException(
          'Informe o vencimento da parcela corrente ou o primeiro vencimento.'
        );
      }
      value.anchorDay = anchorSource.day();
    }
    if (
      value.anchorDay < ALT_CLS_ScheduleCalendar.MIN_ANCHOR_DAY ||
      value.anchorDay > ALT_CLS_ScheduleCalendar.MAX_ANCHOR_DAY
    ) {
      throw new ServiceException('Dia âncora deve estar entre 1 e 31.');
    }

    if (input.firstDueDate != null) {
      if (input.trackingDueDate != null) {
        // A coerência é comparada PARA A FRENTE, derivando pela mesma função que materializa a
        // ocorrência — e não pelo calendário já recortado da parcela corrente. O par só é
        // recusado quando o calendário aprovado realmente não o produz.
        Date projected = ALT_CLS_ScheduleCalendar.nominalDueDate(
          input.firstDueDate,
          value.firstSequence,
          value.periodMonths,
          value.anchorDay,
          value.trackingStartSequence
        );
        if (projected != input.trackingDueDate) {
          throw new ServiceException(
            'O vencimento da parcela corrente informado não é coerente com o primeiro vencimento, a periodicidade e a âncora.'
          );
        }
      }
      value.firstDueDate = input.firstDueDate;
    } else if (input.trackingDueDate != null) {
      value.firstDueDate = ALT_CLS_ScheduleCalendar.shift(
        input.trackingDueDate,
        -(value.trackingStartSequence - value.firstSequence) *
        value.periodMonths,
        value.anchorDay
      );
    }
    if (value.firstDueDate == null) {
      throw new ServiceException(
        'Informe o primeiro vencimento ou o vencimento da parcela corrente.'
      );
    }

    value.totalInstallments = input.totalInstallments;
    if (value.method == METHOD_ESTIMATED) {
      if (value.totalInstallments != null && value.totalInstallments < 1) {
        throw new ServiceException(
          'Total de parcelas deve ser maior ou igual a 1.'
        );
      }
    } else {
      if (value.totalInstallments == null || value.totalInstallments < 1) {
        throw new ServiceException(
          'Total de parcelas é obrigatório para métodos calculados.'
        );
      }
    }
    if (
      value.totalInstallments != null &&
      value.firstSequence + value.totalInstallments - 1 <
      value.trackingStartSequence
    ) {
      throw new ServiceException(
        'A faixa da definição termina antes da parcela corrente informada.'
      );
    }

    value.principal = normalizeMoney(input.principal, 'Principal');
    value.fixedValue = normalizeMoney(input.fixedValue, 'Valor fixo');
    value.recurringFee = normalizeMoney(
      input.recurringFee,
      'Tarifa recorrente'
    );
    value.upfrontFee = normalizeMoney(input.upfrontFee, 'Tarifa de abertura');
    value.referenceAmount = normalizeMoney(
      input.referenceAmount,
      'Valor de referência'
    );
    value.periodRate = normalizeRate(input.periodRate);

    if (value.method == 'RECURRING') {
      if (value.fixedValue == null || value.fixedValue <= 0) {
        throw new ServiceException(
          'Valor fixo da recorrência é obrigatório e positivo.'
        );
      }
    } else if (value.method == 'INSTALLMENT') {
      if (value.principal == null || value.principal <= 0) {
        throw new ServiceException(
          'Total a parcelar é obrigatório e positivo.'
        );
      }
    } else if (value.method == 'PRICE' || value.method == 'SAC') {
      if (value.principal == null || value.principal <= 0) {
        throw new ServiceException(
          'Principal financiado é obrigatório e positivo.'
        );
      }
      if (value.periodRate == null || value.periodRate < 0) {
        throw new ServiceException(
          'Taxa do período é obrigatória e não negativa.'
        );
      }
    } else if (value.referenceAmount == null || value.referenceAmount <= 0) {
      throw new ServiceException(
        'Cronograma estimado exige um valor de referência positivo.'
      );
    }

    // Insumos que o método não usa são zerados para nulo. Um reenvio semanticamente idêntico
    // (campo omitido contra campo enviado como zero/vazio) precisa produzir o MESMO hash de
    // payload, senão um retry legítimo viraria CONFLICT em vez de REPLAY.
    Boolean estimated = value.method == METHOD_ESTIMATED;
    if (estimated) {
      value.principal = null;
      value.periodRate = null;
      value.fixedValue = null;
      value.recurringFee = null;
      value.upfrontFee = null;
    } else {
      value.referenceAmount = null;
      value.recurringFee = (value.recurringFee == null)
        ? 0.00
        : value.recurringFee;
      value.upfrontFee = (value.upfrontFee == null) ? 0.00 : value.upfrontFee;
      if (value.method != 'RECURRING') {
        value.fixedValue = null;
      }
      if (value.method == 'RECURRING' || value.method == 'INSTALLMENT') {
        value.periodRate = null;
      }
      if (value.method == 'RECURRING') {
        value.principal = null;
      }
    }

    // Pré-checagem explícita de texto longo: payload acima do limite é rejeitado, não truncado.
    if (input.reason != null && input.reason.length() > MAX_TAL_LENGTH) {
      throw new ServiceException(
        'Justificativa excede o limite de ' +
          MAX_TAL_LENGTH +
          ' caracteres do campo de texto longo.'
      );
    }

    // Identidade do cronograma: estável sob emenda de fórmula (principal, taxa e tarifas não
    // participam) e distinta por contrato, titular, direção, moeda, método, calendário e pelo
    // discriminador do fluxo. Um contrato admite vários cronogramas; dois contratos do mesmo
    // titular com o mesmo calendário não podem colidir.
    value.scheduleKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        SCHEDULE_TAG,
        input.accountId,
        value.contractId,
        value.direction,
        value.currencyIsoCode,
        value.method,
        value.firstSequence,
        value.firstDueDate,
        value.periodMonths,
        value.anchorDay,
        value.totalInstallments,
        value.trackingStartSequence,
        value.legacyGroupKey
      }
    );
    value.definitionKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ DEFINITION_TAG, value.scheduleKey, 1 }
    );
    value.referenceKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ REFERENCE_TAG, value.scheduleKey, 1, 'INITIAL' }
    );

    String canonical = AXF_CLS_IdentityFraming.frame(
      new List<Object>{
        PAYLOAD_TAG,
        input.accountId,
        value.contractId,
        value.direction,
        value.currencyIsoCode,
        value.method,
        value.totalInstallments,
        value.firstSequence,
        value.firstDueDate,
        value.periodMonths,
        value.anchorDay,
        value.trackingStartSequence,
        value.horizonMonths,
        value.principal,
        value.periodRate,
        value.fixedValue,
        value.recurringFee,
        value.upfrontFee,
        value.referenceAmount,
        value.timeZone,
        value.legacyGroupKey
      }
    );
    value.payloadHash = AXF_CLS_IdentityFraming.sha256Hex(canonical);
    value.operationKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        OPERATION_TAG,
        OPERATION_CREATE,
        value.scheduleKey,
        value.payloadHash
      }
    );
    value.canonicalJson = JSON.serialize(
      new Map<String, Object>{
        'tag' => PAYLOAD_TAG,
        'canonical' => canonical,
        'payloadHash' => value.payloadHash,
        'scheduleKey' => value.scheduleKey
      }
    );
    return value;
  }

  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }

  private static Decimal normalizeMoney(Decimal value, String label) {
    if (value == null) {
      return null;
    }
    if (value < 0) {
      throw new ServiceException(label + ' não pode ser negativo.');
    }
    Decimal scaled = value.setScale(MONEY_SCALE);
    if (scaled > MAX_AMOUNT) {
      throw new ServiceException(
        label +
        ' excede o limite efetivo de magnitude já em uso; nada foi gravado.'
      );
    }
    return scaled;
  }

  private static Decimal normalizeRate(Decimal value) {
    if (value == null) {
      return null;
    }
    if (value < 0) {
      throw new ServiceException('Taxa do período não pode ser negativa.');
    }
    return value.setScale(RATE_SCALE);
  }

  // --- janela inicial ------------------------------------------------------

  /**
   * @description Janela inicial delimitada: do mês corrente até o fim do mês corrente mais
   * `HorizonMonths - 1`, nunca abaixo da sequência inicial de rastreamento e nunca além da
   * faixa da definição. O horizonte é o campo persistido no cronograma, e não uma constante
   * paralela. Uma parcela fora da janela permanece uma obrigação conhecida servida como virtual.
   */
  private static List<MaterializedOccurrence> buildWindow(
    Normalized normalized
  ) {
    List<MaterializedOccurrence> window = new List<MaterializedOccurrence>();
    Date today = Date.today();
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEndShifted(
      today,
      normalized.horizonMonths - 1
    );
    Integer lastCovered = (normalized.totalInstallments == null)
      ? null
      : normalized.firstSequence + normalized.totalInstallments - 1;
    // O teto de LEITURA (MAX_EVALUATED_SEQUENCES) não é o limite de PERSISTÊNCIA desta janela:
    // persistir é limitado por MAX_INITIAL_WINDOW. Uma recorrência indefinida enumera no máximo
    // uma sequência além do limite de persistência — o suficiente para que enforceWindowLimit
    // recuse a janela, em vez de truncá-la em silêncio.
    Integer upperBound = (lastCovered == null)
      ? normalized.trackingStartSequence + MAX_INITIAL_WINDOW
      : lastCovered;

    // A fórmula aprovada é gerada uma única vez por definição: a janela gravada e a projeção
    // lida consomem exatamente a mesma autoridade de cálculo.
    List<ALT_CLS_AmortizationSchedule.Occurrence> formula = (normalized.method ==
      METHOD_ESTIMATED)
      ? new List<ALT_CLS_AmortizationSchedule.Occurrence>()
      : generateFormula(normalized);

    for (
      Integer sequence = normalized.trackingStartSequence;
      sequence <= upperBound;
      sequence++
    ) {
      Date nominal = ALT_CLS_ScheduleCalendar.nominalDueDate(
        normalized.firstDueDate,
        normalized.firstSequence,
        normalized.periodMonths,
        normalized.anchorDay,
        sequence
      );
      if (nominal > windowEnd) {
        break;
      }
      window.add(materialize(normalized, formula, sequence, nominal));
    }
    return window;
  }

  private static MaterializedOccurrence materialize(
    Normalized normalized,
    List<ALT_CLS_AmortizationSchedule.Occurrence> formula,
    Integer sequence,
    Date nominal
  ) {
    MaterializedOccurrence occurrence = new MaterializedOccurrence();
    occurrence.sequence = sequence;
    occurrence.nominalDueDate = nominal;
    occurrence.amount = amountOf(normalized, formula, sequence);
    // O que a fórmula aprovada devolve é persistido como fato, não descartado: o caminho legado
    // da AXF-20 grava principal, juros, tarifa, saldo e resíduo de arredondamento da MESMA
    // fórmula, e uma ocorrência de cronograma sem essas parcelas fica incompleta.
    ALT_CLS_AmortizationSchedule.Occurrence computed = formulaOccurrence(
      normalized,
      formula,
      sequence
    );
    if (computed != null) {
      occurrence.principalPortion = computed.principalPortion;
      occurrence.interestPortion = computed.interestPortion;
      occurrence.feePortion = computed.feePortion;
      occurrence.closingBalance = computed.closingBalance;
      occurrence.roundingResidual = computed.roundingResidualApplied == true;
    }
    // O valor calculado precisa caber no limite efetivo de magnitude já em uso; estourar aqui
    // é rejeitado antes de qualquer escrita, em vez de falhar no DML depois do lock.
    if (
      occurrence.amount == null ||
      occurrence.amount > MAX_AMOUNT ||
      occurrence.amount < 0
    ) {
      throw new ServiceException(
        'O valor calculado da sequência ' +
          sequence +
          ' excede o limite efetivo de magnitude já em uso; nada foi gravado.'
      );
    }
    return occurrence;
  }

  /**
   * @description Ocorrência da fórmula aprovada para a sequência, ou nulo no método estimado —
   * que usa valor de referência e não tem decomposição de principal/juros/tarifa.
   */
  private static ALT_CLS_AmortizationSchedule.Occurrence formulaOccurrence(
    Normalized normalized,
    List<ALT_CLS_AmortizationSchedule.Occurrence> formula,
    Integer sequence
  ) {
    if (normalized.method == METHOD_ESTIMATED) {
      return null;
    }
    Integer index = sequence - normalized.firstSequence;
    if (index < 0 || index >= formula.size()) {
      throw new ServiceException(
        'A definição não cobre a sequência ' + sequence + '.'
      );
    }
    return formula[index];
  }

  /**
   * @description Valor da ocorrência na materialização, pela mesma autoridade usada pela
   * leitura: a fórmula aprovada para métodos calculados e o valor de referência no estimado.
   */
  private static Decimal amountOf(
    Normalized normalized,
    List<ALT_CLS_AmortizationSchedule.Occurrence> formula,
    Integer sequence
  ) {
    if (normalized.method == METHOD_ESTIMATED) {
      return normalized.referenceAmount;
    }
    return formulaOccurrence(normalized, formula, sequence).payment;
  }

  /** @description Ocorrências da fórmula aprovada; nenhuma fórmula nova é introduzida aqui. */
  private static List<ALT_CLS_AmortizationSchedule.Occurrence> generateFormula(
    Normalized normalized
  ) {
    ALT_CLS_AmortizationSchedule.ScheduleInput formula = new ALT_CLS_AmortizationSchedule.ScheduleInput();
    formula.modality = normalized.method;
    formula.principal = normalized.principal;
    formula.installments = normalized.totalInstallments;
    formula.periodRate = normalized.periodRate;
    formula.firstDueDate = normalized.firstDueDate;
    formula.fixedValue = normalized.fixedValue;
    formula.flatFeePerInstallment = normalized.recurringFee;
    formula.upfrontFee = normalized.upfrontFee;
    ALT_CLS_AmortizationSchedule.ScheduleResult generated;
    try {
      generated = ALT_CLS_AmortizationSchedule.generate(formula);
    } catch (System.MathException overflow) {
      // Estouro de precisão da fórmula (por exemplo `powDecimal`) é uma rejeição de entrada,
      // não uma exceção que escapa do comando.
      throw new ServiceException(
        'A fórmula aprovada estourou a precisão numérica para estes insumos.'
      );
    }
    if (generated.outcome != 'OK') {
      throw new ServiceException(
        'A fórmula aprovada não produziu o cronograma: ' + generated.message
      );
    }
    return generated.occurrences;
  }

  /**
   * @description Uma identidade de ocorrência truncada (token de idempotência de 36
   * caracteres) que já pertence a outra identidade completa é conflito, nunca replay nem
   * indisponibilidade genérica.
   */
  private static Boolean hasTruncatedIdentityCollision(
    List<MaterializedOccurrence> window,
    String scheduleKey
  ) {
    if (window == null || window.isEmpty()) {
      return false;
    }
    Map<String, String> expected = new Map<String, String>();
    for (MaterializedOccurrence occurrence : window) {
      String fullKey = ALT_CLS_ScheduleProjection.occurrenceKey(
        scheduleKey,
        occurrence.sequence
      );
      expected.put(
        ALT_CLS_ScheduleProjection.clientRequestId(fullKey),
        fullKey
      );
    }
    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT AXF_FTX_EXI_ClientRequestId__c, AXF_FTX_EXI_OccurrenceKey__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_EXI_ClientRequestId__c IN :expected.keySet()
      WITH SYSTEM_MODE
    ]) {
      String fullKey = expected.get(row.AXF_FTX_EXI_ClientRequestId__c);
      if (row.AXF_FTX_EXI_OccurrenceKey__c != fullKey) {
        return true;
      }
    }
    return false;
  }

  private static AXF_OBJ_FinancialTransaction__c toFinancialTransaction(
    MaterializedOccurrence occurrence,
    Id scheduleId,
    Id definitionId,
    Id referenceId,
    Normalized normalized,
    CreateInput input
  ) {
    String occurrenceKey = (forcedOccurrenceKey != null)
      ? forcedOccurrenceKey
      : ALT_CLS_ScheduleProjection.occurrenceKey(
          normalized.scheduleKey,
          occurrence.sequence
        );
    return new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = input.accountId,
      AXF_FTX_LKP_Contract__c = input.contractId,
      AXF_FTX_LKP_Schedule__c = scheduleId,
      AXF_FTX_LKP_ScheduleDefinition__c = definitionId,
      AXF_FTX_LKP_ScheduleReference__c = referenceId,
      AXF_FTX_EXI_OccurrenceKey__c = occurrenceKey,
      AXF_FTX_EXI_ClientRequestId__c = ALT_CLS_ScheduleProjection.clientRequestId(
        occurrenceKey
      ),
      AXF_FTX_NUM_CurrentBasis__c = occurrence.amount,
      AXF_FTX_NUM_ProjectionRevision__c = CREATE_REVISION,
      AXF_FTX_BOL_BasisFrozen__c = false,
      AXF_FTX_DAT_NominalDueDate__c = occurrence.nominalDueDate,
      AXF_FTX_DAT_DueDate__c = occurrence.nominalDueDate,
      AXF_FTX_DAT_PurchaseDate__c = occurrence.nominalDueDate,
      AXF_FTX_PKL_ScheduleState__c = OPEN_STATE,
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_NUM_Magnitude__c = occurrence.amount,
      AXF_FTX_CHK_IsEstimated__c = (normalized.method == METHOD_ESTIMATED),
      // A decomposição da fórmula aprovada é um fato financeiro da ocorrência. Em ESTIMATED
      // não há fórmula: as parcelas ficam nulas em vez de zero inventado.
      AXF_FTX_NUM_PrincipalPortion__c = occurrence.principalPortion,
      AXF_FTX_NUM_InterestPortion__c = occurrence.interestPortion,
      AXF_FTX_NUM_FeePortion__c = occurrence.feePortion,
      AXF_FTX_NUM_ClosingBalance__c = occurrence.closingBalance,
      AXF_FTX_CHK_RoundingResidual__c = occurrence.roundingResidual,
      AXF_FTX_NUM_Sequence__c = occurrence.sequence,
      AXF_FTX_PKL_Direction__c = normalized.direction,
      AXF_FTX_TXT_CurrencyIsoCode__c = normalized.currencyIsoCode,
      AXF_FTX_NUM_Version__c = 0,
      // A identidade desta via é a OccurrenceKey. `ScheduleGroupKey` pertence ao namespace de
      // idempotência de AXF_CLS_ScheduleService: reusá-lo faria os dois escritores devolverem
      // ALREADY/CONFLICT errados um para o outro. A chave legada é preservada na raiz (adoção).
      AXF_FTX_TXT_ScheduleGroupKey__c = null,
      // ESTIMATED não é uma modalidade da política de amortização: o valor vem da referência.
      AXF_FTX_PKL_Modality__c = (normalized.method == METHOD_ESTIMATED)
        ? null
        : normalized.method
    );
  }

  // --- replay --------------------------------------------------------------

  /**
   * @description Replay autorizado ou conflito. Procura o recibo de CREATE pela identidade
   * de operação; payload equivalente devolve o ResultJson original, payload alterado na mesma
   * identidade é CONFLICT.
   */
  private static CreateResult replayOrConflict(
    String scheduleKey,
    String operationKey,
    String payloadHash
  ) {
    List<AXF_OBJ_ScheduleChange__c> receipts = [
      SELECT
        Id,
        AXF_SCH_EXI_OperationKey__c,
        AXF_SCH_TXT_PayloadHash__c,
        AXF_SCH_TAL_ResultJson__c,
        AXF_SCH_LKP_Schedule__c
      FROM AXF_OBJ_ScheduleChange__c
      WHERE
        AXF_SCH_EXI_OperationKey__c = :operationKey
        AND AXF_SCH_PKL_Operation__c = :OPERATION_CREATE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!receipts.isEmpty()) {
      return replayFromReceipt(receipts[0], payloadHash);
    }
    List<AXF_OBJ_FinancialSchedule__c> roots = [
      SELECT Id, AXF_FSC_EXI_ScheduleKey__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE AXF_FSC_EXI_ScheduleKey__c = :scheduleKey
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (roots.isEmpty()) {
      return null;
    }
    CreateResult result = new CreateResult();
    result.scheduleKey = roots[0].AXF_FSC_EXI_ScheduleKey__c;
    result.scheduleId = roots[0].Id;
    return fail(
      result,
      OUTCOME_CONFLICT,
      'Já existe um cronograma com esta identidade sem recibo de criação equivalente.'
    );
  }

  /**
   * @description Resultado autorizado já confirmado para esta identidade de operação. Um
   * `ResultJson` ausente ou malformado não vira replay nem exceção de desserialização: o
   * reenvio é recusado com um desfecho controlado.
   */
  private static CreateResult replayFromReceipt(
    AXF_OBJ_ScheduleChange__c receipt,
    String payloadHash
  ) {
    CreateResult result = new CreateResult();
    result.changeId = receipt.Id;
    result.changeKey = receipt.AXF_SCH_EXI_OperationKey__c;
    List<AXF_OBJ_FinancialSchedule__c> roots = [
      SELECT Id, AXF_FSC_EXI_ScheduleKey__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :receipt.AXF_SCH_LKP_Schedule__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!roots.isEmpty()) {
      result.scheduleId = roots[0].Id;
      result.scheduleKey = roots[0].AXF_FSC_EXI_ScheduleKey__c;
    }
    if (receipt.AXF_SCH_TXT_PayloadHash__c != payloadHash) {
      return fail(
        result,
        OUTCOME_CONFLICT,
        'A identidade de operação já está confirmada com um payload diferente. O resultado original não é reaproveitado.'
      );
    }
    CreateResult stored;
    if (String.isBlank(receipt.AXF_SCH_TAL_ResultJson__c)) {
      stored = new CreateResult();
    } else {
      try {
        stored = (CreateResult) JSON.deserialize(
          receipt.AXF_SCH_TAL_ResultJson__c,
          CreateResult.class
        );
      } catch (Exception malformed) {
        return fail(
          result,
          OUTCOME_CONFLICT,
          'O resultado autorizado registrado no recibo não pôde ser lido; o reenvio é recusado em vez de inventar um desfecho.'
        );
      }
    }
    if (stored == null) {
      return fail(
        result,
        OUTCOME_CONFLICT,
        'O resultado autorizado registrado no recibo está vazio; o reenvio é recusado em vez de inventar um desfecho.'
      );
    }
    if (result.scheduleId != null) {
      stored.scheduleId = result.scheduleId;
    }
    if (result.scheduleKey != null) {
      stored.scheduleKey = result.scheduleKey;
    }
    stored.changeId = receipt.Id;
    stored.changeKey = receipt.AXF_SCH_EXI_OperationKey__c;
    stored.outcome = OUTCOME_REPLAY;
    stored.replay = true;
    stored.message = 'Operação já confirmada — o resultado original foi devolvido.';
    return stored;
  }

  // --- autorização ---------------------------------------------------------

  /**
   * @description Existe, pertence ao MESMO titular e usa a MESMA moeda? Executada depois do lock
   * do titular (holder-first) e antes de qualquer escrita: o contrato é o lock descendente
   * seguinte. Devolve nulo quando o contrato é válido.
   */
  private static CreateResult lockAndValidateContract(
    Id contractId,
    Id holderId,
    String currencyIsoCode
  ) {
    CreateResult failure = new CreateResult();
    List<AXF_OBJ_Contract__c> contracts = Database.queryWithBinds(
      'SELECT Id, AXF_CTR_LKP_Account__c, AXF_CTR_TXT_CurrencyIsoCode__c FROM AXF_OBJ_Contract__c WHERE Id = :contractId FOR UPDATE',
      new Map<String, Object>{ 'contractId' => contractId },
      AccessLevel.SYSTEM_MODE
    );
    if (contracts.isEmpty()) {
      return fail(
        failure,
        OUTCOME_INVALID,
        'O contrato informado não existe; nada foi gravado.'
      );
    }
    AXF_OBJ_Contract__c contract = contracts[0];
    if (contract.AXF_CTR_LKP_Account__c != holderId) {
      return fail(
        failure,
        OUTCOME_FORBIDDEN,
        'O contrato informado pertence a outro titular: um cronograma nunca cruza a fronteira de titular.'
      );
    }
    String contractCurrency = String.isBlank(
        contract.AXF_CTR_TXT_CurrencyIsoCode__c
      )
      ? null
      : contract.AXF_CTR_TXT_CurrencyIsoCode__c.trim().toUpperCase();
    if (contractCurrency != null && contractCurrency != currencyIsoCode) {
      return fail(
        failure,
        OUTCOME_INVALID,
        'A moeda do cronograma difere da moeda do contrato informado.'
      );
    }
    return null;
  }

  private static Boolean isAuthorized(Id accountId) {
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

  private static String sanitize(Object value) {
    return (value == null) ? 'erro desconhecido' : String.valueOf(value);
  }

  private static CreateResult fail(
    CreateResult result,
    String outcome,
    String message
  ) {
    result.outcome = outcome;
    result.message = message;
    return result;
  }
}
