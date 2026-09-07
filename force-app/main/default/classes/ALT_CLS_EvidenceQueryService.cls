/**
 * @description Consulta read-only de evidencias nativas e de dominio (AXF-49, G7 fechado).
 *
 * Nao cria AuditEvent nem servico generico de auditoria: expoe a matriz G7 (evento material
 * -> evidencia imutavel) e le somente os registros de evidencia que a operacao de origem ja
 * emitiu (CAS/FXS/FxC/EXR/FxSettlement). Regras:
 * - Somente leitura: nenhum DML, edicao ou exclusao de evidencia protegida;
 * - Classe with sharing (mesmo padrao de ALT_CLS_ContractSnapshotService/FxSettlementService):
 *   registro invisivel por sharing -> negado sem vazar existencia; tipo nao suportado -> excecao;
 * - Select explicito por allowlist de campos de consulta: nunca retorna payload bruto, JSON de
 *   proveniencia, segredo ou campo fora da superficie de evidencia;
 * - Eventos cuja evidencia imutavel ainda nao foi integrada em develop (ex.: Reconciliation,
 *   ReviewItem, CalculationSnapshot, BillingDocumentVersion) sao reportados como GAP na matriz,
 *   nunca preenchidos com auditoria ficticia.
 * A emissao de evidencia pertence as mutacoes de origem (AXF-57/24/59/61); esta US habilita a
 * consulta sem esperar todos os modulos existirem.
 */
