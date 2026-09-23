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
 * AXF-155: periodicidade em dias (7/14, sem âncora), origem e descrição aplicadas às ocorrências
 * (janela inicial e reposição) e os comandos de mudança do contrato AXF-103 — EDIT de valor com
 * escopo FROM_SEQUENCE e TERMINATE — que só alteram ocorrências futuras não realizadas.
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
  /** Desfechos da reposição rolante da janela (fatia 2). */
  public static final String OUTCOME_GENERATED = 'GENERATED';
  public static final String OUTCOME_COMPLETE = 'COMPLETE';
  public static final String OUTCOME_NOOP = 'NOOP';
  /** Desligado por `GenerationEnabled`: pulado, nunca erro. */
  public static final String OUTCOME_SKIPPED = 'SKIPPED';
  public static final String OUTCOME_EXHAUSTED = 'EXHAUSTED';
  public static final String OUTCOME_FAILED = 'FAILED';
  public static final String OUTCOME_NOT_FOUND = 'NOT_FOUND';

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
  /**
   * AXF-155 — periodicidades em dias ratificadas: semanal (7) e quinzenal (14). Mutuamente
   * exclusivas com `periodMonths`, sem âncora de dia.
   */
  public static final Set<Integer> PERIOD_DAYS = new Set<Integer>{ 7, 14 };
  /** Limite do texto da descrição aplicada às ocorrências (`AXF_FTX_TXT_Description__c`). */
  public static final Integer MAX_DESCRIPTION_LENGTH = 255;
  /** Limite da chave de fluxo informada pelo chamador (discriminador da identidade). */
  public static final Integer MAX_STREAM_KEY_LENGTH = 120;
  /** Chaves da origem/descrição na entrada canônica da definição (AXF-155). */
  public static final String INPUT_BANK_ACCOUNT = 'bankAccountId';
  public static final String INPUT_CREDIT_CARD = 'creditCardId';
  public static final String INPUT_DESCRIPTION = 'description';
  /** Meses da janela rolante: mês corrente mais onze. */
  public static final Integer DEFAULT_HORIZON_MONTHS = 12;
  /**
   * Teto do horizonte. Materializar além do mês corrente mais onze exige aprovação humana,
   * então o comando aceita o parâmetro mas nunca o deixa passar deste valor.
   */
  public static final Integer MAX_HORIZON_MONTHS = 12;
  /** Limite efetivo de magnitude já em uso (Number(16,2)); não alarga metadado existente. */
  public static final Decimal MAX_AMOUNT = ALT_CLS_ScheduleProjection.MAX_EFFECTIVE_AMOUNT;
  /**
   * Teto de titulares lidos por `AXF_CLS_AuthorizedContextService.listAuthorizedContexts()`
   * (`LIMIT 200`). A limitação é de INFRAESTRUTURA e está DIFERIDA pela spec; ela é declarada
   * aqui apenas para que este serviço distinga "autoridade negada" de "autoridade não concluída".
   */
  public static final Integer AUTHORIZED_CONTEXT_LIMIT = 200;
  /** Vereditos de autoridade do titular. */
  private static final String AUTHORITY_GRANTED = 'GRANTED';
  private static final String AUTHORITY_DENIED = 'DENIED';
  private static final String AUTHORITY_TRUNCATED = 'TRUNCATED';
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
    /**
     * AXF-155 — periodicidade em dias (7 ou 14), mutuamente exclusiva com `periodMonths`. Sem
     * âncora: o vencimento avança exatamente `periodDays` por sequência.
     */
    @AuraEnabled
    public Integer periodDays;
    /**
     * AXF-155 — origem das ocorrências (conta corrente/carteira OU cartão), gravada na entrada
     * canônica da definição e aplicada a toda ocorrência materializada.
     */
    @AuraEnabled
    public Id bankAccountId;
    @AuraEnabled
    public Id creditCardId;
    /** AXF-155 — descrição aplicada às ocorrências materializadas. */
    @AuraEnabled
    public String description;
    /** AXF-155 — cronogramas das telas de Recorrências nascem com a geração ligada. */
    @AuraEnabled
    public Boolean generationEnabled;
    /**
     * AXF-155 — discriminador de fluxo informado pelo chamador (a chave de operação da tela). Dois
     * fluxos do mesmo titular com o mesmo calendário não colidem; ausente, a identidade legada é
     * preservada byte a byte.
     */
    @AuraEnabled
    public String streamKey;
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

  /**
   * Entrada da reposição. O titular é resolvido pelo caminho privilegiado declarado do job
   * (`AXF_CLS_ScheduleReplenishmentSelector`) para que a porta de escrita consiga distinguir
   * "não existe" de "existe e o principal não o enxerga". Ele NÃO é uma autorização: o serviço
   * compara com o titular realmente gravado na raiz e revalida a autoridade do titular antes de
   * qualquer escrita.
   */
  public class ReplenishmentRequest {
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public Id holderId;
    /**
     * Passagem de recuperação DIRIGIDA: o operador já corrigiu a causa apontada pelo estado
     * acionável, então o portão de despacho (orçamento esgotado, código terminal) é ignorado
     * nesta chamada. A revalidação de estado, autoridade e permissão continua valendo.
     */
    @AuraEnabled
    public Boolean recovery = false;
  }

  /**
   * Desfecho de UMA passagem de reposição sobre UM cronograma. É também o relato por cronograma
   * exigido do despacho em lote: cada cronograma carrega o próprio resultado, sem tudo-ou-nada.
   */
  public class ReplenishmentResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public String scheduleKey;
    @AuraEnabled
    public Integer createdCount = 0;
    @AuraEnabled
    public Integer firstCreatedSequence;
    @AuraEnabled
    public Integer lastCreatedSequence;
    @AuraEnabled
    public Integer previousCoverageSequence;
    /** Cursor de cobertura reconciliado PELA PRODUÇÃO sob o lock, nunca pelo plano pré-lock. */
    @AuraEnabled
    public Integer coverageSequence;
    /** Há ocorrência elegível além do limite desta transação: a continuação precisa encadear. */
    @AuraEnabled
    public Boolean moreWork = false;
    /** O termo terminou: nada mais será criado, nem agora nem depois. */
    @AuraEnabled
    public Boolean termReached = false;
    /** O motor truncou por teto de avaliação: cobertura PARCIAL, sem queimar tentativa. */
    @AuraEnabled
    public Boolean evaluationCut = false;
    @AuraEnabled
    public Date windowEndDate;
    @AuraEnabled
    public Long financialVersion;
    /** Código de erro higienizado, quando a passagem falhou. */
    @AuraEnabled
    public String errorCode;
    @AuraEnabled
    public Boolean terminal = false;
    @AuraEnabled
    public Integer retryCount;
    @AuraEnabled
    public DateTime nextAttemptAt;
    @AuraEnabled
    public Integer delayMinutes;
    @AuraEnabled
    public Boolean retryExhausted = false;
    /** As identidades já existiam com a sequência correta: releitura autorizada, nada duplicado. */
    @AuraEnabled
    public Boolean replay = false;
    /**
     * O estado acionável foi de fato PERSISTIDO? `false` significa que o desfecho terminal existe
     * mas o registro operacional foi recusado — o operador precisa ver isso em vez de encontrar um
     * cronograma parado sem motivo.
     */
    @AuraEnabled
    public Boolean statePersisted = false;
    /** Motivo higienizado da recusa da gravação do estado operacional, quando houve. */
    @AuraEnabled
    public String stateWriteFailure;
  }

  /**
   * Metadado de falha persistido em transação SEPARADA e limitada (o finalizador da fila), depois
   * que a transação de geração abortou e reverteu o efeito financeiro parcial.
   */
  public class FailureRecord {
    @AuraEnabled
    public String errorCode;
    @AuraEnabled
    public Integer retryCount;
    @AuraEnabled
    public DateTime nextAttemptAt;
    /** Atraso que cabe no enqueue atrasado; nulo no degrau de 30 minutos e no esgotado. */
    @AuraEnabled
    public Integer delayMinutes;
    /** Orçamento esgotado ou código terminal: nada é reagendado e o estado fica acionável. */
    @AuraEnabled
    public Boolean terminal = false;
    /** O estado acionável foi gravado? Ver `ReplenishmentResult.statePersisted`. */
    @AuraEnabled
    public Boolean statePersisted = false;
    @AuraEnabled
    public String stateWriteFailure;
  }

  /** Código de falha forçado por teste, para exercitar o caminho de DML parcialmente aplicada. */
  @TestVisible
  private static String forcedReplenishmentFailureCode;

  /**
   * Seam de teste declarado da RELEITURA SOB O LOCK: a revisão de projeção e o ponteiro de
   * definição OBSERVADOS depois de o titular ter sido travado. Ele existe porque a divergência
   * real (uma definição confirmada entre a leitura autorizada e o lock) não é produzível dentro de
   * uma transação de teste; o que o seam muda é apenas o VALOR OBSERVADO, e a rechecagem que ele
   * exercita é a de produção.
   */
  @TestVisible
  private static Long lockedRevisionOverrideForTest;
  @TestVisible
  private static Id lockedDefinitionOverrideForTest;
  /** Força o resultado da leitura autorizada, para exercitar cada desfecho de bloqueio. */
  @TestVisible
  private static ALT_CLS_ScheduleProjection.ProjectionResult projectionOverrideForTest;
  /** Força a leitura autorizada a devolver NULO, para exercitar o desfecho sem resultado. */
  @TestVisible
  private static Boolean forceNullProjectionForTest = false;
  /** Força a leitura autorizada a lançar, para exercitar a classificação de exceções reais. */
  @TestVisible
  private static Exception authorizedReadFailureForTest;
  /** Reduz o teto declarado de identidades rastreadas, para exercitar o limite sem 4001 linhas. */
  @TestVisible
  private static Integer trackedIdentityCeilingOverrideForTest;
  /**
   * Teto EFETIVO de contextos autorizados nesta transação. O default é o teto real do serviço de
   * contextos (200); o teste o reduz para exercitar a leitura INCONCLUSIVA.
   */
  @TestVisible
  private static Integer authorizedContextLimitForTest = AUTHORIZED_CONTEXT_LIMIT;
  /**
   * Rastro da ORDEM dos passos do caminho da reposição (lock antes de descendentes). Nulo fora de
   * teste: nenhum consumidor de runtime paga por ele.
   */
  @TestVisible
  private static List<String> lockTraceForTest;

  /** Observa se o lock do titular foi adquirido no caminho da reposição. */
  @TestVisible
  private static Boolean lastReplenishmentLockedHolder = false;

  /** Observa a captura do plano pré-lock, para provar que o cursor não vem dele. */
  @TestVisible
  private static Integer lastPreLockCoverage;

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
    // O modo de acesso é parâmetro: o comando de usuário trava com USER_MODE, e o caminho do job
    // (que já revalidou a autoridade do titular) trava pelo caminho privilegiado declarado.
    lastRunLockedHolder = true;
    if (!lockHolder(input.accountId, AccessLevel.USER_MODE)) {
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

    // AXF-155: a origem aplicada às ocorrências pertence ao MESMO titular — validada sob o lock e
    // antes de qualquer escrita.
    if (!originBelongsTo(normalized, input.accountId)) {
      return fail(
        result,
        OUTCOME_INVALID,
        'A origem informada não pertence ao titular do cronograma; nada foi gravado.'
      );
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
        AXF_FSC_TXT_LegacyGroupKey__c = normalized.legacyGroupKey,
        AXF_FSC_BOL_GenerationEnabled__c = normalized.generationEnabled
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
        AXF_SDF_NUM_PeriodDays__c = normalized.periodDays,
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

  // --- reposição rolante da janela (fatia 2) -------------------------------

  /**
   * @description Materialização de reposição na porta única de escrita: cria SOMENTE as
   * identidades de ocorrência ausentes dentro da janela rolante, avança o cursor de cobertura
   * para o prefixo contíguo efetivamente contabilizado e persiste o metadado de execução, tudo na
   * mesma transação. Nenhuma linha existente é tocada: ocorrência realizada, parcialmente paga,
   * cancelada ou com override manual permanece intacta porque esta passagem não faz UPDATE em FTX
   * nem reescreve `Magnitude` (guarda AXF-25 preservada). A reposição é atualização de cache em
   * transações limitadas e NÃO grava recibo de comando de domínio: nenhum `SCH` nasce daqui.
   *
   * O que falta é decidido pelo motor único de projeção — o mesmo critério que a leitura usa — e
   * recortado por `ALT_CLS_ScheduleReplenishment`. A projeção acontece ANTES do lock, para não
   * segurar a linha do titular durante trabalho de CPU; o titular é então travado
   * (`Account FOR UPDATE`, holder-first) e a raiz é RELIDA sob o lock, com enabled-state,
   * autoridade, permissão e identidades revalidados. O cursor reconciliado é recalculado pela
   * produção a partir do estado lido sob o lock, nunca aceito do plano pré-lock.
   *
   * Falha de escrita não devolve sucesso parcial: o efeito financeiro é revertido por savepoint e
   * o desfecho é `FAILED` com código higienizado. Quem chama registra o metadado de falha em
   * transação separada e limitada (`recordReplenishmentFailure`), como o contrato exige.
   */
  public static ReplenishmentResult replenishSchedule(
    ReplenishmentRequest request
  ) {
    ReplenishmentResult result = new ReplenishmentResult();
    lastReplenishmentLockedHolder = false;
    lastPreLockCoverage = null;
    if (request == null || request.scheduleId == null) {
      return replenishmentFail(
        result,
        OUTCOME_INVALID,
        'Cronograma é obrigatório para repor a janela.',
        null
      );
    }
    result.scheduleId = request.scheduleId;
    Boolean recovery = request.recovery == true;

    AXF_OBJ_FinancialSchedule__c root = readSchedule(request.scheduleId);
    if (root == null) {
      // A leitura usa o escopo de compartilhamento desta classe: `AccessLevel.SYSTEM_MODE`
      // desliga permissão de objeto e FLS, e NÃO amplia visibilidade de registro. Quem enxerga o
      // trabalho é o caminho privilegiado declarado do job, que resolve o titular; quando ele
      // resolveu um titular e ainda assim a raiz não aparece, o desfecho é a ausência de
      // visibilidade do principal.
      if (request.holderId == null) {
        return replenishmentFail(
          result,
          OUTCOME_NOT_FOUND,
          'Cronograma não encontrado neste escopo.',
          null
        );
      }
      return terminalFail(
        result,
        OUTCOME_FORBIDDEN,
        'O cronograma existe, mas o principal que executa a reposição não tem visibilidade nativa sobre ele. Provisione a visibilidade do registro; repetir não resolve.',
        ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY
      );
    }
    result.scheduleKey = root.AXF_FSC_EXI_ScheduleKey__c;
    lastPreLockCoverage = intOf(root.AXF_FSC_NUM_CoverageSequence__c);

    Id holderId = root.AXF_FSC_LKP_Account__c;
    if (request.holderId != null && request.holderId != holderId) {
      return replenishmentFail(
        result,
        OUTCOME_FORBIDDEN,
        'O titular informado não é o titular gravado na raiz do cronograma; nada foi gerado.',
        null
      );
    }
    if (holderId == null) {
      return terminalFail(
        result,
        OUTCOME_FORBIDDEN,
        'O cronograma não possui titular; a autoridade não pode ser conferida e nada é gerado.',
        ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY
      );
    }
    // Autoridade do titular (AXF-3) revalidada a cada transação e a cada lote. O veredito
    // distingue três desfechos: autorizado, NEGADO e INCONCLUSIVO — este último quando o teto
    // diferido de titulares do serviço de contextos impede concluir. Confundir os dois últimos
    // gravaria um estado permanente e bloqueante de despacho que nenhuma correção de visibilidade
    // limpa.
    String authority = authorityVerdict(holderId);
    if (authority == AUTHORITY_TRUNCATED) {
      return replenishmentFail(
        result,
        OUTCOME_FAILED,
        'A autoridade do titular não pôde ser CONCLUÍDA: o serviço de contextos autorizados lê os titulares visíveis com um teto de ' +
          AUTHORIZED_CONTEXT_LIMIT +
          ' registros (limitação de infraestrutura diferida pela spec). Este desfecho NÃO é permanente e não bloqueia o despacho: nada foi gerado e a passagem seguinte relê.',
        ALT_CLS_ScheduleReplenishment.ERROR_AUTHORITY_TRUNCATED
      );
    }
    if (authority != AUTHORITY_GRANTED) {
      return terminalFail(
        result,
        OUTCOME_FORBIDDEN,
        'O principal que executa a reposição não enxerga a entidade titular do cronograma. Este é um desfecho permanente: provisione a visibilidade do titular; repetir não resolve.',
        ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY
      );
    }
    // Permissão revalidada a cada transação: sem CRUD de criação na ocorrência, nada é gerado.
    if (!canGenerateOccurrences()) {
      return terminalFail(
        result,
        OUTCOME_FORBIDDEN,
        'O principal que executa a reposição não tem permissão para criar ocorrências: nada foi gerado.',
        ALT_CLS_ScheduleReplenishment.ERROR_PERMISSION_DENIED
      );
    }
    if (root.AXF_FSC_PKL_State__c != STATE_ACTIVE) {
      // Um cronograma que não está ACTIVE não gera: o desfecho é pulado, não erro.
      return replenishmentFail(
        result,
        OUTCOME_SKIPPED,
        'O cronograma não está ACTIVE: nenhuma ocorrência nova foi criada e as obrigações seguem visíveis na leitura.',
        null
      );
    }
    if (root.AXF_FSC_BOL_GenerationEnabled__c != true) {
      // Desligar nunca esconde a obrigação: nenhuma linha nova, nenhum erro.
      return replenishmentFail(
        result,
        OUTCOME_SKIPPED,
        'Geração desabilitada neste cronograma: nenhuma ocorrência nova foi criada e as obrigações seguem visíveis na leitura.',
        null
      );
    }
    if (
      !recovery &&
      ALT_CLS_ScheduleReplenishment.blocksDispatch(
        root.AXF_FSC_TXT_LastErrorCode__c,
        intOf(root.AXF_FSC_NUM_RetryCount__c),
        ALT_CLS_ScheduleReplenishment.MAX_RETRY_COUNT
      )
    ) {
      return replenishmentFail(
        result,
        OUTCOME_EXHAUSTED,
        'O orçamento de tentativas se esgotou (ou há estado terminal registrado): nenhuma nova tentativa é agendada automaticamente e as obrigações seguem visíveis na leitura. Corrija a causa apontada por ' +
          ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
            root.AXF_FSC_TXT_LastErrorCode__c
          ) +
          ' e use a passagem de recuperação dirigida para retomar.',
        ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
          root.AXF_FSC_TXT_LastErrorCode__c
        )
      );
    }

    ALT_CLS_ScheduleProjection.ProjectionResult projection;
    try {
      if (authorizedReadFailureForTest != null) {
        throw authorizedReadFailureForTest;
      }
      if (forceNullProjectionForTest) {
        projection = null;
      } else if (projectionOverrideForTest != null) {
        projection = projectionOverrideForTest;
      } else {
        ALT_CLS_ScheduleProjection.ProjectionInput projectionInput = new ALT_CLS_ScheduleProjection.ProjectionInput();
        projectionInput.scheduleId = request.scheduleId;
        projectionInput.asOfDate = Date.today();
        projection = ALT_CLS_ScheduleProjection.project(projectionInput);
      }
    } catch (Exception failure) {
      // A classificação decide se a passagem REPETE (recuo limitado) ou PARA. Um estouro
      // numérico determinístico da fórmula aprovada não melhora por repetição: ele é permanente
      // e imediato, e não pode queimar o orçamento até virar `RETRY_EXHAUSTED` por engano.
      return classifyFailure(
        result,
        OUTCOME_FAILED,
        'A leitura autorizada do cronograma falhou antes de qualquer escrita.',
        replenishmentErrorCode(failure)
      );
    }
    ReplenishmentResult rejection = rejectProjection(projection, result);
    if (rejection != null) {
      return rejection;
    }

    ALT_CLS_ScheduleReplenishment.PlanInput planInput = new ALT_CLS_ScheduleReplenishment.PlanInput();
    planInput.lines = projection.lines;
    planInput.windowEndDate = projection.horizonEndDate;
    planInput.trackingStartSequence = projection.trackingStartSequence;
    planInput.coverageSequence = lastPreLockCoverage;
    planInput.maxOccurrences = ALT_CLS_ScheduleReplenishment.MAX_OCCURRENCES_PER_TRANSACTION;
    planInput.unbounded = projection.unbounded;
    planInput.coverageComplete = projection.coverageComplete;
    ALT_CLS_ScheduleReplenishment.Plan plan;
    try {
      plan = ALT_CLS_ScheduleReplenishment.plan(planInput);
    } catch (ALT_CLS_ScheduleReplenishment.ReplenishmentException invalidPlan) {
      return terminalFail(
        result,
        OUTCOME_INVALID,
        'O recorte da janela rolante foi recusado pelo motor de regra.',
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_BLOCKED
      );
    }
    result.windowEndDate = plan.windowEndDate;
    result.previousCoverageSequence = plan.previousCoverageSequence;
    result.moreWork = plan.moreWork;
    result.termReached = plan.termReached;
    result.evaluationCut = plan.evaluationCut;

    // Serialização holder-first: o titular é o PRIMEIRO lock, antes de qualquer descendente.
    lastReplenishmentLockedHolder = lockHolder(
      holderId,
      AccessLevel.SYSTEM_MODE
    );
    traceLockStep('HOLDER_LOCK');
    if (!lastReplenishmentLockedHolder) {
      return replenishmentFail(
        result,
        OUTCOME_FAILED,
        'O titular não está disponível para escrita neste momento.',
        ALT_CLS_ScheduleReplenishment.ERROR_HOLDER_UNAVAILABLE
      );
    }

    // Releitura sob o lock: estado, enabled-state e titular são revalidados AQUI, e não apenas na
    // leitura pré-lock, porque entre as duas leituras o cronograma pode ter sido desligado.
    AXF_OBJ_FinancialSchedule__c locked = readSchedule(request.scheduleId);
    traceLockStep('LOCKED_ROOT_READ');
    if (locked == null || locked.AXF_FSC_LKP_Account__c != holderId) {
      return replenishmentFail(
        result,
        OUTCOME_UNAVAILABLE,
        'O cronograma não está mais disponível sob o lock do titular; nada foi gravado.',
        ALT_CLS_ScheduleReplenishment.ERROR_HOLDER_UNAVAILABLE
      );
    }
    if (locked.AXF_FSC_PKL_State__c != STATE_ACTIVE) {
      return replenishmentFail(
        result,
        OUTCOME_SKIPPED,
        'O cronograma deixou de estar ACTIVE sob o lock: nenhuma ocorrência nova foi criada.',
        null
      );
    }
    if (locked.AXF_FSC_BOL_GenerationEnabled__c != true) {
      return replenishmentFail(
        result,
        OUTCOME_SKIPPED,
        'A geração foi desabilitada sob o lock: nenhuma ocorrência nova foi criada e as obrigações seguem visíveis na leitura.',
        null
      );
    }
    if (
      !recovery &&
      ALT_CLS_ScheduleReplenishment.blocksDispatch(
        locked.AXF_FSC_TXT_LastErrorCode__c,
        intOf(locked.AXF_FSC_NUM_RetryCount__c),
        ALT_CLS_ScheduleReplenishment.MAX_RETRY_COUNT
      )
    ) {
      // O estado pode ter se tornado terminal ENTRE a leitura e o lock: revalidado aqui, o
      // "terminal é permanente" não depende da leitura pré-lock.
      return replenishmentFail(
        result,
        OUTCOME_EXHAUSTED,
        'O orçamento de tentativas se esgotou (ou há estado terminal registrado) sob o lock: nenhuma nova tentativa automática é agendada e as obrigações seguem visíveis na leitura.',
        ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
          locked.AXF_FSC_TXT_LastErrorCode__c
        )
      );
    }

    // Rechecagem da REVISÃO e dos PONTEIROS vigentes SOB O LOCK (contrato L44 e L83). O plano foi
    // montado a partir da projeção pré-lock e carimba `ProjectionRevision` da raiz lida antes do
    // lock; sem esta comparação, uma definição confirmada entre as duas leituras produziria linhas
    // apontando para a definição antiga SOB A ETIQUETA da revisão nova, sem `STALE`.
    Long observedRevision = (lockedRevisionOverrideForTest != null)
      ? lockedRevisionOverrideForTest
      : projectionRevisionOf(locked);
    Id observedDefinition = (lockedDefinitionOverrideForTest != null)
      ? lockedDefinitionOverrideForTest
      : locked.AXF_FSC_LKP_ActiveDefinition__c;
    Long capturedRevision = (projection.capturedProjectionRevision == null)
      ? 0
      : projection.capturedProjectionRevision;
    if (
      observedRevision != capturedRevision ||
      observedDefinition != projection.capturedActiveDefinition
    ) {
      traceLockStep('STALE_RECHECK');
      return replenishmentFail(
        result,
        OUTCOME_FAILED,
        'A revisão vigente ou o ponteiro de definição mudou entre a leitura autorizada e o lock: nada foi gravado e a passagem será repetida com recuo limitado.',
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_STALE
      );
    }

    // Reconciliação de identidades sob o lock. Uma linha sob OUTRA identidade não conta como a
    // esperada, e uma identidade já ocupada pela sequência correta é replay — nunca duplicidade.
    Integer trackingStart = (projection.trackingStartSequence == null ||
      projection.trackingStartSequence < 1)
      ? 1
      : projection.trackingStartSequence;
    IdentitySnapshot snapshot = persistedIdentities(request.scheduleId);
    traceLockStep('IDENTITIES_READ');
    if (snapshot.truncated) {
      return terminalFail(
        result,
        OUTCOME_INVALID,
        'O cronograma tem mais identidades rastreadas do que o teto declarado de ' +
          trackedIdentityCeiling() +
          ' ocorrências por cronograma: a reconciliação do cursor não é decidível e a passagem não carrega o histórico inteiro em memória. Redimensione o cronograma ou o teto antes de retomar.',
        ALT_CLS_ScheduleReplenishment.ERROR_SCALE_LIMIT
      );
    }
    Map<Integer, String> identities = snapshot.bySequence;
    Set<Integer> accounted = new Set<Integer>();
    for (Integer sequence : identities.keySet()) {
      if (sequence == null || sequence < trackingStart) {
        continue;
      }
      if (
        identities.get(sequence) ==
        ALT_CLS_ScheduleProjection.occurrenceKey(result.scheduleKey, sequence)
      ) {
        accounted.add(sequence);
      }
    }
    List<Integer> toCreate = new List<Integer>();
    Boolean replayedIdentity = false;
    for (Integer sequence : plan.sequences) {
      String expected = ALT_CLS_ScheduleProjection.occurrenceKey(
        result.scheduleKey,
        sequence
      );
      String existing = identities.get(sequence);
      if (existing == null) {
        toCreate.add(sequence);
        continue;
      }
      if (existing != expected) {
        return terminalFail(
          result,
          OUTCOME_CONFLICT,
          'A identidade da sequência ' +
            sequence +
            ' já pertence a outra ocorrência de identidade completa diferente; nada foi gravado.',
          ALT_CLS_ScheduleReplenishment.ERROR_IDENTITY
        );
      }
      replayedIdentity = true;
      accounted.add(sequence);
    }

    // PÓS-LOCK: `moreWork` e `termReached` são RECALCULADOS a partir das identidades lidas sob o
    // lock, e não aceitos do plano pré-lock. Uma passagem que não criou nada (replay, colisão,
    // no-op) não pode re-enfileirar a si mesma e gastar uma rodada da cadeia.
    Set<Integer> plannedNow = new Set<Integer>(toCreate);
    Integer remaining = 0;
    Integer virtualBeyond = 0;
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
      if (
        line == null ||
        line.sequence == null ||
        line.sequence < trackingStart ||
        line.nominalDueDate == null
      ) {
        continue;
      }
      Boolean covered =
        accounted.contains(line.sequence) || plannedNow.contains(line.sequence);
      if (line.nominalDueDate > plan.windowEndDate) {
        if (!covered) {
          virtualBeyond++;
        }
        continue;
      }
      if (!covered) {
        remaining++;
      }
    }
    result.moreWork = remaining > 0;
    result.termReached =
      projection.unbounded != true &&
      projection.coverageComplete == true &&
      remaining == 0 &&
      virtualBeyond == 0;

    Map<Id, AXF_OBJ_ScheduleDefinition__c> definitions = definitionRows(
      request.scheduleId
    );
    List<AXF_OBJ_FinancialTransaction__c> occurrences = buildReplenishmentOccurrences(
      toCreate,
      projection,
      definitions,
      locked,
      result.scheduleKey
    );
    // A colisão de identidade é REAL: a chave `AXF_FTX_EXI_OccurrenceKey__c` é única e o insert
    // inteiro é revertido por savepoint. Nenhuma costura de produção semeia linhas concorrentes.
    Savepoint checkpoint = Database.setSavepoint();
    try {
      writing = true;
      if (!occurrences.isEmpty()) {
        Database.insert(occurrences, AccessLevel.SYSTEM_MODE);
      }
      if (forcedReplenishmentFailureCode != null) {
        // Seam de teste: falha após parte das linhas, para provar que nada parcial persiste.
        throw new ServiceException(forcedReplenishmentFailureCode);
      }
      accounted.addAll(toCreate);
      // O cursor reconciliado é recalculado pela PRODUÇÃO a partir do estado lido sob o lock —
      // nunca aceito do plano pré-lock — e nunca fica abaixo do progresso já confirmado: um
      // cursor persistido que ainda não foi reconciliado (uma lacuna abaixo dele) não é
      // rebaixado. É a verificação de LACUNA do despacho, e não o valor do cursor, que mantém
      // esse cronograma no conjunto devido até a lacuna ser materializada.
      result.coverageSequence = Math.max(
        ALT_CLS_ScheduleReplenishment.coverageAfter(trackingStart, accounted),
        intOf(locked.AXF_FSC_NUM_CoverageSequence__c)
      );
      result.createdCount = occurrences.size();
      result.firstCreatedSequence = occurrences.isEmpty()
        ? null
        : firstSequenceOf(toCreate);
      result.lastCreatedSequence = occurrences.isEmpty()
        ? null
        : lastSequenceOf(toCreate);
      persistSuccess(locked, result.coverageSequence, !occurrences.isEmpty());
      result.financialVersion = financialVersionOf(
        locked,
        !occurrences.isEmpty()
      );
      result.replay = replayedIdentity && occurrences.isEmpty();
      result.outcome = replenishmentOutcome(
        result,
        occurrences.size(),
        replayedIdentity
      );
    } catch (DmlException failure) {
      Database.rollback(checkpoint);
      return recoverFromCollision(
        request,
        toCreate,
        result,
        trackingStart,
        failure
      );
    } catch (ServiceException failure) {
      Database.rollback(checkpoint);
      return replenishmentFail(
        result,
        OUTCOME_FAILED,
        'A escrita da reposição falhou e foi revertida por inteiro.',
        forcedReplenishmentFailureCode != null
          ? ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
              forcedReplenishmentFailureCode
            )
          : ALT_CLS_ScheduleReplenishment.ERROR_DML
      );
    } catch (ALT_CLS_ScheduleProjection.ProjectionException failure) {
      Database.rollback(checkpoint);
      return terminalFail(
        result,
        OUTCOME_FAILED,
        'A ocorrência recusada pelo motor de projeção durante a escrita.',
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_BLOCKED
      );
    } catch (System.MathException failure) {
      Database.rollback(checkpoint);
      // Estouro numérico determinístico da fórmula aprovada: PERMANENTE e imediato. Repetir não
      // muda a aritmética e queimaria o orçamento até virar `RETRY_EXHAUSTED` por engano.
      return terminalFail(
        result,
        OUTCOME_FAILED,
        'A fórmula aprovada estourou a precisão numérica: desfecho permanente, repetir não resolve.',
        ALT_CLS_ScheduleReplenishment.ERROR_FORMULA
      );
    } finally {
      writing = false;
    }

    result.message = replenishmentMessage(result);
    return result;
  }

  /**
   * @description Registro do metadado de falha em transação SEPARADA e limitada: uma única linha,
   * somente `RetryCount`, `NextAttemptAt` e `LastErrorCode`. Chamado pelo finalizador da fila
   * depois que a transação de geração abortou e reverteu o efeito financeiro.
   *
   * Um código TERMINAL não consome orçamento de retry e não agenda tentativa: ele deixa o estado
   * acionável e tira o cronograma do conjunto devido, para que ele não morra de fome a cauda da
   * fila esperando uma tentativa que nunca vai progredir.
   */
  public static FailureRecord recordReplenishmentFailure(
    Id scheduleId,
    String errorCode,
    DateTime failedAt
  ) {
    FailureRecord record = new FailureRecord();
    record.errorCode = ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
      errorCode
    );
    if (scheduleId == null || failedAt == null) {
      return record;
    }
    AXF_OBJ_FinancialSchedule__c row = AXF_CLS_ScheduleReplenishmentStateWriter.read(
      scheduleId
    );
    if (row == null) {
      return record;
    }
    Integer previous = intOf(row.AXF_FSC_NUM_RetryCount__c);
    if (ALT_CLS_ScheduleReplenishment.isTerminal(record.errorCode)) {
      // Condição PERMANENTE: o orçamento fica CONGELADO (não é consumido nem reiniciado) e nada é
      // agendado automaticamente. O operador corrige a causa e usa a passagem DIRIGIDA.
      record.retryCount = previous;
      record.terminal = true;
    } else {
      ALT_CLS_ScheduleReplenishment.RetryDecision decision = ALT_CLS_ScheduleReplenishment.nextAttempt(
        previous,
        failedAt
      );
      record.retryCount = decision.retryCount;
      record.nextAttemptAt = decision.nextAttemptAt;
      record.delayMinutes = decision.delayMinutes;
      record.terminal = decision.exhausted;
      if (decision.exhausted) {
        // REALARME LIMITADO: o orçamento continua esgotado, mas o cronograma ganha um horário
        // declarado a partir do qual a passagem de recuperação tenta UMA vez de novo. Sem isso,
        // quatro falhas transitórias desligariam a reposição daquele cronograma para sempre; com
        // um reset irrestrito, uma falha permanente repetiria sem limite.
        record.errorCode = ALT_CLS_ScheduleReplenishment.ERROR_EXHAUSTED;
        record.nextAttemptAt = ALT_CLS_ScheduleReplenishment.rearmAt(
          failedAt,
          rearmHours()
        );
        record.delayMinutes = null;
      }
    }
    Boolean stateWritten = writeOperationalState(
      scheduleId,
      record.errorCode,
      record.retryCount,
      record.nextAttemptAt
    );
    record.statePersisted = stateWritten;
    record.stateWriteFailure = AXF_CLS_ScheduleReplenishmentStateWriter.failureReason();
    if (!stateWritten) {
      System.debug(
        LoggingLevel.ERROR,
        'AXF103 reposicao: estado acionavel NAO persistido. ' +
          AXF_CLS_ScheduleReplenishmentStateWriter.describeLastOutcome() +
          ' codigo=' +
          record.errorCode
      );
    }
    return record;
  }

  /** Janela declarada do realarme; ausência de política aprovada usa o default declarado. */
  private static Integer rearmHours() {
    try {
      return AXF_CLS_ScheduleReplenishmentPolicy.current().rearmHours;
    } catch (AXF_CLS_ScheduleReplenishmentPolicy.PolicyException unavailable) {
      return ALT_CLS_ScheduleReplenishment.DEFAULT_REARM_HOURS;
    }
  }

  /**
   * @description Gravação do metadado operacional de execução: UMA linha, somente `RetryCount`,
   * `NextAttemptAt` e `LastErrorCode`.
   *
   * Ela NÃO acontece dentro desta classe, e isso é uma decisão de plataforma verificada neste
   * org: o job precisa registrar um desfecho permanente justamente quando o principal NÃO enxerga
   * o cronograma, e tanto a leitura quanto a DML respeitam a visibilidade de registro da classe
   * onde o código é declarado. O caminho privilegiado declarado é
   * `AXF_CLS_ScheduleReplenishmentStateWriter`, cuja capacidade é aceita pelo handler da raiz
   * SOMENTE para estes três campos — e que adquire o lock do titular ANTES da DML.
   */
  @TestVisible
  private static Boolean writeOperationalState(
    Id scheduleId,
    String errorCode,
    Integer retryCount,
    DateTime nextAttemptAt
  ) {
    return AXF_CLS_ScheduleReplenishmentStateWriter.write(
      scheduleId,
      errorCode,
      retryCount,
      nextAttemptAt
    );
  }

  // --- reposição: apoio ----------------------------------------------------

  private static AXF_OBJ_FinancialSchedule__c readSchedule(Id scheduleId) {
    List<AXF_OBJ_FinancialSchedule__c> rows = [
      SELECT
        Id,
        AXF_FSC_EXI_ScheduleKey__c,
        AXF_FSC_LKP_Account__c,
        AXF_FSC_LKP_Contract__c,
        AXF_FSC_TXT_CurrencyIsoCode__c,
        AXF_FSC_PKL_Direction__c,
        AXF_FSC_PKL_State__c,
        AXF_FSC_NUM_TrackingStartSequence__c,
        AXF_FSC_NUM_HorizonMonths__c,
        AXF_FSC_NUM_ProjectionRevision__c,
        AXF_FSC_NUM_CoverageSequence__c,
        AXF_FSC_NUM_FinancialVersion__c,
        AXF_FSC_NUM_RetryCount__c,
        AXF_FSC_DT_NextAttemptAt__c,
        AXF_FSC_TXT_LastErrorCode__c,
        AXF_FSC_BOL_GenerationEnabled__c,
        AXF_FSC_LKP_ActiveDefinition__c,
        AXF_FSC_LKP_ActiveReference__c,
        AXF_FSC_NUM_Version__c,
        AXF_FSC_DAT_TerminationDate__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :scheduleId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /**
   * @description Lock do titular extraído com o modo de acesso como PARÂMETRO: o comando de
   * usuário trava com `USER_MODE`, e o caminho do job (que já revalidou estado, autoridade do
   * titular e permissão) trava pelo caminho privilegiado declarado. É sempre o PRIMEIRO lock,
   * antes de qualquer descendente.
   */
  private static Boolean lockHolder(Id accountId, AccessLevel mode) {
    if (accountId == null) {
      return false;
    }
    List<SObject> holders = Database.queryWithBinds(
      'SELECT Id FROM Account WHERE Id = :holderId FOR UPDATE',
      new Map<String, Object>{ 'holderId' => accountId },
      mode
    );
    return holders.size() == 1;
  }

  /** @description Permissão de criação da ocorrência, revalidada a cada transação. */
  private static Boolean canGenerateOccurrences() {
    return AXF_OBJ_FinancialTransaction__c.SObjectType.getDescribe()
      .isCreateable();
  }

  /**
   * @description Identidades rastreadas lidas em memória, com o sinal de TETO excedido.
   */
  private class IdentitySnapshot {
    public Map<Integer, String> bySequence = new Map<Integer, String>();
    public Boolean truncated = false;
  }

  /** Teto declarado desta transação (o teste o reduz para exercitar o limite). */
  private static Integer trackedIdentityCeiling() {
    return (trackedIdentityCeilingOverrideForTest == null)
      ? ALT_CLS_ScheduleReplenishment.MAX_TRACKED_IDENTITIES_PER_SCHEDULE
      : trackedIdentityCeilingOverrideForTest;
  }

  /**
   * @description As identidades persistidas do cronograma, por sequência. É a leitura que a
   * produção faz sob o lock para reconciliar cobertura — nunca o plano montado antes dele.
   *
   * A leitura é LIMITADA pelo teto declarado: acima dele a passagem RECUSA em vez de carregar o
   * histórico inteiro em memória e estourar o heap no meio do savepoint. O teto é asserido em
   * teste, e a recusa é um código sanitizado (`SCALE_LIMIT_EXCEEDED`) com mensagem acionável.
   */
  private static IdentitySnapshot persistedIdentities(Id scheduleId) {
    IdentitySnapshot snapshot = new IdentitySnapshot();
    Integer ceiling = trackedIdentityCeiling();
    Integer probe = ceiling + 1;
    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT AXF_FTX_NUM_Sequence__c, AXF_FTX_EXI_OccurrenceKey__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :scheduleId
      WITH SYSTEM_MODE
      LIMIT :probe
    ]) {
      if (row.AXF_FTX_NUM_Sequence__c == null) {
        continue;
      }
      snapshot.bySequence.put(
        row.AXF_FTX_NUM_Sequence__c.intValue(),
        row.AXF_FTX_EXI_OccurrenceKey__c
      );
    }
    snapshot.truncated = snapshot.bySequence.size() > ceiling;
    return snapshot;
  }

  /** @description Definições do cronograma, por Id, para reusar a fórmula aprovada. */
  private static Map<Id, AXF_OBJ_ScheduleDefinition__c> definitionRows(
    Id scheduleId
  ) {
    Map<Id, AXF_OBJ_ScheduleDefinition__c> definitions = new Map<Id, AXF_OBJ_ScheduleDefinition__c>();
    for (AXF_OBJ_ScheduleDefinition__c definition : [
      SELECT
        Id,
        AXF_SDF_PKL_Method__c,
        AXF_SDF_NUM_FirstSequence__c,
        AXF_SDF_DAT_FirstDueDate__c,
        AXF_SDF_NUM_PeriodMonths__c,
        AXF_SDF_NUM_PeriodDays__c,
        AXF_SDF_NUM_TotalInstallments__c,
        AXF_SDF_NUM_Principal__c,
        AXF_SDF_NUM_PeriodRate__c,
        AXF_SDF_NUM_FixedValue__c,
        AXF_SDF_NUM_RecurringFee__c,
        AXF_SDF_NUM_UpfrontFee__c,
        AXF_SDF_TAL_InputCanonicalJson__c
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE AXF_SDF_LKP_Schedule__c = :scheduleId
      WITH SYSTEM_MODE
    ]) {
      definitions.put(definition.Id, definition);
    }
    return definitions;
  }

  /**
   * @description Ocorrências a materializar com AS MESMAS porções e evidência da criação.
   * O VALOR vem da linha do motor único de projeção (nenhum valor é recalculado aqui) e a
   * decomposição vem da fórmula aprovada, pela mesma autoridade pura da criação.
   */
  private static List<AXF_OBJ_FinancialTransaction__c> buildReplenishmentOccurrences(
    List<Integer> sequences,
    ALT_CLS_ScheduleProjection.ProjectionResult projection,
    Map<Id, AXF_OBJ_ScheduleDefinition__c> definitions,
    AXF_OBJ_FinancialSchedule__c root,
    String scheduleKey
  ) {
    List<AXF_OBJ_FinancialTransaction__c> occurrences = new List<AXF_OBJ_FinancialTransaction__c>();
    if (sequences.isEmpty()) {
      return occurrences;
    }
    Map<Integer, ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new Map<Integer, ALT_CLS_ScheduleProjection.OccurrenceLine>();
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
      if (line != null && line.sequence != null) {
        lines.put(line.sequence, line);
      }
    }
    Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>> formulas = new Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>>();
    Long revision = (root.AXF_FSC_NUM_ProjectionRevision__c == null)
      ? 0
      : root.AXF_FSC_NUM_ProjectionRevision__c.longValue();
    for (Integer sequence : sequences) {
      ALT_CLS_ScheduleProjection.OccurrenceLine line = lines.get(sequence);
      if (line == null || line.nominalDueDate == null) {
        throw new ServiceException(
          'A projeção autorizada não cobre a sequência ' + sequence + '.'
        );
      }
      AXF_OBJ_ScheduleDefinition__c definition = definitions.get(
        line.definitionId
      );
      if (definition == null) {
        throw new ServiceException(
          'A sequência ' +
            sequence +
            ' não tem definição vigente do próprio cronograma.'
        );
      }
      Decimal amount = line.amount;
      if (amount == null || amount < 0 || amount > MAX_AMOUNT) {
        throw new ServiceException(
          'O valor da sequência ' +
            sequence +
            ' está fora do limite efetivo de magnitude já em uso.'
        );
      }
      Boolean estimated = definition.AXF_SDF_PKL_Method__c == METHOD_ESTIMATED;
      ALT_CLS_AmortizationSchedule.Occurrence computed = formulaPortions(
        definition,
        sequence,
        formulas
      );
      String occurrenceKey = ALT_CLS_ScheduleProjection.occurrenceKey(
        scheduleKey,
        sequence
      );
      // AXF-155: a reposição aplica a MESMA origem e descrição gravadas na entrada canônica da
      // definição vigente daquela sequência.
      Map<String, Object> canonicalInput = canonicalInputOf(definition);
      occurrences.add(
        new AXF_OBJ_FinancialTransaction__c(
          AXF_FTX_LKP_BankAccount__c = (Id) canonicalInput.get(
            INPUT_BANK_ACCOUNT
          ),
          AXF_FTX_LKP_CreditCard__c = (Id) canonicalInput.get(
            INPUT_CREDIT_CARD
          ),
          AXF_FTX_TXT_Description__c = (String) canonicalInput.get(
            INPUT_DESCRIPTION
          ),
          AXF_FTX_LKP_Account__c = root.AXF_FSC_LKP_Account__c,
          AXF_FTX_LKP_Contract__c = root.AXF_FSC_LKP_Contract__c,
          AXF_FTX_LKP_Schedule__c = root.Id,
          AXF_FTX_LKP_ScheduleDefinition__c = line.definitionId,
          AXF_FTX_LKP_ScheduleReference__c = line.referenceId,
          AXF_FTX_EXI_OccurrenceKey__c = occurrenceKey,
          AXF_FTX_EXI_ClientRequestId__c = ALT_CLS_ScheduleProjection.clientRequestId(
            occurrenceKey
          ),
          AXF_FTX_NUM_CurrentBasis__c = amount,
          AXF_FTX_NUM_ProjectionRevision__c = revision,
          AXF_FTX_BOL_BasisFrozen__c = false,
          AXF_FTX_DAT_NominalDueDate__c = line.nominalDueDate,
          AXF_FTX_DAT_DueDate__c = line.nominalDueDate,
          AXF_FTX_DAT_PurchaseDate__c = line.nominalDueDate,
          AXF_FTX_PKL_ScheduleState__c = OPEN_STATE,
          AXF_FTX_PKL_Status__c = 'PLANNED',
          AXF_FTX_PKL_PlanKind__c = 'PLANNED',
          AXF_FTX_NUM_Magnitude__c = amount,
          AXF_FTX_CHK_IsEstimated__c = estimated,
          AXF_FTX_NUM_PrincipalPortion__c = (computed == null)
            ? null
            : computed.principalPortion,
          AXF_FTX_NUM_InterestPortion__c = (computed == null)
            ? null
            : computed.interestPortion,
          AXF_FTX_NUM_FeePortion__c = (computed == null)
            ? null
            : computed.feePortion,
          AXF_FTX_NUM_ClosingBalance__c = (computed == null)
            ? null
            : computed.closingBalance,
          AXF_FTX_CHK_RoundingResidual__c = computed != null &&
            computed.roundingResidualApplied == true,
          AXF_FTX_NUM_Sequence__c = sequence,
          AXF_FTX_PKL_Direction__c = root.AXF_FSC_PKL_Direction__c,
          AXF_FTX_TXT_CurrencyIsoCode__c = root.AXF_FSC_TXT_CurrencyIsoCode__c,
          AXF_FTX_NUM_Version__c = 0,
          // A identidade desta via é a OccurrenceKey. `ScheduleGroupKey` pertence ao namespace de
          // idempotência de AXF_CLS_ScheduleService: reusá-lo faria os dois escritores devolverem
          // ALREADY/CONFLICT errados um para o outro.
          AXF_FTX_TXT_ScheduleGroupKey__c = null,
          // ESTIMATED não é uma modalidade da política de amortização: o valor vem da referência.
          AXF_FTX_PKL_Modality__c = estimated
            ? null
            : definition.AXF_SDF_PKL_Method__c
        )
      );
    }
    return occurrences;
  }

  /**
   * @description AXF-155 — entrada canônica da definição como mapa, com a origem (`Id`) e a
   * descrição tipadas. Uma entrada ausente ou ilegível não inventa origem: devolve vazio.
   */
  public static Map<String, Object> canonicalInputOf(
    AXF_OBJ_ScheduleDefinition__c definition
  ) {
    Map<String, Object> values = new Map<String, Object>();
    String raw = (definition == null)
      ? null
      : definition.AXF_SDF_TAL_InputCanonicalJson__c;
    if (String.isBlank(raw)) {
      return values;
    }
    Map<String, Object> parsed;
    try {
      parsed = (Map<String, Object>) JSON.deserializeUntyped(raw);
    } catch (Exception malformed) {
      return values;
    }
    for (
      String key : new List<String>{ INPUT_BANK_ACCOUNT, INPUT_CREDIT_CARD }
    ) {
      Object value = parsed.get(key);
      if (value instanceof String && !String.isBlank((String) value)) {
        try {
          values.put(key, Id.valueOf((String) value));
        } catch (Exception invalidId) {
          continue;
        }
      }
    }
    Object description = parsed.get(INPUT_DESCRIPTION);
    if (
      description instanceof String && !String.isBlank((String) description)
    ) {
      values.put(INPUT_DESCRIPTION, (String) description);
    }
    return values;
  }

  /**
   * @description Decomposição da ocorrência pela fórmula aprovada, gerada uma única vez por
   * definição. `ESTIMATED` não tem fórmula: as porções ficam nulas em vez de zero inventado.
   */
  private static ALT_CLS_AmortizationSchedule.Occurrence formulaPortions(
    AXF_OBJ_ScheduleDefinition__c definition,
    Integer sequence,
    Map<Id, List<ALT_CLS_AmortizationSchedule.Occurrence>> formulas
  ) {
    if (definition.AXF_SDF_PKL_Method__c == METHOD_ESTIMATED) {
      return null;
    }
    List<ALT_CLS_AmortizationSchedule.Occurrence> occurrences = formulas.get(
      definition.Id
    );
    if (occurrences == null) {
      occurrences = ALT_CLS_ScheduleProjection.generateOccurrences(definition);
      formulas.put(definition.Id, occurrences);
    }
    if (occurrences.isEmpty()) {
      throw new ServiceException(
        'A fórmula aprovada não produziu o cronograma para a definição vigente.'
      );
    }
    Integer first = intOf(definition.AXF_SDF_NUM_FirstSequence__c);
    if (first == null || first < 1) {
      first = 1;
    }
    Integer index = sequence - first;
    if (index < 0 || index >= occurrences.size()) {
      throw new ServiceException(
        'A definição vigente não cobre a sequência ' + sequence + '.'
      );
    }
    return occurrences[index];
  }

  /**
   * @description Persiste os cursores e reconcilia o estado de execução sob o lock. A cobertura
   * gravada é a reconciliada pela produção e NUNCA fica abaixo do progresso já confirmado: um
   * cursor persistido que ainda não foi reconciliado (lacuna abaixo dele) não é rebaixado.
   */
  private static Long persistSuccess(
    AXF_OBJ_FinancialSchedule__c locked,
    Integer coverageSequence,
    Boolean advanceVersion
  ) {
    Long version = financialVersionOf(locked, advanceVersion);
    Database.update(
      new List<AXF_OBJ_FinancialSchedule__c>{
        new AXF_OBJ_FinancialSchedule__c(
          Id = locked.Id,
          AXF_FSC_NUM_CoverageSequence__c = coverageSequence,
          AXF_FSC_NUM_FinancialVersion__c = version,
          AXF_FSC_NUM_RetryCount__c = 0,
          AXF_FSC_DT_NextAttemptAt__c = null,
          AXF_FSC_TXT_LastErrorCode__c = null
        )
      },
      AccessLevel.SYSTEM_MODE
    );
    return version;
  }

  private static Long financialVersionOf(
    AXF_OBJ_FinancialSchedule__c row,
    Boolean advance
  ) {
    Long current = (row == null ||
      row.AXF_FSC_NUM_FinancialVersion__c == null)
      ? 0
      : row.AXF_FSC_NUM_FinancialVersion__c.longValue();
    // FinancialVersion avança em toda mudança de composição persistida (materialização é mudança
    // de composição persistida); uma passagem que não criou nada não a movimenta.
    return advance ? current + 1 : current;
  }

  /**
   * @description Releitura autorizada depois de uma colisão de chave única. Todas as identidades
   * do plano já existem com a chave CORRETA => replay, nada duplicado. Alguma delas existe sob
   * OUTRA identidade completa => CONFLICT, nunca sucesso arbitrário. Caso contrário, falha de DML
   * recuperável.
   *
   * Visível ao teste porque a colisão REAL exige uma linha que apareça entre a leitura autorizada e
   * a escrita — um entrelaçamento que não é produzível dentro de UMA transação de teste. O que o
   * teste injeta é o `DmlException` de uma colisão de chave única REAL; a classificação e a
   * reconciliação do cursor continuam sendo esta produção.
   */
  @TestVisible
  private static ReplenishmentResult recoverFromCollision(
    ReplenishmentRequest request,
    List<Integer> toCreate,
    ReplenishmentResult result,
    Integer trackingStart,
    DmlException failure
  ) {
    IdentitySnapshot snapshot = persistedIdentities(request.scheduleId);
    if (snapshot.truncated) {
      return terminalFail(
        result,
        OUTCOME_INVALID,
        'O cronograma tem mais identidades rastreadas do que o teto declarado: a releitura autorizada depois da colisão não é decidível.',
        ALT_CLS_ScheduleReplenishment.ERROR_SCALE_LIMIT
      );
    }
    Map<Integer, String> identities = snapshot.bySequence;
    Set<Integer> accounted = new Set<Integer>();
    for (Integer sequence : identities.keySet()) {
      if (sequence == null || sequence < trackingStart) {
        continue;
      }
      if (
        identities.get(sequence) ==
        ALT_CLS_ScheduleProjection.occurrenceKey(result.scheduleKey, sequence)
      ) {
        accounted.add(sequence);
      }
    }
    Boolean allPresent = true;
    Boolean conflict = false;
    for (Integer sequence : toCreate) {
      String existing = identities.get(sequence);
      String expected = ALT_CLS_ScheduleProjection.occurrenceKey(
        result.scheduleKey,
        sequence
      );
      if (existing == null) {
        allPresent = false;
        continue;
      }
      if (existing != expected) {
        conflict = true;
        continue;
      }
      accounted.add(sequence);
    }
    if (conflict) {
      return terminalFail(
        result,
        OUTCOME_CONFLICT,
        'A releitura autorizada encontrou uma identidade ocupada por outra ocorrência de identidade completa diferente; nada foi gravado.',
        ALT_CLS_ScheduleReplenishment.ERROR_IDENTITY
      );
    }
    if (!allPresent) {
      return replenishmentFail(
        result,
        OUTCOME_FAILED,
        'Não foi possível gravar a reposição: ' +
        sanitize(failure.getDmlType(0)),
        ALT_CLS_ScheduleReplenishment.ERROR_DML
      );
    }
    AXF_OBJ_FinancialSchedule__c current = readSchedule(request.scheduleId);
    if (current == null) {
      return replenishmentFail(
        result,
        OUTCOME_UNAVAILABLE,
        'O cronograma não está mais disponível após a releitura autorizada.',
        ALT_CLS_ScheduleReplenishment.ERROR_HOLDER_UNAVAILABLE
      );
    }
    Integer coverage = Math.max(
      ALT_CLS_ScheduleReplenishment.coverageAfter(trackingStart, accounted),
      intOf(current.AXF_FSC_NUM_CoverageSequence__c)
    );
    try {
      writing = true;
      result.financialVersion = persistSuccess(current, coverage, false);
    } catch (DmlException retryFailure) {
      return replenishmentFail(
        result,
        OUTCOME_FAILED,
        'A reconciliação dos cursores falhou depois da colisão de identidade.',
        ALT_CLS_ScheduleReplenishment.ERROR_DML
      );
    } finally {
      writing = false;
    }
    result.coverageSequence = coverage;
    result.replay = true;
    result.outcome = OUTCOME_REPLAY;
    result.message = 'As identidades elegíveis da janela já existiam com a sequência correta: nada foi duplicado e o cursor foi reconciliado pela produção.';
    return result;
  }

  /**
   * @description Rejeita uma leitura que não serve para gerar, com um código POR DESFECHO — o
   * estado persistido é a superfície acionável do operador, e colapsar ambiguidade, método sem
   * valor, leitura inválida e ausência de resultado no mesmo `PROJECTION_BLOCKED` deixaria o
   * operador sem saber o que corrigir. Divergência de revisão continua recuperável; todo o resto é
   * PERMANENTE e nunca queima orçamento de retry.
   */
  private static ReplenishmentResult rejectProjection(
    ALT_CLS_ScheduleProjection.ProjectionResult projection,
    ReplenishmentResult result
  ) {
    if (projection == null) {
      return terminalFail(
        result,
        OUTCOME_FAILED,
        'A leitura autorizada não devolveu resultado algum: não há o que materializar nem como decidir. Desfecho permanente.',
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_MISSING
      );
    }
    if (projection.outcome == ALT_CLS_ScheduleProjection.OUTCOME_OK) {
      return null;
    }
    if (projection.outcome == ALT_CLS_ScheduleProjection.OUTCOME_FORBIDDEN) {
      return terminalFail(
        result,
        OUTCOME_FORBIDDEN,
        'A leitura autorizada recusou a autoridade do titular. Provisione o acesso; repetir não resolve.',
        ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY
      );
    }
    if (projection.outcome == ALT_CLS_ScheduleProjection.OUTCOME_NOT_FOUND) {
      return replenishmentFail(
        result,
        OUTCOME_NOT_FOUND,
        'Cronograma não encontrado neste escopo.',
        null
      );
    }
    if (projection.outcome == ALT_CLS_ScheduleProjection.OUTCOME_STALE) {
      return replenishmentFail(
        result,
        OUTCOME_FAILED,
        'A revisão do cronograma mudou durante a leitura: a passagem será repetida com recuo limitado.',
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_STALE
      );
    }
    if (projection.outcome == ALT_CLS_ScheduleProjection.OUTCOME_AMBIGUOUS) {
      return terminalFail(
        result,
        OUTCOME_INVALID,
        'Há confirmações de referência conflitantes na mesma ordem econômica: a precedência é AMBÍGUA e o operador precisa resolvê-la explicitamente. Nada foi gravado.',
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_AMBIGUOUS
      );
    }
    if (projection.outcome == ALT_CLS_ScheduleProjection.OUTCOME_UNSUPPORTED) {
      return terminalFail(
        result,
        OUTCOME_INVALID,
        'A definição vigente não produz valor para a sequência: método sem valor. O operador precisa corrigir a definição. Nada foi gravado.',
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_UNSUPPORTED
      );
    }
    if (projection.outcome == ALT_CLS_ScheduleProjection.OUTCOME_INVALID) {
      return terminalFail(
        result,
        OUTCOME_INVALID,
        'A leitura recusou a faixa rastreada — definição efetiva ausente na sequência, ocorrência duplicada na mesma identidade, identidade que não corresponde à posição, ou ponteiro para definição/referência de outro cronograma. Nada foi gravado: ' +
        projection.message,
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_INVALID
      );
    }
    return terminalFail(
      result,
      OUTCOME_INVALID,
      'A leitura autorizada devolveu um desfecho fora do catálogo conhecido: ' +
      projection.outcome,
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_BLOCKED
    );
  }

  private static String replenishmentOutcome(
    ReplenishmentResult result,
    Integer createdCount,
    Boolean replayedIdentity
  ) {
    if (createdCount > 0) {
      return OUTCOME_GENERATED;
    }
    if (replayedIdentity) {
      return OUTCOME_REPLAY;
    }
    return result.termReached ? OUTCOME_COMPLETE : OUTCOME_NOOP;
  }

  private static String replenishmentMessage(ReplenishmentResult result) {
    if (result.outcome == OUTCOME_COMPLETE) {
      return 'Termo concluído: nenhuma ocorrência elegível falta dentro da janela e nada é criado além do termo.';
    }
    if (result.outcome == OUTCOME_NOOP) {
      return 'Nenhuma ocorrência elegível ausente dentro da janela.';
    }
    String message =
      result.createdCount +
      ' ocorrência(s) criada(s) na janela rolante; cobertura reconciliada em ' +
      result.coverageSequence +
      '.';
    if (result.evaluationCut) {
      message += ' Cobertura PARCIAL: o motor truncou por teto de avaliação e a passagem não consome tentativa por isso.';
    }
    if (result.moreWork) {
      message += ' Há ocorrência elegível além do limite desta transação: a continuação encadeia.';
    }
    return message;
  }

  private static ReplenishmentResult replenishmentFail(
    ReplenishmentResult result,
    String outcome,
    String message,
    String errorCode
  ) {
    result.outcome = outcome;
    result.message = message;
    result.errorCode = (errorCode == null)
      ? null
      : ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(errorCode);
    result.terminal = ALT_CLS_ScheduleReplenishment.isTerminal(
      result.errorCode
    );
    return result;
  }

  /**
   * @description Desfecho PERMANENTE: deixa o estado acionável registrado e NÃO consome
   * orçamento de retry nem agenda tentativa. O registro é operacional — uma única linha, antes de
   * qualquer efeito financeiro a reverter — e não pode derrubar a classificação já feita.
   */
  private static ReplenishmentResult terminalFail(
    ReplenishmentResult result,
    String outcome,
    String message,
    String errorCode
  ) {
    replenishmentFail(result, outcome, message, errorCode);
    if (result.scheduleId == null || result.errorCode == null) {
      return result;
    }
    try {
      AXF_OBJ_FinancialSchedule__c state = AXF_CLS_ScheduleReplenishmentStateWriter.read(
        result.scheduleId
      );
      if (state == null) {
        return result;
      }
      Boolean stateWritten = writeOperationalState(
        result.scheduleId,
        result.errorCode,
        intOf(state.AXF_FSC_NUM_RetryCount__c),
        null
      );
      result.statePersisted = stateWritten;
      result.stateWriteFailure = AXF_CLS_ScheduleReplenishmentStateWriter.failureReason();
      if (!stateWritten) {
        // Sem este rastro, uma gravação recusada deixaria o cronograma parecendo parado sem
        // motivo: o desfecho terminal existe, o estado acionável não, e ninguém saberia.
        result.message +=
          ' (O registro do estado acionável NÃO foi gravado: ' +
          AXF_CLS_ScheduleReplenishmentStateWriter.describeLastOutcome() +
          '. O cronograma segue no conjunto devido até o registro acontecer.)';
        System.debug(
          LoggingLevel.ERROR,
          'AXF103 reposicao: estado acionavel NAO persistido. ' +
            AXF_CLS_ScheduleReplenishmentStateWriter.describeLastOutcome() +
            ' codigo=' +
            result.errorCode
        );
      }
    } catch (Exception markingFailure) {
      // Estado acionável é registro operacional; a classificação do desfecho prevalece.
      result.message += ' (O registro do estado acionável não pôde ser gravado nesta transação.)';
      result.stateWriteFailure = AXF_CLS_ScheduleReplenishmentStateWriter.REASON_DML_REFUSED;
    }
    return result;
  }

  /**
   * @description Classificação de uma falha da leitura autorizada. Um desfecho TERMINAL é
   * permanente e imediato — registrar o estado acionável agora, sem consumir orçamento de retry;
   * um recuperável segue o recuo limitado. Sem esta distinção, um estouro numérico determinístico
   * da fórmula aprovada queimaria as três tentativas e viraria `RETRY_EXHAUSTED` por engano.
   */
  private static ReplenishmentResult classifyFailure(
    ReplenishmentResult result,
    String outcome,
    String message,
    String errorCode
  ) {
    if (ALT_CLS_ScheduleReplenishment.isTerminal(errorCode)) {
      return terminalFail(result, outcome, message, errorCode);
    }
    return replenishmentFail(result, outcome, message, errorCode);
  }

  private static String replenishmentErrorCode(Exception failure) {
    if (failure instanceof System.DmlException) {
      return ALT_CLS_ScheduleReplenishment.ERROR_DML;
    }
    if (failure instanceof System.QueryException) {
      return ALT_CLS_ScheduleReplenishment.ERROR_QUERY;
    }
    if (failure instanceof ALT_CLS_ScheduleCalendar.CalendarException) {
      return ALT_CLS_ScheduleReplenishment.ERROR_CALENDAR;
    }
    if (failure instanceof System.MathException) {
      // Estouro da fórmula aprovada: determinístico, permanente e imediato.
      return ALT_CLS_ScheduleReplenishment.ERROR_FORMULA;
    }
    return ALT_CLS_ScheduleReplenishment.ERROR_UNEXPECTED;
  }

  /** Registra um passo do caminho da reposição, para o teste provar a ORDEM dos locks. */
  private static void traceLockStep(String step) {
    if (lockTraceForTest != null) {
      lockTraceForTest.add(step);
    }
  }

  private static Long projectionRevisionOf(AXF_OBJ_FinancialSchedule__c row) {
    if (row == null || row.AXF_FSC_NUM_ProjectionRevision__c == null) {
      return 0;
    }
    return row.AXF_FSC_NUM_ProjectionRevision__c.longValue();
  }

  private static Integer firstSequenceOf(List<Integer> sequences) {
    Integer first;
    for (Integer sequence : sequences) {
      if (first == null || sequence < first) {
        first = sequence;
      }
    }
    return first;
  }

  private static Integer lastSequenceOf(List<Integer> sequences) {
    Integer last;
    for (Integer sequence : sequences) {
      if (last == null || sequence > last) {
        last = sequence;
      }
    }
    return last;
  }

  private static Integer intOf(Decimal value) {
    return (value == null) ? null : Integer.valueOf(value);
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
    Integer periodDays;
    Id bankAccountId;
    Id creditCardId;
    String description;
    Boolean generationEnabled = false;
    String streamKey;
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
    value.periodDays = input.periodDays;
    if (value.periodDays != null) {
      // AXF-155: exatamente uma periodicidade. Em dias não há âncora nem padrão mensal.
      if (input.periodMonths != null) {
        throw new ServiceException(
          'Informe a periodicidade em meses ou em dias, nunca as duas.'
        );
      }
      if (!PERIOD_DAYS.contains(value.periodDays)) {
        throw new ServiceException(
          'A periodicidade em dias deve ser 7 (semanal) ou 14 (quinzenal).'
        );
      }
      value.periodMonths = null;
    } else {
      value.periodMonths = (input.periodMonths == null)
        ? 1
        : input.periodMonths;
      if (value.periodMonths < 1) {
        throw new ServiceException(
          'Periodicidade deve ser de pelo menos 1 mês.'
        );
      }
      if (value.periodMonths > MAX_PERIOD_MONTHS) {
        throw new ServiceException(
          'Periodicidade deve estar entre 1 e ' + MAX_PERIOD_MONTHS + ' meses.'
        );
      }
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

    if (value.periodDays != null) {
      normalizeDayCalendar(input, value);
    } else {
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

    normalizeOrigin(input, value);

    // Identidade do cronograma: estável sob emenda de fórmula (principal, taxa e tarifas não
    // participam) e distinta por contrato, titular, direção, moeda, método, calendário e pelo
    // discriminador do fluxo. Um contrato admite vários cronogramas; dois contratos do mesmo
    // titular com o mesmo calendário não podem colidir.
    List<Object> keyParts = new List<Object>{
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
    };
    // AXF-155: partes novas entram SÓ quando presentes, para que a identidade de todo cronograma
    // mensal existente continue byte a byte a mesma (replay de criação inalterado).
    if (value.periodDays != null) {
      keyParts.addAll(new List<Object>{ 'periodDays', value.periodDays });
    }
    if (value.streamKey != null) {
      keyParts.addAll(new List<Object>{ 'stream', value.streamKey });
    }
    value.scheduleKey = AXF_CLS_IdentityFraming.key(keyParts);
    value.definitionKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ DEFINITION_TAG, value.scheduleKey, 1 }
    );
    value.referenceKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ REFERENCE_TAG, value.scheduleKey, 1, 'INITIAL' }
    );

    List<Object> payloadParts = new List<Object>{
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
    };
    if (value.periodDays != null) {
      payloadParts.addAll(new List<Object>{ 'periodDays', value.periodDays });
    }
    if (value.bankAccountId != null || value.creditCardId != null) {
      payloadParts.addAll(
        new List<Object>{ 'origin', value.bankAccountId, value.creditCardId }
      );
    }
    if (value.description != null) {
      payloadParts.addAll(new List<Object>{ 'description', value.description });
    }
    if (value.generationEnabled) {
      payloadParts.addAll(new List<Object>{ 'generationEnabled', true });
    }
    String canonical = AXF_CLS_IdentityFraming.frame(payloadParts);
    value.payloadHash = AXF_CLS_IdentityFraming.sha256Hex(canonical);
    value.operationKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        OPERATION_TAG,
        OPERATION_CREATE,
        value.scheduleKey,
        value.payloadHash
      }
    );
    Map<String, Object> canonicalInput = new Map<String, Object>{
      'tag' => PAYLOAD_TAG,
      'canonical' => canonical,
      'payloadHash' => value.payloadHash,
      'scheduleKey' => value.scheduleKey
    };
    // AXF-155: origem e descrição fazem parte da entrada canônica da definição, e é daqui que a
    // reposição as reaplica a cada ocorrência nova.
    if (value.bankAccountId != null) {
      canonicalInput.put(INPUT_BANK_ACCOUNT, value.bankAccountId);
    }
    if (value.creditCardId != null) {
      canonicalInput.put(INPUT_CREDIT_CARD, value.creditCardId);
    }
    if (value.description != null) {
      canonicalInput.put(INPUT_DESCRIPTION, value.description);
    }
    value.canonicalJson = JSON.serialize(canonicalInput);
    return value;
  }

  /**
   * @description AXF-155 — calendário em dias: sem âncora. O primeiro vencimento vem informado ou
   * é derivado da parcela corrente recuando `periodDays` por sequência; a âncora persistida (campo
   * obrigatório da definição) é apenas o dia do primeiro vencimento e não participa do cálculo.
   */
  private static void normalizeDayCalendar(
    CreateInput input,
    Normalized value
  ) {
    if (input.firstDueDate != null) {
      if (
        input.trackingDueDate != null &&
        ALT_CLS_ScheduleCalendar.nominalDueDateByDays(
          input.firstDueDate,
          value.firstSequence,
          value.periodDays,
          value.trackingStartSequence
        ) != input.trackingDueDate
      ) {
        throw new ServiceException(
          'O vencimento da parcela corrente informado não é coerente com o primeiro vencimento e a periodicidade em dias.'
        );
      }
      value.firstDueDate = input.firstDueDate;
    } else if (input.trackingDueDate != null) {
      value.firstDueDate = ALT_CLS_ScheduleCalendar.shiftDays(
        input.trackingDueDate,
        -(value.trackingStartSequence - value.firstSequence) * value.periodDays
      );
    }
    if (value.firstDueDate != null) {
      value.anchorDay = value.firstDueDate.day();
    }
  }

  /**
   * @description AXF-155 — origem (uma só: conta/carteira OU cartão), descrição, geração e chave de
   * fluxo normalizadas. A pertença da origem ao titular é conferida sob o lock, antes da escrita.
   */
  private static void normalizeOrigin(CreateInput input, Normalized value) {
    if (input.bankAccountId != null && input.creditCardId != null) {
      throw new ServiceException(
        'Informe uma única origem: conta corrente, carteira ou cartão.'
      );
    }
    value.bankAccountId = input.bankAccountId;
    value.creditCardId = input.creditCardId;
    value.description = blankToNull(input.description);
    if (
      value.description != null &&
      value.description.length() > MAX_DESCRIPTION_LENGTH
    ) {
      throw new ServiceException(
        'A descrição excede ' + MAX_DESCRIPTION_LENGTH + ' caracteres.'
      );
    }
    value.generationEnabled = input.generationEnabled == true;
    value.streamKey = blankToNull(input.streamKey);
    if (
      value.streamKey != null &&
      value.streamKey.length() > MAX_STREAM_KEY_LENGTH
    ) {
      throw new ServiceException(
        'A chave de fluxo excede ' + MAX_STREAM_KEY_LENGTH + ' caracteres.'
      );
    }
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
    Date today = today();
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
        normalized.periodDays,
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
        : normalized.method,
      // AXF-155: origem e descrição da recorrência em toda ocorrência materializada.
      AXF_FTX_LKP_BankAccount__c = normalized.bankAccountId,
      AXF_FTX_LKP_CreditCard__c = normalized.creditCardId,
      AXF_FTX_TXT_Description__c = normalized.description
    );
  }

  /**
   * @description A origem informada existe e pertence ao titular? Sem origem, nada a conferir.
   * Leitura do caminho privilegiado declarado: a autoridade do titular já foi conferida.
   */
  private static Boolean originBelongsTo(Normalized normalized, Id holderId) {
    if (normalized.bankAccountId != null) {
      List<AXF_OBJ_BankAccount__c> accounts = [
        SELECT Id
        FROM AXF_OBJ_BankAccount__c
        WHERE
          Id = :normalized.bankAccountId
          AND AXF_BA_LKP_Account__c = :holderId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      return accounts.size() == 1;
    }
    if (normalized.creditCardId != null) {
      List<AXF_OBJ_CreditCard__c> cards = [
        SELECT Id
        FROM AXF_OBJ_CreditCard__c
        WHERE
          Id = :normalized.creditCardId
          AND AXF_CC_LKP_Account__c = :holderId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      return cards.size() == 1;
    }
    return true;
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

  // --- comandos de mudança: EDIT de valor e TERMINATE (AXF-155) -----------

  public static final String OPERATION_EDIT = 'EDIT';
  public static final String OPERATION_TERMINATE = 'TERMINATE';
  public static final String STATE_ENDED = 'ENDED';
  public static final String OUTCOME_UPDATED = 'UPDATED';
  public static final String OUTCOME_TERMINATED = 'TERMINATED';
  public static final String OUTCOME_UNSUPPORTED = 'UNSUPPORTED';
  public static final String CHANGE_TAG = 'axf155-change-v1';
  public static final String MANUAL_REFERENCE_TAG = 'axf155-srf-manual-v1';
  public static final String WITHDRAW_REFERENCE_TAG = 'axf155-srf-withdraw-v1';
  /** Política de proteção registrada no recibo: nada realizado/conciliado/congelado muda. */
  public static final String PROTECTION_POLICY = 'ALLOCATED_CONFIRMED_FROZEN_PROTECTED';
  public static final Integer MAX_OPERATION_KEY_LENGTH = 120;
  /** Teto de ocorrências persistidas lidas por comando de mudança. */
  public static final Integer MAX_CHANGE_ROWS = 2000;
  private static final String KIND_MANUAL = 'MANUAL';
  private static final String KIND_REALIZATION = 'REALIZATION';
  private static final String KIND_COMPENSATION = 'COMPENSATION';
  private static final String STATE_CANCELLED = 'CANCELLED';
  private static final String STATUS_CONFIRMED = 'CONFIRMED';

  /**
   * Comando de mudança de um cronograma (contrato AXF-103 EDIT/TERMINATE). `operationKey` é a
   * identidade de idempotência do chamador; `expectedVersion` é a versão otimista da raiz.
   */
  public class ChangeInput {
    public Id scheduleId;
    public String operationKey;
    public Long expectedVersion;
    /** EDIT: novo valor de referência, a partir da primeira ocorrência futura não realizada. */
    public Decimal amount;
    /** TERMINATE: data efetiva; vencimentos estritamente posteriores são cancelados. */
    public Date terminationDate;
    public String reason;
  }

  /** Resultado autorizado do comando de mudança, devolvido também no replay. */
  public class ChangeResult {
    public String outcome;
    public String message;
    public Id scheduleId;
    public Id changeId;
    public String changeKey;
    public Id referenceId;
    public Long revision;
    public Long version;
    public Integer fromSequence;
    public Integer updatedCount = 0;
    public Integer cancelledCount = 0;
    public Integer protectedCount = 0;
    public Decimal amount;
    public Date terminationDate;
    public Boolean replay = false;
  }

  /**
   * @description EDIT de valor com escopo FROM_SEQUENCE: nova referência MANUAL efetiva na
   * primeira ocorrência futura não realizada, recibo EDIT e atualização da base corrente das
   * ocorrências persistidas elegíveis. Realizadas, conciliadas e congeladas ficam intocadas.
   */
  public static ChangeResult editAmount(ChangeInput input) {
    return applyChange(OPERATION_EDIT, input);
  }

  /**
   * @description TERMINATE: fronteira efetiva, raiz ENDED, ocorrências elegíveis com vencimento
   * estritamente posterior à data marcadas CANCELLED e recibo TERMINATE. Sem reativação.
   */
  public static ChangeResult terminateSchedule(ChangeInput input) {
    return applyChange(OPERATION_TERMINATE, input);
  }

  private static ChangeResult applyChange(String operation, ChangeInput input) {
    ChangeResult result = new ChangeResult();
    lastRunLockedHolder = false;
    String invalid = changeInputError(operation, input);
    if (invalid != null) {
      return changeFail(result, OUTCOME_INVALID, invalid);
    }
    result.scheduleId = input.scheduleId;
    AXF_OBJ_FinancialSchedule__c root = readSchedule(input.scheduleId);
    if (root == null) {
      return changeFail(
        result,
        OUTCOME_NOT_FOUND,
        'Cronograma não encontrado neste escopo.'
      );
    }
    Id holderId = root.AXF_FSC_LKP_Account__c;
    if (!isAuthorized(holderId)) {
      return changeFail(
        result,
        OUTCOME_FORBIDDEN,
        'Você não tem acesso a esta entidade titular.'
      );
    }
    if (!canChangeSchedules()) {
      return changeFail(
        result,
        OUTCOME_FORBIDDEN,
        'Você não tem permissão para alterar cronogramas financeiros.'
      );
    }
    Decimal amount = (operation == OPERATION_EDIT)
      ? input.amount.setScale(MONEY_SCALE)
      : null;
    String payloadHash = changePayloadHash(operation, root, input, amount);
    String operationKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        OPERATION_TAG,
        operation,
        root.AXF_FSC_EXI_ScheduleKey__c,
        input.operationKey.trim()
      }
    );
    result.changeKey = operationKey;

    // Replay autorizado: identidade de operação ANTES da checagem de versão.
    ChangeResult replay = changeReplayOrConflict(
      operation,
      operationKey,
      payloadHash,
      result
    );
    if (replay != null) {
      return replay;
    }
    ChangeResult rejected = changePreconditions(operation, root, input, result);
    if (rejected != null) {
      return rejected;
    }

    // Serialização holder-first, releitura sob o lock e rechecagem de replay e de versão.
    lastRunLockedHolder = true;
    if (!lockHolder(holderId, AccessLevel.USER_MODE)) {
      return changeFail(
        result,
        OUTCOME_UNAVAILABLE,
        'O titular não está disponível para escrita neste momento.'
      );
    }
    AXF_OBJ_FinancialSchedule__c locked = readSchedule(input.scheduleId);
    if (locked == null || locked.AXF_FSC_LKP_Account__c != holderId) {
      return changeFail(
        result,
        OUTCOME_UNAVAILABLE,
        'O cronograma não está mais disponível sob o lock do titular; nada foi gravado.'
      );
    }
    replay = changeReplayOrConflict(
      operation,
      operationKey,
      payloadHash,
      result
    );
    if (replay != null) {
      return replay;
    }
    rejected = changePreconditions(operation, locked, input, result);
    if (rejected != null) {
      return rejected;
    }

    Savepoint checkpoint = Database.setSavepoint();
    try {
      writing = true;
      ChangeContext context = new ChangeContext();
      context.root = locked;
      context.input = input;
      context.operationKey = operationKey;
      context.payloadHash = payloadHash;
      context.amount = amount;
      context.revision = projectionRevisionOf(locked) + 1;
      context.version = versionOf(locked) + 1;
      context.rows = changeRows(locked.Id);
      context.allocated = allocatedTargets(context.rows);
      if (operation == OPERATION_EDIT) {
        applyEdit(context, result);
      } else {
        applyTerminate(context, result);
      }
    } catch (DmlException failure) {
      Database.rollback(checkpoint);
      ChangeResult recovered = changeReplayOrConflict(
        operation,
        operationKey,
        payloadHash,
        new ChangeResult()
      );
      if (recovered != null) {
        return recovered;
      }
      return changeFail(
        result,
        OUTCOME_UNAVAILABLE,
        'Não foi possível gravar a alteração: ' +
        sanitize(failure.getDmlType(0))
      );
    } catch (ServiceException failure) {
      Database.rollback(checkpoint);
      return changeFail(result, OUTCOME_INVALID, failure.getMessage());
    } finally {
      writing = false;
    }
    return result;
  }

  /** Estado compartilhado de UM comando de mudança sob o lock. */
  private class ChangeContext {
    AXF_OBJ_FinancialSchedule__c root;
    ChangeInput input;
    String operationKey;
    String payloadHash;
    Decimal amount;
    Long revision;
    Long version;
    List<AXF_OBJ_FinancialTransaction__c> rows;
    Set<Id> allocated;
  }

  private static void applyEdit(ChangeContext context, ChangeResult result) {
    Date today = today();
    Integer fromSequence;
    Integer highest = 0;
    List<AXF_OBJ_FinancialTransaction__c> eligible = new List<AXF_OBJ_FinancialTransaction__c>();
    List<Integer> protectedSequences = new List<Integer>();
    for (AXF_OBJ_FinancialTransaction__c row : context.rows) {
      Integer sequence = row.AXF_FTX_NUM_Sequence__c.intValue();
      highest = Math.max(highest, sequence);
      if (row.AXF_FTX_PKL_ScheduleState__c == STATE_CANCELLED) {
        continue;
      }
      Boolean future =
        row.AXF_FTX_DAT_DueDate__c != null &&
        row.AXF_FTX_DAT_DueDate__c >= today;
      if (!future) {
        continue;
      }
      // Toda ocorrência futura protegida é registrada, inclusive as anteriores à primeira
      // ocorrência mutável (conciliadas antecipadamente).
      if (!isMutable(row, context.allocated)) {
        protectedSequences.add(sequence);
        continue;
      }
      if (fromSequence == null) {
        fromSequence = sequence;
      }
      eligible.add(row);
    }
    if (fromSequence == null) {
      // Nenhuma ocorrência persistida elegível no futuro: vale a partir da próxima virtual.
      fromSequence = Math.max(
        highest + 1,
        intOf(context.root.AXF_FSC_NUM_TrackingStartSequence__c)
      );
    }

    Decimal previousAmount = activeReferenceAmount(context.root);
    List<AXF_OBJ_ScheduleReference__c> inserts = withdrawnReferences(
      context.root.Id,
      fromSequence
    );
    AXF_OBJ_ScheduleReference__c manual = new AXF_OBJ_ScheduleReference__c(
      AXF_SRF_EXI_ReferenceKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{
          MANUAL_REFERENCE_TAG,
          context.root.AXF_FSC_EXI_ScheduleKey__c,
          context.operationKey
        }
      ),
      AXF_SRF_LKP_Schedule__c = context.root.Id,
      AXF_SRF_NUM_EconomicSequence__c = fromSequence,
      AXF_SRF_NUM_EffectiveSequence__c = fromSequence,
      AXF_SRF_NUM_RecurringAmount__c = context.amount,
      AXF_SRF_PKL_Kind__c = KIND_MANUAL,
      AXF_SRF_LKP_Predecessor__c = context.root.AXF_FSC_LKP_ActiveReference__c,
      AXF_SRF_DT_ConfirmedAt__c = System.now(),
      AXF_SRF_LKP_ConfirmedBy__c = UserInfo.getUserId(),
      AXF_SRF_TAL_Reason__c = blankToNull(context.input.reason)
    );
    inserts.add(manual);
    Database.insert(inserts, AccessLevel.SYSTEM_MODE);

    List<AXF_OBJ_FinancialTransaction__c> updates = new List<AXF_OBJ_FinancialTransaction__c>();
    for (AXF_OBJ_FinancialTransaction__c row : eligible) {
      updates.add(
        new AXF_OBJ_FinancialTransaction__c(
          Id = row.Id,
          AXF_FTX_NUM_CurrentBasis__c = context.amount,
          // Linha futura, não alocada, não CONFIRMED e sem base congelada: a previsão exibida
          // por extratos, lançamentos, sugestões e exportações acompanha o novo valor.
          AXF_FTX_NUM_Magnitude__c = context.amount,
          AXF_FTX_LKP_ScheduleReference__c = manual.Id,
          AXF_FTX_NUM_ProjectionRevision__c = context.revision,
          AXF_FTX_NUM_Version__c = nextRowVersion(row)
        )
      );
    }
    if (!updates.isEmpty()) {
      Database.update(updates, AccessLevel.SYSTEM_MODE);
    }
    persistChangeRoot(context, manual.Id, null);

    result.outcome = OUTCOME_UPDATED;
    result.referenceId = manual.Id;
    result.fromSequence = fromSequence;
    result.updatedCount = updates.size();
    result.protectedCount = protectedSequences.size();
    result.amount = context.amount;
    result.revision = context.revision;
    result.version = context.version;
    result.message =
      'Valor atualizado a partir da sequência ' +
      fromSequence +
      ': ' +
      updates.size() +
      ' ocorrência(s) alterada(s), ' +
      protectedSequences.size() +
      ' protegida(s).';
    insertChangeReceipt(
      context,
      OPERATION_EDIT,
      fromSequence,
      new Map<String, Object>{ 'amount' => context.amount },
      new Map<String, Object>{ 'amount' => previousAmount },
      protectedSequences,
      result
    );
  }

  private static void applyTerminate(
    ChangeContext context,
    ChangeResult result
  ) {
    Date boundary = context.input.terminationDate;
    Integer fromSequence;
    Integer highest = 0;
    List<AXF_OBJ_FinancialTransaction__c> cancellations = new List<AXF_OBJ_FinancialTransaction__c>();
    List<Integer> protectedSequences = new List<Integer>();
    for (AXF_OBJ_FinancialTransaction__c row : context.rows) {
      Integer sequence = row.AXF_FTX_NUM_Sequence__c.intValue();
      highest = Math.max(highest, sequence);
      // Fronteira aprovada: vencimento ESTRITAMENTE posterior à data efetiva.
      if (
        row.AXF_FTX_DAT_DueDate__c == null ||
        row.AXF_FTX_DAT_DueDate__c <= boundary
      ) {
        continue;
      }
      if (fromSequence == null) {
        fromSequence = sequence;
      }
      if (row.AXF_FTX_PKL_ScheduleState__c == STATE_CANCELLED) {
        continue;
      }
      if (!isMutable(row, context.allocated)) {
        protectedSequences.add(sequence);
        continue;
      }
      cancellations.add(
        new AXF_OBJ_FinancialTransaction__c(
          Id = row.Id,
          AXF_FTX_PKL_ScheduleState__c = STATE_CANCELLED,
          AXF_FTX_NUM_ProjectionRevision__c = context.revision,
          AXF_FTX_NUM_Version__c = nextRowVersion(row)
        )
      );
    }
    if (fromSequence == null) {
      fromSequence = Math.max(
        highest + 1,
        intOf(context.root.AXF_FSC_NUM_TrackingStartSequence__c)
      );
    }
    if (!cancellations.isEmpty()) {
      Database.update(cancellations, AccessLevel.SYSTEM_MODE);
    }
    persistChangeRoot(context, null, boundary);

    result.outcome = OUTCOME_TERMINATED;
    result.fromSequence = fromSequence;
    result.cancelledCount = cancellations.size();
    result.protectedCount = protectedSequences.size();
    result.terminationDate = boundary;
    result.revision = context.revision;
    result.version = context.version;
    result.message =
      'Cronograma encerrado em ' +
      String.valueOf(boundary) +
      ': ' +
      cancellations.size() +
      ' ocorrência(s) cancelada(s), ' +
      protectedSequences.size() +
      ' protegida(s).';
    insertChangeReceipt(
      context,
      OPERATION_TERMINATE,
      fromSequence,
      new Map<String, Object>{
        'terminationDate' => String.valueOf(boundary),
        'protectionPolicy' => PROTECTION_POLICY
      },
      new Map<String, Object>{
        'state' => context.root.AXF_FSC_PKL_State__c,
        'terminationDate' => context.root.AXF_FSC_DAT_TerminationDate__c == null
          ? null
          : String.valueOf(context.root.AXF_FSC_DAT_TerminationDate__c)
      },
      protectedSequences,
      result
    );
  }

  /**
   * @description Ocorrência que o comando pode alterar: não alocada (nenhuma alocação a
   * referencia, nem revertida — a guarda AXF-25 congela a linha referenciada), não CONFIRMED e
   * sem base congelada.
   */
  private static Boolean isMutable(
    AXF_OBJ_FinancialTransaction__c row,
    Set<Id> allocated
  ) {
    return !allocated.contains(row.Id) &&
      row.AXF_FTX_PKL_Status__c != STATUS_CONFIRMED &&
      row.AXF_FTX_BOL_BasisFrozen__c != true;
  }

  /**
   * @description Referências ativas retiradas pela nova referência manual: a da MESMA ordem
   * econômica (para a precedência nunca ficar ambígua) e as manuais/iniciais posteriores (uma
   * edição mais recente do usuário prevalece sobre as dele próprias). Referências de realização
   * posteriores são evidência AXF-104 e permanecem.
   */
  private static List<AXF_OBJ_ScheduleReference__c> withdrawnReferences(
    Id scheduleId,
    Integer fromSequence
  ) {
    List<AXF_OBJ_ScheduleReference__c> references = [
      SELECT
        Id,
        AXF_SRF_PKL_Kind__c,
        AXF_SRF_NUM_EconomicSequence__c,
        AXF_SRF_NUM_EffectiveSequence__c,
        AXF_SRF_LKP_Compensates__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE AXF_SRF_LKP_Schedule__c = :scheduleId
      WITH SYSTEM_MODE
      ORDER BY AXF_SRF_NUM_EconomicSequence__c ASC, Id ASC
    ];
    Set<Id> compensated = new Set<Id>();
    for (AXF_OBJ_ScheduleReference__c reference : references) {
      if (
        reference.AXF_SRF_PKL_Kind__c == KIND_COMPENSATION &&
        reference.AXF_SRF_LKP_Compensates__c != null
      ) {
        compensated.add(reference.AXF_SRF_LKP_Compensates__c);
      }
    }
    List<AXF_OBJ_ScheduleReference__c> withdrawals = new List<AXF_OBJ_ScheduleReference__c>();
    for (AXF_OBJ_ScheduleReference__c reference : references) {
      if (
        reference.AXF_SRF_PKL_Kind__c == KIND_COMPENSATION ||
        compensated.contains(reference.Id)
      ) {
        continue;
      }
      Integer economic = (reference.AXF_SRF_NUM_EconomicSequence__c == null)
        ? 0
        : reference.AXF_SRF_NUM_EconomicSequence__c.intValue();
      Boolean sameOrder = economic == fromSequence;
      Boolean laterOwnEdit =
        economic > fromSequence &&
        reference.AXF_SRF_PKL_Kind__c != KIND_REALIZATION;
      if (!sameOrder && !laterOwnEdit) {
        continue;
      }
      withdrawals.add(
        new AXF_OBJ_ScheduleReference__c(
          AXF_SRF_EXI_ReferenceKey__c = AXF_CLS_IdentityFraming.key(
            new List<Object>{ WITHDRAW_REFERENCE_TAG, reference.Id }
          ),
          AXF_SRF_LKP_Schedule__c = scheduleId,
          AXF_SRF_NUM_EconomicSequence__c = reference.AXF_SRF_NUM_EconomicSequence__c,
          AXF_SRF_NUM_EffectiveSequence__c = reference.AXF_SRF_NUM_EffectiveSequence__c,
          AXF_SRF_NUM_RecurringAmount__c = 0,
          AXF_SRF_PKL_Kind__c = KIND_COMPENSATION,
          AXF_SRF_LKP_Compensates__c = reference.Id,
          AXF_SRF_DT_ConfirmedAt__c = System.now(),
          AXF_SRF_LKP_ConfirmedBy__c = UserInfo.getUserId(),
          AXF_SRF_TAL_Reason__c = 'Substituída por edição manual do valor (AXF-155).'
        )
      );
    }
    return withdrawals;
  }

  private static Decimal activeReferenceAmount(
    AXF_OBJ_FinancialSchedule__c root
  ) {
    if (root.AXF_FSC_LKP_ActiveReference__c == null) {
      return null;
    }
    List<AXF_OBJ_ScheduleReference__c> rows = [
      SELECT AXF_SRF_NUM_RecurringAmount__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE Id = :root.AXF_FSC_LKP_ActiveReference__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].AXF_SRF_NUM_RecurringAmount__c;
  }

  /**
   * @description Avança revisão solicitada/aplicada, versão financeira e versão otimista da raiz
   * atomicamente com a mudança; o EDIT reposiciona a referência vigente e o TERMINATE grava a
   * fronteira e encerra a raiz.
   */
  private static void persistChangeRoot(
    ChangeContext context,
    Id activeReference,
    Date terminationDate
  ) {
    AXF_OBJ_FinancialSchedule__c revision = new AXF_OBJ_FinancialSchedule__c(
      Id = context.root.Id,
      AXF_FSC_NUM_ProjectionRevision__c = context.revision,
      AXF_FSC_NUM_AppliedRevision__c = context.revision,
      AXF_FSC_NUM_FinancialVersion__c = financialVersionOf(context.root, true),
      AXF_FSC_NUM_Version__c = context.version
    );
    if (activeReference != null) {
      revision.AXF_FSC_LKP_ActiveReference__c = activeReference;
    }
    if (terminationDate != null) {
      revision.AXF_FSC_DAT_TerminationDate__c = terminationDate;
      revision.AXF_FSC_PKL_State__c = STATE_ENDED;
    }
    Database.update(
      new List<AXF_OBJ_FinancialSchedule__c>{ revision },
      AccessLevel.SYSTEM_MODE
    );
  }

  private static void insertChangeReceipt(
    ChangeContext context,
    String operation,
    Integer fromSequence,
    Map<String, Object> patch,
    Map<String, Object> priorValues,
    List<Integer> protectedSequences,
    ChangeResult result
  ) {
    result.scheduleId = context.root.Id;
    result.changeKey = context.operationKey;
    // O Id do próprio recibo não participa do ResultJson: um recibo é imutável.
    AXF_OBJ_ScheduleChange__c receipt = new AXF_OBJ_ScheduleChange__c(
      AXF_SCH_EXI_OperationKey__c = context.operationKey,
      AXF_SCH_TXT_PayloadHash__c = context.payloadHash,
      AXF_SCH_LKP_Schedule__c = context.root.Id,
      AXF_SCH_PKL_Operation__c = operation,
      AXF_SCH_NUM_Revision__c = context.revision,
      AXF_SCH_PKL_Scope__c = SCOPE_FROM_SEQUENCE,
      AXF_SCH_NUM_FromSequence__c = fromSequence,
      AXF_SCH_BOL_IncludeManualOverrides__c = false,
      AXF_SCH_TAL_FieldPatchJson__c = JSON.serialize(patch),
      AXF_SCH_TAL_PriorValuesJson__c = JSON.serialize(priorValues),
      AXF_SCH_TAL_ProtectedRangesJson__c = JSON.serialize(protectedSequences),
      AXF_SCH_TAL_ResultJson__c = JSON.serialize(result),
      AXF_SCH_LKP_Actor__c = UserInfo.getUserId(),
      AXF_SCH_DT_CommittedAt__c = System.now(),
      AXF_SCH_TAL_Reason__c = blankToNull(context.input.reason)
    );
    Database.insert(
      new List<AXF_OBJ_ScheduleChange__c>{ receipt },
      AccessLevel.SYSTEM_MODE
    );
    result.changeId = receipt.Id;
  }

  /** @description Ocorrências persistidas do cronograma, em ordem de sequência. */
  private static List<AXF_OBJ_FinancialTransaction__c> changeRows(
    Id scheduleId
  ) {
    Integer probe = MAX_CHANGE_ROWS + 1;
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT
        Id,
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_BOL_BasisFrozen__c,
        AXF_FTX_PKL_ScheduleState__c,
        AXF_FTX_NUM_Version__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c != NULL
      WITH SYSTEM_MODE
      ORDER BY AXF_FTX_NUM_Sequence__c ASC
      LIMIT :probe
    ];
    if (rows.size() > MAX_CHANGE_ROWS) {
      throw new ServiceException(
        'O cronograma tem mais de ' +
          MAX_CHANGE_ROWS +
          ' ocorrências persistidas; a alteração não é decidível nesta transação.'
      );
    }
    return rows;
  }

  /** @description Ocorrências referenciadas por qualquer alocação (inclusive revertida). */
  private static Set<Id> allocatedTargets(
    List<AXF_OBJ_FinancialTransaction__c> rows
  ) {
    Set<Id> ids = new Map<Id, AXF_OBJ_FinancialTransaction__c>(rows).keySet();
    Set<Id> allocated = new Set<Id>();
    if (ids.isEmpty()) {
      return allocated;
    }
    for (AXF_OBJ_ReconciliationAllocation__c allocation : [
      SELECT AXF_RA_LKP_FinancialTransaction__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE AXF_RA_LKP_FinancialTransaction__c IN :ids
      WITH SYSTEM_MODE
    ]) {
      allocated.add(allocation.AXF_RA_LKP_FinancialTransaction__c);
    }
    return allocated;
  }

  private static Decimal nextRowVersion(AXF_OBJ_FinancialTransaction__c row) {
    return (row.AXF_FTX_NUM_Version__c == null)
      ? 1
      : row.AXF_FTX_NUM_Version__c + 1;
  }

  private static Long versionOf(AXF_OBJ_FinancialSchedule__c row) {
    return (row == null ||
      row.AXF_FSC_NUM_Version__c == null)
      ? 0
      : row.AXF_FSC_NUM_Version__c.longValue();
  }

  /** Data de hoje sobreposta em teste; a mesma data serve à janela e aos comandos. */
  @TestVisible
  private static Date todayOverride;

  /** @description Hoje, para a janela inicial e os comandos de mudança (teste pode fixar). */
  public static Date today() {
    return todayOverride == null ? Date.today() : todayOverride;
  }

  /** @description Permissão de alterar cronogramas: criação e edição da raiz (Gestor). */
  public static Boolean canChangeSchedules() {
    Schema.DescribeSObjectResult describe = AXF_OBJ_FinancialSchedule__c.SObjectType.getDescribe();
    return describe.isCreateable() && describe.isUpdateable();
  }

  private static String changeInputError(String operation, ChangeInput input) {
    if (input == null || input.scheduleId == null) {
      return 'Cronograma é obrigatório.';
    }
    if (
      String.isBlank(input.operationKey) ||
      input.operationKey.trim().length() > MAX_OPERATION_KEY_LENGTH
    ) {
      return 'A chave de operação é obrigatória e tem até ' +
        MAX_OPERATION_KEY_LENGTH +
        ' caracteres.';
    }
    if (input.expectedVersion == null || input.expectedVersion < 0) {
      return 'A versão esperada do cronograma é obrigatória.';
    }
    if (input.reason != null && input.reason.length() > MAX_TAL_LENGTH) {
      return 'Justificativa excede o limite de ' +
        MAX_TAL_LENGTH +
        ' caracteres do campo de texto longo.';
    }
    if (operation == OPERATION_EDIT) {
      if (
        input.amount == null ||
        input.amount <= 0 ||
        input.amount > MAX_AMOUNT ||
        input.amount != input.amount.setScale(MONEY_SCALE)
      ) {
        return 'O novo valor deve ser positivo, com até duas casas decimais e dentro do limite efetivo de magnitude.';
      }
    } else if (input.terminationDate == null) {
      return 'A data de encerramento é obrigatória.';
    }
    return null;
  }

  /**
   * @description Pré-condições revalidadas antes e depois do lock: cronograma ativo (encerrado não
   * é alterado nem reativado), versão otimista e, no EDIT, método estimado — um método calculado
   * exige emenda de parâmetros aprovada, não um valor manual.
   */
  private static ChangeResult changePreconditions(
    String operation,
    AXF_OBJ_FinancialSchedule__c root,
    ChangeInput input,
    ChangeResult result
  ) {
    if (root.AXF_FSC_PKL_State__c != STATE_ACTIVE) {
      return changeFail(
        result,
        OUTCOME_CONFLICT,
        'O cronograma não está ativo: um cronograma encerrado não é alterado nem reativado.'
      );
    }
    if (versionOf(root) != input.expectedVersion) {
      return changeFail(
        result,
        OUTCOME_CONFLICT,
        'O cronograma mudou desde a leitura; recarregue antes de alterar.'
      );
    }
    if (operation == OPERATION_EDIT) {
      List<AXF_OBJ_ScheduleDefinition__c> definitions = [
        SELECT AXF_SDF_PKL_Method__c
        FROM AXF_OBJ_ScheduleDefinition__c
        WHERE Id = :root.AXF_FSC_LKP_ActiveDefinition__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (
        definitions.isEmpty() ||
        definitions[0].AXF_SDF_PKL_Method__c != METHOD_ESTIMATED
      ) {
        return changeFail(
          result,
          OUTCOME_UNSUPPORTED,
          'Alterar o valor de um cronograma calculado exige uma emenda de parâmetros aprovada.'
        );
      }
    }
    return null;
  }

  /** @description Hash do payload canônico versionado do comando de mudança. */
  private static String changePayloadHash(
    String operation,
    AXF_OBJ_FinancialSchedule__c root,
    ChangeInput input,
    Decimal amount
  ) {
    return AXF_CLS_IdentityFraming.sha256Hex(
      AXF_CLS_IdentityFraming.frame(
        new List<Object>{
          CHANGE_TAG,
          operation,
          root.Id,
          root.AXF_FSC_EXI_ScheduleKey__c,
          root.AXF_FSC_LKP_Account__c,
          input.expectedVersion,
          amount,
          input.terminationDate,
          PROTECTION_POLICY,
          blankToNull(input.reason),
          UserInfo.getUserId()
        }
      )
    );
  }

  /**
   * @description Recibo já confirmado para a identidade de operação: payload equivalente devolve o
   * resultado autorizado original; payload diferente é CONFLICT.
   */
  private static ChangeResult changeReplayOrConflict(
    String operation,
    String operationKey,
    String payloadHash,
    ChangeResult result
  ) {
    List<AXF_OBJ_ScheduleChange__c> receipts = [
      SELECT
        Id,
        AXF_SCH_TXT_PayloadHash__c,
        AXF_SCH_TAL_ResultJson__c,
        AXF_SCH_LKP_Schedule__c
      FROM AXF_OBJ_ScheduleChange__c
      WHERE
        AXF_SCH_EXI_OperationKey__c = :operationKey
        AND AXF_SCH_PKL_Operation__c = :operation
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (receipts.isEmpty()) {
      return null;
    }
    AXF_OBJ_ScheduleChange__c receipt = receipts[0];
    if (receipt.AXF_SCH_TXT_PayloadHash__c != payloadHash) {
      return changeFail(
        result,
        OUTCOME_CONFLICT,
        'A identidade de operação já está confirmada com um payload diferente.'
      );
    }
    ChangeResult stored;
    try {
      stored = String.isBlank(receipt.AXF_SCH_TAL_ResultJson__c)
        ? null
        : (ChangeResult) JSON.deserialize(
            receipt.AXF_SCH_TAL_ResultJson__c,
            ChangeResult.class
          );
    } catch (Exception malformed) {
      stored = null;
    }
    if (stored == null) {
      return changeFail(
        result,
        OUTCOME_CONFLICT,
        'O resultado autorizado registrado no recibo não pôde ser lido; o reenvio é recusado.'
      );
    }
    stored.scheduleId = receipt.AXF_SCH_LKP_Schedule__c;
    stored.changeId = receipt.Id;
    stored.changeKey = operationKey;
    stored.outcome = OUTCOME_REPLAY;
    stored.replay = true;
    stored.message = 'Operação já confirmada — o resultado original foi devolvido.';
    return stored;
  }

  private static ChangeResult changeFail(
    ChangeResult result,
    String outcome,
    String message
  ) {
    result.outcome = outcome;
    result.message = message;
    return result;
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
    return authorityVerdict(accountId) == AUTHORITY_GRANTED;
  }

  /**
   * @description Veredito de autoridade do titular (AXF-3): autorizado, NEGADO ou NÃO CONCLUÍDO.
   *
   * A distinção existe porque `listAuthorizedContexts()` lê os titulares visíveis com `LIMIT 200`,
   * limitação de infraestrutura DIFERIDA pela spec. Tratar "não vi nos primeiros 200" como
   * "principal sem visibilidade" gravaria, no caminho do job, um estado PERMANENTE e BLOQUEANTE de
   * despacho que nenhuma correção de visibilidade limpa — e a limitação é do mecanismo de leitura,
   * não do principal. O veredito não concluído é NÃO terminal e não grava estado.
   */
  private static String authorityVerdict(Id accountId) {
    if (accountId == null) {
      return AUTHORITY_DENIED;
    }
    if (authorizedOverride != null) {
      return authorizedOverride.contains(accountId)
        ? AUTHORITY_GRANTED
        : AUTHORITY_DENIED;
    }
    List<AXF_CLS_AuthorizedContextService.ContextView> contexts = AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    for (AXF_CLS_AuthorizedContextService.ContextView view : contexts) {
      if (view.accountId == accountId) {
        return AUTHORITY_GRANTED;
      }
    }
    Integer contextLimit = (authorizedContextLimitForTest == null)
      ? AUTHORIZED_CONTEXT_LIMIT
      : authorizedContextLimitForTest;
    return (contexts.size() >= contextLimit)
      ? AUTHORITY_TRUNCATED
      : AUTHORITY_DENIED;
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
