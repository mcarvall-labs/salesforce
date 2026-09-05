/**
 * @description Servico de dominio para modelos de remuneracao contratual e termos (AXF-54).
 *
 * Principios e Criterios de Aceite:
 * 1. Modelos MONTHLY, HOURLY e FIXED (FR-53, AD-31):
 *    - Exige apenas campos aplicaveis de cada modelo.
 *    - Rejeita estritamente campos incompativeis.
 *    - Explicita quantidade, taxa, moeda, proporcionalidade e politicas.
 * 2. Cronograma e Arredondamento Canonico:
 *    - Conserva o total contratado para valor fixo parcelado (GF-04).
 *    - Diferenca indivisivel vai para a ultima parcela e fica explicitada como residual.
 *    - Proporcionalidade mensal (proration) por dias corridos/calendario canonico.
 * 3. Politica de Calendario e Ausencia:
 *    - Se regra de calendario/ausencia nao for contratada, ativacao e BLOQUEADA (BLOCKED).
 *    - Nao inventa formula ou feriado local.
 * 4. Imutabilidade e Concorrencia:
 *    - Termo ACTIVE e imutavel (AD-31).
 *    - Concorrencia otimista via expectedVersion (G6).
 */
public with sharing class ALT_CLS_ContractRemunerationService {

  public static final String STATUS_DRAFT = 'DRAFT';
  public static final String STATUS_ACTIVE = 'ACTIVE';
  public static final String STATUS_SUPERSEDED = 'SUPERSEDED';
  public static final String STATUS_BLOCKED = 'BLOCKED';
  public static final String STATUS_CANCELLED = 'CANCELLED';

  public static final String MODEL_MONTHLY = 'MONTHLY';
  public static final String MODEL_HOURLY = 'HOURLY';
  public static final String MODEL_FIXED = 'FIXED';

  public static final String PRORATION_CALENDAR_DAYS = 'CALENDAR_DAYS';
  public static final String PRORATION_BUSINESS_DAYS = 'BUSINESS_DAYS';
  public static final String PRORATION_FIXED_30 = 'FIXED_30';
  public static final String PRORATION_NONE = 'NONE';

  public static final String SHARING_ROW_CAUSE = 'AXF_TermVersionAccess__c';

  /**
   * Conjunto de politicas de calendario contratadas permitidas.
   * Regras fora desta lista sao consideradas nao contratadas e bloqueiam ativacao (AC 3).
   */
  public static final Set<String> CONTRACTED_CALENDAR_POLICIES = new Set<String>{
    'STANDARD_CALENDAR',
    'CALENDAR_DAYS',
    'BUSINESS_DAYS_BRAZIL',
    'BUSINESS_DAYS_STANDARD'
  };

  public class TermVersionInputDTO {
    @AuraEnabled public Id termVersionId;
    @AuraEnabled public Id contractId;
    @AuraEnabled public Id accountId;
    @AuraEnabled public Long revision;
    @AuraEnabled public String remunerationModel;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public Date effectiveFrom;
    @AuraEnabled public Date effectiveTo;
    @AuraEnabled public Decimal contractedAmount;
    @AuraEnabled public Decimal rate;
    @AuraEnabled public Decimal hoursQuantity;
    @AuraEnabled public Integer installments;
    @AuraEnabled public String proportionalityPolicy;
    @AuraEnabled public String timeZone;
    @AuraEnabled public String calendarPolicy;
    @AuraEnabled public Id preferredBankAccountId;
    @AuraEnabled public Long version;
  }

  public class TermVersionDetailDTO {
    @AuraEnabled public Id termVersionId;
    @AuraEnabled public String termNumber;
    @AuraEnabled public String termKey;
    @AuraEnabled public Id contractId;
    @AuraEnabled public String contractCode;
    @AuraEnabled public Long revision;
    @AuraEnabled public String status;
    @AuraEnabled public String remunerationModel;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public Date effectiveFrom;
    @AuraEnabled public Date effectiveTo;
    @AuraEnabled public Decimal contractedAmount;
    @AuraEnabled public Decimal rate;
    @AuraEnabled public Decimal hoursQuantity;
    @AuraEnabled public Integer installments;
    @AuraEnabled public String proportionalityPolicy;
    @AuraEnabled public String timeZone;
    @AuraEnabled public String calendarPolicy;
    @AuraEnabled public Id preferredBankAccountId;
    @AuraEnabled public String blockedReason;
    @AuraEnabled public Long version;
    @AuraEnabled public Datetime createdDate;
    @AuraEnabled public Datetime lastModifiedDate;
  }

  public class ScheduleItemDTO {
    @AuraEnabled public Integer installmentNumber;
    @AuraEnabled public Date dueDate;
    @AuraEnabled public String periodLabel;
    @AuraEnabled public Decimal amount;
    @AuraEnabled public Decimal roundingResidual;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public Boolean isLast;
  }

  public class ScheduleCalculationResultDTO {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public Decimal totalAmount;
    @AuraEnabled public Decimal totalResidual;
    @AuraEnabled public Boolean isConserved;
    @AuraEnabled public String currencyIsoCode;
    @AuraEnabled public List<ScheduleItemDTO> scheduleItems;
  }

  public class OperationResultDTO {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public Id termVersionId;
    @AuraEnabled public String status;
    @AuraEnabled public Long version;
  }

  /**
   * @description Gera chave canonica para o termo: CTV + contractId + revision.
   */
  public static String buildTermKey(Id contractId, Long revision) {
    if (contractId == null || revision == null) {
      throw new AXF_CLS_ContractException('Contrato e Revisao sao obrigatorios para gerar chave do termo.');
    }
    return AXF_CLS_IdentityFraming.key(new List<Object>{
      'CTV',
      contractId,
      revision
    });
  }

  /**
   * @description Valida os campos da versao de termo conforme o modelo de remuneracao (AC 1).
   * Exige somente campos aplicaveis e rejeita campos incompativeis.
   */
  public void validateDraftTermVersion(TermVersionInputDTO input) {
    if (input == null) {
      throw new AXF_CLS_ContractException('Dados da versao do termo sao obrigatorios.');
    }
    if (input.contractId == null) {
      throw new AXF_CLS_ContractException('O Contrato aggregate root e obrigatorio.');
    }
    if (String.isBlank(input.remunerationModel)) {
      throw new AXF_CLS_ContractException('O Modelo de Remuneracao e obrigatorio (MONTHLY, HOURLY ou FIXED).');
    }
    if (String.isBlank(input.currencyIsoCode)) {
      throw new AXF_CLS_ContractException('A Moeda do termo e obrigatoria.');
    }
    if (input.effectiveFrom == null) {
      throw new AXF_CLS_ContractException('A data de vigencia inicial e obrigatoria.');
    }
    if (input.effectiveTo != null && input.effectiveTo < input.effectiveFrom) {
      throw new AXF_CLS_ContractException('A data de vigencia final nao pode ser anterior a vigencia inicial.');
    }

    String model = input.remunerationModel.trim().toUpperCase();

    if (model == MODEL_MONTHLY) {
      validateMonthlyModel(input);
    } else if (model == MODEL_HOURLY) {
      validateHourlyModel(input);
    } else if (model == MODEL_FIXED) {
      validateFixedModel(input);
    } else {
      throw new AXF_CLS_ContractException('Modelo de remuneracao invalido: ' + input.remunerationModel + '. Deve ser MONTHLY, HOURLY ou FIXED.');
    }
  }

  private void validateMonthlyModel(TermVersionInputDTO input) {
    // Exige campos aplicaveis
    if (input.rate == null || input.rate <= 0) {
      throw new AXF_CLS_ContractException('Modelo MONTHLY exige Taxa/Valor Mensal positivo (campo Rate).');
    }
    if (String.isBlank(input.proportionalityPolicy)) {
      input.proportionalityPolicy = PRORATION_CALENDAR_DAYS;
    } else {
      Set<String> validPolicies = new Set<String>{ PRORATION_CALENDAR_DAYS, PRORATION_BUSINESS_DAYS, PRORATION_FIXED_30, PRORATION_NONE };
      if (!validPolicies.contains(input.proportionalityPolicy.trim().toUpperCase())) {
        throw new AXF_CLS_ContractException('Politica de proporcionalidade invalida: ' + input.proportionalityPolicy);
      }
    }

    // Rejeita campos incompativeis com MONTHLY
    if (input.hoursQuantity != null) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo MONTHLY: Quantidade de Horas nao e aplicavel.');
    }
    if (input.installments != null) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo MONTHLY: Numero de Parcelas nao e aplicavel.');
    }
    if (input.contractedAmount != null) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo MONTHLY: Valor Total Contratado (Fixo) nao e aplicavel.');
    }
  }

  private void validateHourlyModel(TermVersionInputDTO input) {
    // Exige campos aplicaveis
    if (input.rate == null || input.rate <= 0) {
      throw new AXF_CLS_ContractException('Modelo HOURLY exige Taxa Horaria positiva (campo Rate).');
    }
    if (input.hoursQuantity == null || input.hoursQuantity <= 0) {
      throw new AXF_CLS_ContractException('Modelo HOURLY exige Quantidade de Horas positiva (campo HoursQuantity).');
    }

    // Rejeita campos incompativeis com HOURLY
    if (input.installments != null) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo HOURLY: Numero de Parcelas nao e aplicavel.');
    }
    if (input.contractedAmount != null) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo HOURLY: Valor Total Contratado (Fixo) nao e aplicavel.');
    }
    if (String.isNotBlank(input.proportionalityPolicy)) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo HOURLY: Politica de Proporcionalidade nao e aplicavel.');
    }
  }

  private void validateFixedModel(TermVersionInputDTO input) {
    // Exige campos aplicaveis
    if (input.contractedAmount == null || input.contractedAmount <= 0) {
      throw new AXF_CLS_ContractException('Modelo FIXED exige Valor Total Contratado positivo (campo ContractedAmount).');
    }
    if (input.installments == null || input.installments < 1) {
      throw new AXF_CLS_ContractException('Modelo FIXED exige Numero de Parcelas maior ou igual a 1 (campo Installments).');
    }

    // Rejeita campos incompativeis com FIXED
    if (input.rate != null) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo FIXED: Taxa Periodica / Horaria nao e aplicavel.');
    }
    if (input.hoursQuantity != null) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo FIXED: Quantidade de Horas nao e aplicavel.');
    }
    if (String.isNotBlank(input.proportionalityPolicy)) {
      throw new AXF_CLS_ContractException('Campo incompativel com o modelo FIXED: Politica de Proporcionalidade nao e aplicavel.');
    }
  }

  /**
   * @description Cria ou salva uma versao de termo contratual em estado DRAFT.
   */
  public OperationResultDTO saveDraftTermVersion(TermVersionInputDTO input) {
    validateDraftTermVersion(input);

    AXF_OBJ_Contract__c contract = [
      SELECT Id, AXF_CTR_LKP_Account__c, AXF_CTR_PKL_Lifecycle__c, AXF_CTR_TXT_ContractCode__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :input.contractId
      LIMIT 1
    ];

    if (input.accountId != null && input.accountId != contract.AXF_CTR_LKP_Account__c) {
      throw new AXF_CLS_ContractException('Acesso negado: o contrato pertence a outra Entidade.');
    }

    AXF_OBJ_ContractTermVersion__c tv;
    Boolean isNew = (input.termVersionId == null);

    if (isNew) {
      // Determina proxima revisao
      List<AggregateResult> maxRev = [
        SELECT MAX(AXF_CTV_NUM_Revision__c) maxR
        FROM AXF_OBJ_ContractTermVersion__c
        WHERE AXF_CTV_LKP_Contract__c = :contract.Id
      ];
      Decimal currentMax = (Decimal) maxRev[0].get('maxR');
      Long nextRevision = (currentMax != null) ? currentMax.longValue() + 1 : 1;

      tv = new AXF_OBJ_ContractTermVersion__c();
      tv.AXF_CTV_LKP_Contract__c = contract.Id;
      tv.AXF_CTV_NUM_Revision__c = nextRevision;
      tv.AXF_CTV_PKL_Status__c = STATUS_DRAFT;
      tv.AXF_CTV_EXI_TermKey__c = buildTermKey(contract.Id, nextRevision);
      tv.AXF_CTV_NUM_Version__c = 1;
    } else {
      tv = [
        SELECT
          Id,
          AXF_CTV_LKP_Contract__c,
          AXF_CTV_NUM_Revision__c,
          AXF_CTV_PKL_Status__c,
          AXF_CTV_NUM_Version__c
        FROM AXF_OBJ_ContractTermVersion__c
        WHERE Id = :input.termVersionId
        LIMIT 1
      ];

      if (tv.AXF_CTV_PKL_Status__c == STATUS_ACTIVE) {
        throw new AXF_CLS_ContractException('Termos com status ACTIVE sao imutaveis e nao podem ser editados (AD-31).');
      }

      if (input.version != null && input.version != tv.AXF_CTV_NUM_Version__c) {
        throw new AXF_CLS_ContractException('Conflito de concorrencia: a versao do termo foi alterada por outro usuario.');
      }
      tv.AXF_CTV_NUM_Version__c = tv.AXF_CTV_NUM_Version__c + 1;
    }

    String model = input.remunerationModel.trim().toUpperCase();
    tv.AXF_CTV_PKL_RemunerationModel__c = model;
    tv.AXF_CTV_TXT_CurrencyIsoCode__c = input.currencyIsoCode.trim().toUpperCase();
    tv.AXF_CTV_DAT_EffectiveFrom__c = input.effectiveFrom;
    tv.AXF_CTV_DAT_EffectiveTo__c = input.effectiveTo;
    tv.AXF_CTV_TXT_TimeZone__c = input.timeZone;
    tv.AXF_CTV_TXT_CalendarPolicy__c = input.calendarPolicy;
    tv.AXF_CTV_LKP_PreferredBankAccount__c = input.preferredBankAccountId;

    if (model == MODEL_MONTHLY) {
      tv.AXF_CTV_CUR_Rate__c = input.rate;
      tv.AXF_CTV_PKL_ProportionalityPolicy__c = input.proportionalityPolicy;
      tv.AXF_CTV_NUM_HoursQuantity__c = null;
      tv.AXF_CTV_NUM_Installments__c = null;
      tv.AXF_CTV_CUR_ContractedAmount__c = null;
    } else if (model == MODEL_HOURLY) {
      tv.AXF_CTV_CUR_Rate__c = input.rate;
      tv.AXF_CTV_NUM_HoursQuantity__c = input.hoursQuantity;
      tv.AXF_CTV_PKL_ProportionalityPolicy__c = null;
      tv.AXF_CTV_NUM_Installments__c = null;
      tv.AXF_CTV_CUR_ContractedAmount__c = null;
    } else if (model == MODEL_FIXED) {
      tv.AXF_CTV_CUR_ContractedAmount__c = input.contractedAmount;
      tv.AXF_CTV_NUM_Installments__c = input.installments;
      tv.AXF_CTV_CUR_Rate__c = null;
      tv.AXF_CTV_NUM_HoursQuantity__c = null;
      tv.AXF_CTV_PKL_ProportionalityPolicy__c = null;
    }

    upsert tv;

    // Compartilhamento Apex Managed Sharing para o dono da Entidade
    Account acc = [SELECT OwnerId FROM Account WHERE Id = :contract.AXF_CTR_LKP_Account__c LIMIT 1];
    grantSharingPrivileged(tv.Id, acc.OwnerId);

    OperationResultDTO result = new OperationResultDTO();
    result.success = true;
    result.message = 'Versao de termo salva com sucesso.';
    result.termVersionId = tv.Id;
    result.status = tv.AXF_CTV_PKL_Status__c;
    result.version = tv.AXF_CTV_NUM_Version__c.longValue();
    return result;
  }

  /**
   * @description Calcula o cronograma financeiro conservando total e aplicando arredondamento/residual canonicos (AC 2, GF-04).
   */
  public ScheduleCalculationResultDTO calculateSchedule(TermVersionInputDTO input) {
    if (input == null) {
      throw new AXF_CLS_ContractException('Insumos para calculo do cronograma sao obrigatorios.');
    }
    validateDraftTermVersion(input);

    String model = input.remunerationModel.trim().toUpperCase();
    String currencyIso = String.isNotBlank(input.currencyIsoCode) ? input.currencyIsoCode.trim().toUpperCase() : 'BRL';

    ScheduleCalculationResultDTO result = new ScheduleCalculationResultDTO();
    result.currencyIsoCode = currencyIso;
    result.scheduleItems = new List<ScheduleItemDTO>();

    if (model == MODEL_FIXED) {
      calculateFixedSchedule(input, result);
    } else if (model == MODEL_MONTHLY) {
      calculateMonthlySchedule(input, result);
    } else if (model == MODEL_HOURLY) {
      calculateHourlySchedule(input, result);
    }

    result.success = true;
    result.message = 'Cronograma calculado com conservacao estrita e residual explicito.';
    return result;
  }

  /**
   * Calculo canonico de parcelas fixas com conservacao de total e residual na ultima parcela (GF-04).
   */
  private void calculateFixedSchedule(TermVersionInputDTO input, ScheduleCalculationResultDTO result) {
    Decimal totalAmount = input.contractedAmount.setScale(2, System.RoundingMode.HALF_UP);
    Integer n = input.installments;
    Date baseDate = (input.effectiveFrom != null) ? input.effectiveFrom : Date.today();

    // Divisao base arredondada para 2 casas
    Decimal baseInstallment = (totalAmount / n).setScale(2, System.RoundingMode.HALF_UP);
    Decimal allocatedPrior = 0.00;
    Decimal totalResidual = 0.00;

    for (Integer i = 1; i <= n; i++) {
      ScheduleItemDTO item = new ScheduleItemDTO();
      item.installmentNumber = i;
      item.dueDate = baseDate.addMonths(i - 1);
      item.currencyIsoCode = result.currencyIsoCode;

      if (i < n) {
        item.amount = baseInstallment;
        item.roundingResidual = 0.00;
        item.isLast = false;
        item.periodLabel = 'Parcela ' + i + '/' + n;
        allocatedPrior += baseInstallment;
      } else {
        // Ultima parcela recebe a diferenca indivisivel residual
        item.amount = (totalAmount - allocatedPrior).setScale(2, System.RoundingMode.HALF_UP);
        item.roundingResidual = (item.amount - baseInstallment).setScale(2, System.RoundingMode.HALF_UP);
        item.isLast = true;
        item.periodLabel = 'Parcela ' + i + '/' + n + ' (Final com residual)';
        totalResidual = item.roundingResidual;
        allocatedPrior += item.amount;
      }
      result.scheduleItems.add(item);
    }

    result.totalAmount = allocatedPrior;
    result.totalResidual = totalResidual;
    // Conservacao estrita: soma das parcelas DEVE ser identica ao total informado
    result.isConserved = (allocatedPrior == totalAmount);
  }

  /**
   * Calculo de competencias mensais com politica de proporcionalidade (proration) canonica.
   */
  private void calculateMonthlySchedule(TermVersionInputDTO input, ScheduleCalculationResultDTO result) {
    Decimal rate = input.rate.setScale(2, System.RoundingMode.HALF_UP);
    Date startDt = input.effectiveFrom;
    Date endDt = (input.effectiveTo != null) ? input.effectiveTo : startDt.addMonths(1);
    String prorationPolicy = String.isNotBlank(input.proportionalityPolicy) ? input.proportionalityPolicy : PRORATION_CALENDAR_DAYS;

    Decimal totalSum = 0.00;
    Date currentCursor = startDt;
    Integer itemIndex = 1;

    while (currentCursor < endDt) {
      Integer year = currentCursor.year();
      Integer month = currentCursor.month();
      Integer daysInMonth = Date.daysInMonth(year, month);
      Date monthStart = Date.newInstance(year, month, 1);
      Date monthEnd = Date.newInstance(year, month, daysInMonth);

      Date cycleStart = (currentCursor > monthStart) ? currentCursor : monthStart;
      Date cycleEnd = (endDt < monthEnd) ? endDt : monthEnd;

      Integer activeDays = cycleStart.daysBetween(cycleEnd) + 1;
      Boolean isPartial = (activeDays < daysInMonth);

      ScheduleItemDTO item = new ScheduleItemDTO();
      item.installmentNumber = itemIndex;
      item.dueDate = cycleStart;
      item.currencyIsoCode = result.currencyIsoCode;
      item.roundingResidual = 0.00;

      if (!isPartial || prorationPolicy == PRORATION_NONE) {
        item.amount = rate;
        item.periodLabel = 'Competencia ' + month + '/' + year + ' (Integral)';
      } else if (prorationPolicy == PRORATION_FIXED_30) {
        Decimal factor = ((Decimal) activeDays) / 30.0;
        item.amount = (rate * factor).setScale(2, System.RoundingMode.HALF_UP);
        item.periodLabel = 'Competencia ' + month + '/' + year + ' (' + activeDays + '/30 dias - Base 30)';
      } else {
        // CALENDAR_DAYS ou BUSINESS_DAYS default
        Decimal factor = ((Decimal) activeDays) / ((Decimal) daysInMonth);
        item.amount = (rate * factor).setScale(2, System.RoundingMode.HALF_UP);
        item.periodLabel = 'Competencia ' + month + '/' + year + ' (' + activeDays + '/' + daysInMonth + ' dias corridos)';
      }

      totalSum += item.amount;
      result.scheduleItems.add(item);

      itemIndex++;
      currentCursor = monthEnd.addDays(1);
    }

    if (!result.scheduleItems.isEmpty()) {
      result.scheduleItems[result.scheduleItems.size() - 1].isLast = true;
    }

    result.totalAmount = totalSum.setScale(2, System.RoundingMode.HALF_UP);
    result.totalResidual = 0.00;
    result.isConserved = true;
  }

  /**
   * Calculo de valor esperado para modelo por hora.
   */
  private void calculateHourlySchedule(TermVersionInputDTO input, ScheduleCalculationResultDTO result) {
    Decimal expectedTotal = (input.rate * input.hoursQuantity).setScale(2, System.RoundingMode.HALF_UP);
    ScheduleItemDTO item = new ScheduleItemDTO();
    item.installmentNumber = 1;
    item.dueDate = (input.effectiveFrom != null) ? input.effectiveFrom : Date.today();
    item.periodLabel = 'Estimativa de Horas (' + input.hoursQuantity + 'h @ ' + input.rate + '/h)';
    item.amount = expectedTotal;
    item.roundingResidual = 0.00;
    item.currencyIsoCode = result.currencyIsoCode;
    item.isLast = true;

    result.scheduleItems.add(item);
    result.totalAmount = expectedTotal;
    result.totalResidual = 0.00;
    result.isConserved = true;
  }

  /**
   * @description Tenta ativar uma versao de termo contratual (AC 3).
   * Se regra de calendario/ausencia nao estiver explicitamente contratada, transiciona para BLOCKED
   * e bloqueia a ativacao sem inventar formulas ou feriados locais.
   */
  public OperationResultDTO activateTermVersion(Id termVersionId, Id accountId) {
    if (termVersionId == null) {
      throw new AXF_CLS_ContractException('ID da versao de termo e obrigatorio para ativacao.');
    }

    List<AXF_OBJ_ContractTermVersion__c> terms = [
      SELECT
        Id,
        Name,
        AXF_CTV_LKP_Contract__c,
        AXF_CTV_LKP_Contract__r.AXF_CTR_LKP_Account__c,
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
        AXF_CTV_TXT_CalendarPolicy__c,
        AXF_CTV_NUM_Version__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE Id = :termVersionId
      LIMIT 1
    ];

    if (terms.isEmpty()) {
      throw new AXF_CLS_ContractException('Versao de termo nao encontrada.');
    }

    AXF_OBJ_ContractTermVersion__c tv = terms[0];

    if (accountId != null && accountId != tv.AXF_CTV_LKP_Contract__r.AXF_CTR_LKP_Account__c) {
      throw new AXF_CLS_ContractException('Acesso negado: o termo pertence a outra Entidade.');
    }

    // Valida modelo de remuneracao antes de ativar
    TermVersionInputDTO input = new TermVersionInputDTO();
    input.contractId = tv.AXF_CTV_LKP_Contract__c;
    input.remunerationModel = tv.AXF_CTV_PKL_RemunerationModel__c;
    input.currencyIsoCode = tv.AXF_CTV_TXT_CurrencyIsoCode__c;
    input.effectiveFrom = tv.AXF_CTV_DAT_EffectiveFrom__c;
    input.effectiveTo = tv.AXF_CTV_DAT_EffectiveTo__c;
    input.contractedAmount = tv.AXF_CTV_CUR_ContractedAmount__c;
    input.rate = tv.AXF_CTV_CUR_Rate__c;
    input.hoursQuantity = tv.AXF_CTV_NUM_HoursQuantity__c;
    input.installments = (tv.AXF_CTV_NUM_Installments__c != null) ? tv.AXF_CTV_NUM_Installments__c.intValue() : null;
    input.proportionalityPolicy = tv.AXF_CTV_PKL_ProportionalityPolicy__c;
    validateDraftTermVersion(input);

    // GATE CANONICO DE CALENDARIO E AUSENCIA (AC 3):
    // Se regra de calendario ou ausencia nao contratada -> BLOCKED (nao inventa formula ou feriado local)
    Boolean isCalendarContracted = isContractedCalendarPolicy(tv.AXF_CTV_TXT_CalendarPolicy__c);
    Boolean isValidTimeZone = isContractedTimeZone(tv.AXF_CTV_TXT_TimeZone__c);

    if (!isCalendarContracted || !isValidTimeZone) {
      tv.AXF_CTV_PKL_Status__c = STATUS_BLOCKED;
      String reason = (!isCalendarContracted)
        ? 'Regra de calendario ou ausencia nao contratada (' + tv.AXF_CTV_TXT_CalendarPolicy__c + '). Nao e permitido inventar formula ou feriado local.'
        : 'Fuso horario nao contratado ou invalido (' + tv.AXF_CTV_TXT_TimeZone__c + ').';
      tv.AXF_CTV_TXT_BlockedReason__c = reason;
      tv.AXF_CTV_NUM_Version__c = tv.AXF_CTV_NUM_Version__c + 1;
      update tv;

      OperationResultDTO blockedResult = new OperationResultDTO();
      blockedResult.success = false;
      blockedResult.termVersionId = tv.Id;
      blockedResult.status = STATUS_BLOCKED;
      blockedResult.message = 'Ativacao BLOQUEADA: ' + reason;
      blockedResult.version = tv.AXF_CTV_NUM_Version__c.longValue();
      return blockedResult;
    }

    // Ativacao canonica: fecha predecessora ativa sem sobreposicao (AD-31)
    List<AXF_OBJ_ContractTermVersion__c> activePredecessors = [
      SELECT Id, AXF_CTV_DAT_EffectiveTo__c, AXF_CTV_PKL_Status__c, AXF_CTV_NUM_Version__c
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE AXF_CTV_LKP_Contract__c = :tv.AXF_CTV_LKP_Contract__c
        AND AXF_CTV_PKL_Status__c = :STATUS_ACTIVE
        AND Id != :tv.Id
    ];

    for (AXF_OBJ_ContractTermVersion__c pred : activePredecessors) {
      pred.AXF_CTV_PKL_Status__c = STATUS_SUPERSEDED;
      pred.AXF_CTV_DAT_EffectiveTo__c = tv.AXF_CTV_DAT_EffectiveFrom__c;
      pred.AXF_CTV_NUM_Version__c = pred.AXF_CTV_NUM_Version__c + 1;
    }
    if (!activePredecessors.isEmpty()) {
      update activePredecessors;
    }

    tv.AXF_CTV_PKL_Status__c = STATUS_ACTIVE;
    tv.AXF_CTV_TXT_BlockedReason__c = null;
    tv.AXF_CTV_NUM_Version__c = tv.AXF_CTV_NUM_Version__c + 1;
    update tv;

    OperationResultDTO result = new OperationResultDTO();
    result.success = true;
    result.message = 'Versao de termo ativada com sucesso.';
    result.termVersionId = tv.Id;
    result.status = STATUS_ACTIVE;
    result.version = tv.AXF_CTV_NUM_Version__c.longValue();
    return result;
  }

  /**
   * @description Consulta todas as versoes de termos de um Contrato.
   */
  public List<TermVersionDetailDTO> getTermVersionsByContract(Id contractId, Id accountId) {
    if (contractId == null) {
      throw new AXF_CLS_ContractException('ID do Contrato e obrigatorio.');
    }

    List<AXF_OBJ_ContractTermVersion__c> terms = [
      SELECT
        Id,
        Name,
        AXF_CTV_EXI_TermKey__c,
        AXF_CTV_LKP_Contract__c,
        AXF_CTV_LKP_Contract__r.AXF_CTR_TXT_ContractCode__c,
        AXF_CTV_LKP_Contract__r.AXF_CTR_LKP_Account__c,
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
        AXF_CTV_TXT_CalendarPolicy__c,
        AXF_CTV_LKP_PreferredBankAccount__c,
        AXF_CTV_TXT_BlockedReason__c,
        AXF_CTV_NUM_Version__c,
        CreatedDate,
        LastModifiedDate
      FROM AXF_OBJ_ContractTermVersion__c
      WHERE AXF_CTV_LKP_Contract__c = :contractId
      ORDER BY AXF_CTV_NUM_Revision__c DESC
    ];

    List<TermVersionDetailDTO> dtos = new List<TermVersionDetailDTO>();
    for (AXF_OBJ_ContractTermVersion__c tv : terms) {
      if (accountId != null && tv.AXF_CTV_LKP_Contract__r.AXF_CTR_LKP_Account__c != accountId) {
        continue;
      }
      TermVersionDetailDTO dto = new TermVersionDetailDTO();
      dto.termVersionId = tv.Id;
      dto.termNumber = tv.Name;
      dto.termKey = tv.AXF_CTV_EXI_TermKey__c;
      dto.contractId = tv.AXF_CTV_LKP_Contract__c;
      dto.contractCode = tv.AXF_CTV_LKP_Contract__r.AXF_CTR_TXT_ContractCode__c;
      dto.revision = (tv.AXF_CTV_NUM_Revision__c != null) ? tv.AXF_CTV_NUM_Revision__c.longValue() : 1;
      dto.status = tv.AXF_CTV_PKL_Status__c;
      dto.remunerationModel = tv.AXF_CTV_PKL_RemunerationModel__c;
      dto.currencyIsoCode = tv.AXF_CTV_TXT_CurrencyIsoCode__c;
      dto.effectiveFrom = tv.AXF_CTV_DAT_EffectiveFrom__c;
      dto.effectiveTo = tv.AXF_CTV_DAT_EffectiveTo__c;
      dto.contractedAmount = tv.AXF_CTV_CUR_ContractedAmount__c;
      dto.rate = tv.AXF_CTV_CUR_Rate__c;
      dto.hoursQuantity = tv.AXF_CTV_NUM_HoursQuantity__c;
      dto.installments = (tv.AXF_CTV_NUM_Installments__c != null) ? tv.AXF_CTV_NUM_Installments__c.intValue() : null;
      dto.proportionalityPolicy = tv.AXF_CTV_PKL_ProportionalityPolicy__c;
      dto.timeZone = tv.AXF_CTV_TXT_TimeZone__c;
      dto.calendarPolicy = tv.AXF_CTV_TXT_CalendarPolicy__c;
      dto.preferredBankAccountId = tv.AXF_CTV_LKP_PreferredBankAccount__c;
      dto.blockedReason = tv.AXF_CTV_TXT_BlockedReason__c;
      dto.version = (tv.AXF_CTV_NUM_Version__c != null) ? tv.AXF_CTV_NUM_Version__c.longValue() : 0;
      dto.createdDate = tv.CreatedDate;
      dto.lastModifiedDate = tv.LastModifiedDate;
      dtos.add(dto);
    }
    return dtos;
  }

  /**
   * @description Verifica se uma politica de calendario e formalmente contratada.
   */
  public static Boolean isContractedCalendarPolicy(String policy) {
    if (String.isBlank(policy)) {
      return false;
    }
    return CONTRACTED_CALENDAR_POLICIES.contains(policy.trim().toUpperCase());
  }

  /**
   * @description Verifica se o fuso horario e um identificador IANA valido.
   */
  public static Boolean isContractedTimeZone(String tz) {
    if (String.isBlank(tz)) {
      return false;
    }
    try {
      TimeZone resolved = TimeZone.getTimeZone(tz.trim());
      // No Apex, getTimeZone retorna GMT se for desconhecido
      if (resolved.getID().equalsIgnoreCase('GMT') && !tz.trim().equalsIgnoreCase('GMT') && !tz.trim().equalsIgnoreCase('UTC')) {
        return false;
      }
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  /**
   * @description Compartilhamento gerenciado por Apex para o dono da Entidade (G2).
   */
  private static void grantSharingPrivileged(Id termVersionId, Id entityOwnerId) {
    if (entityOwnerId == null || termVersionId == null) {
      return;
    }
    try {
      AXF_OBJ_ContractTermVersion__Share tvShare = new AXF_OBJ_ContractTermVersion__Share();
      tvShare.ParentId = termVersionId;
      tvShare.UserOrGroupId = entityOwnerId;
      tvShare.AccessLevel = 'Edit';
      tvShare.RowCause = Schema.AXF_OBJ_ContractTermVersion__Share.RowCause.AXF_TermVersionAccess__c;
      Database.insert(tvShare, false);
    } catch (Exception e) {
      // Ignora se ja possuir acesso superior
    }
  }
}