public with sharing class ALT_CLS_EvidenceQueryService {
  public static final String COVERED_IMMUTABLE = 'COVERED_IMMUTABLE_SNAPSHOT';
  public static final String COVERED_NATIVE = 'COVERED_NATIVE';
  public static final String GAP_NOT_INTEGRATED = 'GAP_NOT_INTEGRATED';

  public static final String EVT_CONTRACT_APPLICATION = 'CONTRACT_APPLICATION';
  public static final String EVT_FX_MATERIAL_CONVERSION = 'FX_MATERIAL_CONVERSION';
  public static final String EVT_FX_CHARGE = 'FX_CHARGE';
  public static final String EVT_FX_SETTLEMENT = 'FX_SETTLEMENT';
  public static final String EVT_RATE_EVIDENCE = 'RATE_EVIDENCE';
  public static final String EVT_RECONCILIATION = 'RECONCILIATION';
  public static final String EVT_REVIEW_RESOLUTION = 'REVIEW_RESOLUTION';
  public static final String EVT_CALCULATION_DECISION = 'CALCULATION_DECISION';
  public static final String EVT_BILLING_ISSUANCE = 'BILLING_ISSUANCE';

  public static final Set<String> SUPPORTED_TYPES = new Set<String>{
    'AXF_OBJ_ContractApplicationSnapshot__c',
    'AXF_OBJ_FxApplicationSnapshot__c',
    'AXF_OBJ_FxSettlementCharge__c',
    'AXF_OBJ_FxSettlement__c',
    'AXF_OBJ_ExchangeRate__c'
  };

  /** Linha da matriz G7-2 (fechamento 30/08): evento material -> evidencia. */
  public class CoverageRowDTO {
    public String eventKey;
    public String eventLabel;
    public String coverage;
    public String evidenceObjectApi;
    public String retentionDomain;
    public String limitNote;
    public Boolean actorAvailable;
    public Boolean instantAvailable;
    public Boolean sourceAvailable;
    public Boolean reasonAvailable;
    public Boolean priorStateAvailable;
  }

  /** Resultado da consulta para um registro-alvo de evidencia. */
  public class EvidenceEntryDTO {
    public String evidenceObjectApi;
    public String eventKey;
    public Id evidenceId;
    public String recordLabel;
    public Id actorUserId;
    public String actorName;
    public Datetime instant;
    public String sourceLabel;
    public String reasonLabel;
    public String priorStateLabel;
    public String stateLabel;
    public String coverage;
  }

  public class QueryResultDTO {
    public Boolean found;
    public Boolean denied;
    public List<EvidenceEntryDTO> entries;
  }

  /** Matriz G7-2 por evento material, com cobertura real em develop hoje (06/09/2026). */
  public static List<CoverageRowDTO> evidenceCoverage() {
    List<CoverageRowDTO> rows = new List<CoverageRowDTO>();
    rows.add(
      row(
        EVT_CONTRACT_APPLICATION,
        'Aplicacao de contrato',
        COVERED_IMMUTABLE,
        'AXF_OBJ_ContractApplicationSnapshot__c',
        'contract.snapshot',
        '1:1 imutavel; correcao = sucessor + SUPERSEDED; retencao longa propria (G7-3).',
        true,
        true,
        true,
        true,
        true
      )
    );
    rows.add(
      row(
        EVT_FX_MATERIAL_CONVERSION,
        'Conversao cambial material',
        COVERED_IMMUTABLE,
        'AXF_OBJ_FxApplicationSnapshot__c',
        'fx.snapshot',
        'Congela taxa/fonte/lado/data/policy; retencao longa propria (G7-3).',
        true,
        true,
        true,
        true,
        true
      )
    );
    rows.add(
      row(
        EVT_FX_CHARGE,
        'Encargo de liquidacao cambial',
        COVERED_IMMUTABLE,
        'AXF_OBJ_FxSettlementCharge__c',
        'fx.charge',
        'Filho imutavel de FxSettlement; retencao longa propria.',
        true,
        true,
        true,
        true,
        true
      )
    );
    rows.add(
      row(
        EVT_FX_SETTLEMENT,
        'Liquidacao cambial',
        COVERED_IMMUTABLE,
        'AXF_OBJ_FxSettlement__c',
        'fx.settlement',
        'Root append-only (DRAFT..CONFIRMED/CORRECTION/REVERSAL); retencao longa propria.',
        true,
        true,
        true,
        true,
        true
      )
    );
    rows.add(
      row(
        EVT_RATE_EVIDENCE,
        'Cotacao de referencia',
        COVERED_NATIVE,
        'AXF_OBJ_ExchangeRate__c',
        'fx.rate',
        'Fonte publica PTAX/BCB; chave Provider+Pair+Data+Bulletin+Side.',
        true,
        true,
        true,
        false,
        false
      )
    );
    rows.add(
      row(
        EVT_RECONCILIATION,
        'Reconciliacao / reversao',
        GAP_NOT_INTEGRATED,
        'AXF_OBJ_Reconciliation__c',
        'reconciliation',
        'Objeto append-only ainda nao integrado em develop; consulta indisponivel (G7-2).',
        false,
        false,
        false,
        false,
        false
      )
    );
    rows.add(
      row(
        EVT_REVIEW_RESOLUTION,
        'Resolucao de item de revisao',
        GAP_NOT_INTEGRATED,
        'AXF_OBJ_ReviewItem__c',
        'review.prior',
        'ReviewItem (AD-41) ainda nao integrado; Prior* expurgados apos resolucao + janela.',
        false,
        false,
        false,
        false,
        false
      )
    );
    rows.add(
      row(
        EVT_CALCULATION_DECISION,
        'Decisao / fechamento de calculo',
        GAP_NOT_INTEGRATED,
        'AXF_OBJ_CalculationSnapshot__c',
        'calculation.snapshot',
        'Snapshot de calculo ainda nao integrado em develop.',
        false,
        false,
        false,
        false,
        false
      )
    );
    rows.add(
      row(
        EVT_BILLING_ISSUANCE,
        'Emissao de documento de cobranca',
        GAP_NOT_INTEGRATED,
        'AXF_OBJ_BillingDocumentVersion__c',
        'billing.document',
        'Dominio billing em fechamento; ISSUED imutavel ainda nao integrado.',
        false,
        false,
        false,
        false,
        false
      )
    );
    return rows;
  }

  /** Consulta a evidencia emitida para um registro de evidencia imutavel ja integrado. */
  public static QueryResultDTO queryEvidenceForRecord(Id recordId) {
    QueryResultDTO out = new QueryResultDTO();
    out.entries = new List<EvidenceEntryDTO>();
    if (recordId == null) {
      throw new AXF_CLS_EvidenceQueryException(
        'Alvo de evidencia e obrigatorio.'
      );
    }
    String sobj = recordId.getSObjectType().getDescribe().getName();
    if (!SUPPORTED_TYPES.contains(sobj)) {
      throw new AXF_CLS_EvidenceQueryException(
        'Tipo de registro sem evidencia imutavel consultavel nesta superficie.'
      );
    }
    try {
      if (sobj == 'AXF_OBJ_ContractApplicationSnapshot__c') {
        out = queryCas(recordId);
      } else if (sobj == 'AXF_OBJ_FxApplicationSnapshot__c') {
        out = queryFxs(recordId);
      } else if (sobj == 'AXF_OBJ_FxSettlementCharge__c') {
        out = queryFxc(recordId);
      } else if (sobj == 'AXF_OBJ_FxSettlement__c') {
        out = queryFxt(recordId);
      } else if (sobj == 'AXF_OBJ_ExchangeRate__c') {
        out = queryExr(recordId);
      }
    } catch (Exception e) {
      out = new QueryResultDTO();
      out.entries = new List<EvidenceEntryDTO>();
    }
    if (out.entries.isEmpty()) {
      out.found = false;
      out.denied = true;
    }
    return out;
  }

  /** Consulta todas as evidencias imutaveis ligadas a um FinancialTransaction. */
  public static QueryResultDTO queryEvidenceForFinancialTransaction(Id ftxId) {
    QueryResultDTO out = new QueryResultDTO();
    out.entries = new List<EvidenceEntryDTO>();
    if (ftxId == null) {
      throw new AXF_CLS_EvidenceQueryException('Alvo e obrigatorio.');
    }
    List<AXF_OBJ_FinancialTransaction__c> root = [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :ftxId
      LIMIT 1
    ];
    if (root.isEmpty()) {
      out.denied = true;
      return out;
    }
    for (AXF_OBJ_ContractApplicationSnapshot__c cas : [
      SELECT
        Id,
        Name,
        AXF_CAS_PKL_State__c,
        AXF_CAS_NUM_Version__c,
        AXF_CAS_DT_OverriddenAt__c,
        AXF_CAS_TAL_OverrideReason__c,
        AXF_CAS_LKP_OverriddenByUser__c,
        AXF_CAS_LKP_PredecessorSnapshot__c,
        AXF_CAS_EXI_ApplicationIdentityHash__c,
        CreatedById,
        CreatedDate
      FROM AXF_OBJ_ContractApplicationSnapshot__c
      WHERE AXF_CAS_LKP_FinancialTransaction__c = :ftxId
      ORDER BY CreatedDate ASC
    ]) {
      out.entries.add(casEntry(cas));
    }
    for (AXF_OBJ_FxApplicationSnapshot__c fxs : [
      SELECT
        Id,
        Name,
        AXF_FXS_PKL_State__c,
        AXF_FXS_NUM_Version__c,
        AXF_FXS_DT_AppliedAt__c,
        AXF_FXS_PKL_Purpose__c,
        AXF_FXS_LKP_ActorUser__c,
        AXF_FXS_LKP_PredecessorSnapshot__c,
        AXF_FXS_LKP_RateSource__c,
        AXF_FXS_EXI_ApplicationKey__c,
        CreatedById,
        CreatedDate
      FROM AXF_OBJ_FxApplicationSnapshot__c
      WHERE AXF_FXS_LKP_FinancialTransaction__c = :ftxId
      ORDER BY CreatedDate ASC
    ]) {
      out.entries.add(fxsEntry(fxs));
    }
    out.found = !out.entries.isEmpty();
    return out;
  }

  // ---- Leitores tipados por evidencia -------------------------------------------

  private static QueryResultDTO queryCas(Id recordId) {
    QueryResultDTO out = new QueryResultDTO();
    out.entries = new List<EvidenceEntryDTO>();
    List<AXF_OBJ_ContractApplicationSnapshot__c> rows = [
      SELECT
        Id,
        Name,
        AXF_CAS_PKL_State__c,
        AXF_CAS_NUM_Version__c,
        AXF_CAS_DT_OverriddenAt__c,
        AXF_CAS_TAL_OverrideReason__c,
        AXF_CAS_LKP_OverriddenByUser__c,
        AXF_CAS_LKP_PredecessorSnapshot__c,
        AXF_CAS_EXI_ApplicationIdentityHash__c,
        CreatedById,
        CreatedDate
      FROM AXF_OBJ_ContractApplicationSnapshot__c
      WHERE Id = :recordId
      LIMIT 1
    ];
    if (!rows.isEmpty()) {
      out.entries.add(casEntry(rows[0]));
      out.found = true;
    }
    return out;
  }

  private static EvidenceEntryDTO casEntry(
    AXF_OBJ_ContractApplicationSnapshot__c cas
  ) {
    EvidenceEntryDTO e = new EvidenceEntryDTO();
    e.evidenceObjectApi = 'AXF_OBJ_ContractApplicationSnapshot__c';
    e.eventKey = EVT_CONTRACT_APPLICATION;
    e.evidenceId = cas.Id;
    e.recordLabel = labelOf(cas.Name, cas.Id);
    e.actorUserId = cas.AXF_CAS_LKP_OverriddenByUser__c != null
      ? cas.AXF_CAS_LKP_OverriddenByUser__c
      : cas.CreatedById;
    e.actorName = resolveUserName(e.actorUserId);
    e.instant = cas.AXF_CAS_DT_OverriddenAt__c != null
      ? cas.AXF_CAS_DT_OverriddenAt__c
      : cas.CreatedDate;
    e.reasonLabel = String.isBlank(cas.AXF_CAS_TAL_OverrideReason__c)
      ? 'DEFAULTED (sem override)'
      : cas.AXF_CAS_TAL_OverrideReason__c;
    e.sourceLabel =
      'ApplicationIdentityHash=' + cas.AXF_CAS_EXI_ApplicationIdentityHash__c;
    e.priorStateLabel = cas.AXF_CAS_LKP_PredecessorSnapshot__c == null
      ? 'SEM_PREDECESSOR'
      : String.valueOf(cas.AXF_CAS_LKP_PredecessorSnapshot__c);
    e.stateLabel = cas.AXF_CAS_PKL_State__c + ' v' + cas.AXF_CAS_NUM_Version__c;
    e.coverage = COVERED_IMMUTABLE;
    return e;
  }

  private static QueryResultDTO queryFxs(Id recordId) {
    QueryResultDTO out = new QueryResultDTO();
    out.entries = new List<EvidenceEntryDTO>();
    List<AXF_OBJ_FxApplicationSnapshot__c> rows = [
      SELECT
        Id,
        Name,
        AXF_FXS_PKL_State__c,
        AXF_FXS_NUM_Version__c,
        AXF_FXS_DT_AppliedAt__c,
        AXF_FXS_PKL_Purpose__c,
        AXF_FXS_LKP_ActorUser__c,
        AXF_FXS_LKP_PredecessorSnapshot__c,
        AXF_FXS_LKP_RateSource__c,
        AXF_FXS_EXI_ApplicationKey__c,
        CreatedById,
        CreatedDate
      FROM AXF_OBJ_FxApplicationSnapshot__c
      WHERE Id = :recordId
      LIMIT 1
    ];
    if (!rows.isEmpty()) {
      out.entries.add(fxsEntry(rows[0]));
      out.found = true;
    }
    return out;
  }

  private static EvidenceEntryDTO fxsEntry(
    AXF_OBJ_FxApplicationSnapshot__c fxs
  ) {
    EvidenceEntryDTO e = new EvidenceEntryDTO();
    e.evidenceObjectApi = 'AXF_OBJ_FxApplicationSnapshot__c';
    e.eventKey = EVT_FX_MATERIAL_CONVERSION;
    e.evidenceId = fxs.Id;
    e.recordLabel = labelOf(fxs.Name, fxs.Id);
    e.actorUserId = fxs.AXF_FXS_LKP_ActorUser__c != null
      ? fxs.AXF_FXS_LKP_ActorUser__c
      : fxs.CreatedById;
    e.actorName = resolveUserName(e.actorUserId);
    e.instant = fxs.AXF_FXS_DT_AppliedAt__c != null
      ? fxs.AXF_FXS_DT_AppliedAt__c
      : fxs.CreatedDate;
    e.sourceLabel = fxs.AXF_FXS_LKP_RateSource__c == null
      ? 'SEM_COTACAO_REFERENCIA'
      : String.valueOf(fxs.AXF_FXS_LKP_RateSource__c);
    e.reasonLabel = fxs.AXF_FXS_PKL_Purpose__c;
    e.priorStateLabel = fxs.AXF_FXS_LKP_PredecessorSnapshot__c == null
      ? 'SEM_PREDECESSOR'
      : String.valueOf(fxs.AXF_FXS_LKP_PredecessorSnapshot__c);
    e.stateLabel = fxs.AXF_FXS_PKL_State__c + ' v' + fxs.AXF_FXS_NUM_Version__c;
    e.coverage = COVERED_IMMUTABLE;
    return e;
  }

  private static QueryResultDTO queryFxc(Id recordId) {
    QueryResultDTO out = new QueryResultDTO();
    out.entries = new List<EvidenceEntryDTO>();
    List<AXF_OBJ_FxSettlementCharge__c> rows = [
      SELECT
        Id,
        Name,
        AXF_FXC_NUM_Version__c,
        AXF_FXC_PKL_ChargeType__c,
        AXF_FXC_TXT_EvidenceHash__c,
        AXF_FXC_MDR_Settlement__c,
        CreatedById,
        CreatedDate
      FROM AXF_OBJ_FxSettlementCharge__c
      WHERE Id = :recordId
      LIMIT 1
    ];
    if (!rows.isEmpty()) {
      AXF_OBJ_FxSettlementCharge__c c = rows[0];
      EvidenceEntryDTO e = new EvidenceEntryDTO();
      e.evidenceObjectApi = 'AXF_OBJ_FxSettlementCharge__c';
      e.eventKey = EVT_FX_CHARGE;
      e.evidenceId = c.Id;
      e.recordLabel = labelOf(c.Name, c.Id);
      e.actorUserId = c.CreatedById;
      e.actorName = resolveUserName(c.CreatedById);
      e.instant = c.CreatedDate;
      e.reasonLabel = c.AXF_FXC_PKL_ChargeType__c;
      e.sourceLabel = String.isBlank(c.AXF_FXC_TXT_EvidenceHash__c)
        ? 'SEM_HASH'
        : 'EvidenceHash=' + c.AXF_FXC_TXT_EvidenceHash__c;
      e.priorStateLabel = 'SEM_PREDECESSOR';
      e.stateLabel = 'v' + c.AXF_FXC_NUM_Version__c;
      e.coverage = COVERED_IMMUTABLE;
      out.entries.add(e);
      out.found = true;
    }
    return out;
  }

  private static QueryResultDTO queryFxt(Id recordId) {
    QueryResultDTO out = new QueryResultDTO();
    out.entries = new List<EvidenceEntryDTO>();
    List<AXF_OBJ_FxSettlement__c> rows = [
      SELECT
        Id,
        Name,
        AXF_FXT_PKL_State__c,
        AXF_FXT_NUM_Version__c,
        AXF_FXT_TXT_Provider__c,
        AXF_FXT_EXI_SettlementKey__c,
        AXF_FXT_LKP_PredecessorSettlement__c,
        AXF_FXT_TXT_OperationKey__c,
        CreatedById,
        CreatedDate
      FROM AXF_OBJ_FxSettlement__c
      WHERE Id = :recordId
      LIMIT 1
    ];
    if (!rows.isEmpty()) {
      AXF_OBJ_FxSettlement__c s = rows[0];
      EvidenceEntryDTO e = new EvidenceEntryDTO();
      e.evidenceObjectApi = 'AXF_OBJ_FxSettlement__c';
      e.eventKey = EVT_FX_SETTLEMENT;
      e.evidenceId = s.Id;
      e.recordLabel = labelOf(s.Name, s.Id);
      e.actorUserId = s.CreatedById;
      e.actorName = resolveUserName(s.CreatedById);
      e.instant = s.CreatedDate;
      e.sourceLabel = String.isBlank(s.AXF_FXT_TXT_Provider__c)
        ? 'SEM_PROVIDER'
        : s.AXF_FXT_TXT_Provider__c;
      e.reasonLabel = 'OperationKey=' + s.AXF_FXT_TXT_OperationKey__c;
      e.priorStateLabel = s.AXF_FXT_LKP_PredecessorSettlement__c == null
        ? 'SEM_PREDECESSOR'
        : String.valueOf(s.AXF_FXT_LKP_PredecessorSettlement__c);
      e.stateLabel = s.AXF_FXT_PKL_State__c + ' v' + s.AXF_FXT_NUM_Version__c;
      e.coverage = COVERED_IMMUTABLE;
      out.entries.add(e);
      out.found = true;
    }
    return out;
  }

  private static QueryResultDTO queryExr(Id recordId) {
    QueryResultDTO out = new QueryResultDTO();
    out.entries = new List<EvidenceEntryDTO>();
    List<AXF_OBJ_ExchangeRate__c> rows = [
      SELECT
        Id,
        Name,
        AXF_EXR_TXT_Provider__c,
        AXF_EXR_TXT_BaseCurrency__c,
        AXF_EXR_TXT_QuoteCurrency__c,
        AXF_EXR_DT_EffectiveDateTime__c,
        AXF_EXR_EXI_RateKey__c,
        CreatedById,
        CreatedDate
      FROM AXF_OBJ_ExchangeRate__c
      WHERE Id = :recordId
      LIMIT 1
    ];
    if (!rows.isEmpty()) {
      AXF_OBJ_ExchangeRate__c r = rows[0];
      EvidenceEntryDTO e = new EvidenceEntryDTO();
      e.evidenceObjectApi = 'AXF_OBJ_ExchangeRate__c';
      e.eventKey = EVT_RATE_EVIDENCE;
      e.evidenceId = r.Id;
      e.recordLabel = labelOf(r.Name, r.Id);
      e.actorUserId = r.CreatedById;
      e.actorName = resolveUserName(r.CreatedById);
      e.instant = r.AXF_EXR_DT_EffectiveDateTime__c;
      e.sourceLabel = String.isBlank(r.AXF_EXR_TXT_Provider__c)
        ? 'SEM_PROVIDER'
        : r.AXF_EXR_TXT_Provider__c;
      e.reasonLabel = null;
      e.priorStateLabel = 'SEM_PREDECESSOR';
      e.stateLabel =
        r.AXF_EXR_TXT_BaseCurrency__c +
        '/' +
        r.AXF_EXR_TXT_QuoteCurrency__c;
      e.coverage = COVERED_NATIVE;
      out.entries.add(e);
      out.found = true;
    }
    return out;
  }

  // ---- Helpers -------------------------------------------------------------------

  private static String resolveUserName(Id userId) {
    if (userId == null) {
      return null;
    }
    List<User> users = [
      SELECT Name
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0].Name;
  }

  private static String labelOf(String name, Id id) {
    return String.isBlank(name) ? String.valueOf(id) : name;
  }

  private static CoverageRowDTO row(
    String key,
    String label,
    String coverage,
    String objectApi,
    String retentionDomain,
    String limitNote,
    Boolean actor,
    Boolean instant,
    Boolean source,
    Boolean reason,
    Boolean prior
  ) {
    CoverageRowDTO r = new CoverageRowDTO();
    r.eventKey = key;
    r.eventLabel = label;
    r.coverage = coverage;
    r.evidenceObjectApi = objectApi;
    r.retentionDomain = retentionDomain;
    r.limitNote = limitNote;
    r.actorAvailable = actor;
    r.instantAvailable = instant;
    r.sourceAvailable = source;
    r.reasonAvailable = reason;
    r.priorStateAvailable = prior;
    return r;
  }
}
