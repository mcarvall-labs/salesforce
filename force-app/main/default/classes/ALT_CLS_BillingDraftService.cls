/**
 * @description Servico de dominio do rascunho de cobranca (AXF-65, GBI-1..GBI-4, fechamento
 * billing 06/09/2026). Compoe um BillingDocument (OPEN) + BillingDocumentVersion (DRAFT) a partir
 * de lancamentos previstos (FinancialTransaction) e seus snapshots contratuais ACTIVE, com
 * alocacoes de WorkRecord aprovado.
 *
 * Regras:
 * - Uma versao so agrupa linhas compativeis por Contract + Counterparty + Account + moeda +
 *   periodo + tipo; qualquer incompatibilidade e explicada linha a linha e rejeita a operacao
 *   inteira (sem linha parcial, sem documento parcial).
 * - Linha referencia fontes tipadas (FTX + CAS); nunca ID opaco nem contrato corrente.
 * - Moeda diferente do documento = regra cambial indisponivel -> BLOCKED_FX, sem conversao.
 * - Soma das linhas conserva o total documental; alocacao por WorkRecord <= saldo aprovado.
 * - Idempotencia por ClientRequestId (mesma chave + mesmo payload = mesmo documento; payload
 *   divergente = CONFLICT). Atomicidade por savepoint.
 * - CRUD/FLS/sharing nativos (with sharing + USER_MODE); operacao multi-registro sem acesso a
 *   todas as partes e negada sem revelar existencia.
 */
public with sharing class ALT_CLS_BillingDraftService {
  public static final String LIFECYCLE_OPEN = 'OPEN';
  public static final String STATE_DRAFT = 'DRAFT';
  public static final Set<String> EFFECTIVE_STATES = new Set<String>{
    'DRAFT',
    'REVIEWED',
    'ISSUING',
    'ISSUED'
  };
  public static final Set<String> DOCUMENT_KINDS = new Set<String>{
    'GENERIC_INVOICE',
    'GENERIC_RECEIPT'
  };
  public static final String WORK_APPROVED = 'APPROVED';
  public static final Set<String> LINE_TYPES = new Set<String>{
    'MONTHLY',
    'HOURLY',
    'FIXED'
  };
  public static final Set<String> NON_BILLABLE_CONTRACTS = new Set<String>{
    'CANCELLED',
    'REPLACED'
  };
  /** Upper bound of lines per composition (keeps the fixed summary within its field size). */
  public static final Integer MAX_LINES = 200;
  /** Candidate listing window; the period filter keeps it far from being reached. */
  public static final Integer MAX_CANDIDATES = 500;

  // Codigos de incompatibilidade (explicados na UI por rotulo traduzido).
  public static final String R_NOT_ACCESSIBLE = 'NOT_ACCESSIBLE';
  public static final String R_CONTRACT_MISMATCH = 'CONTRACT_MISMATCH';
  public static final String R_COUNTERPARTY_MISMATCH = 'COUNTERPARTY_MISMATCH';
  public static final String R_ACCOUNT_MISMATCH = 'ACCOUNT_MISMATCH';
  public static final String R_CURRENCY_BLOCKED_FX = 'BLOCKED_FX';
  public static final String R_PERIOD_MISMATCH = 'PERIOD_MISMATCH';
  public static final String R_TYPE_MISMATCH = 'TYPE_MISMATCH';
  public static final String R_SNAPSHOT_MISSING = 'SNAPSHOT_MISSING';
  public static final String R_SNAPSHOT_STALE = 'SNAPSHOT_STALE';
  public static final String R_ALREADY_BILLED = 'ALREADY_BILLED';
  public static final String R_NOT_PLANNED = 'NOT_PLANNED';
  public static final String R_WORK_NOT_APPROVED = 'WORK_NOT_APPROVED';
  public static final String R_WORK_CONTRACT_MISMATCH = 'WORK_CONTRACT_MISMATCH';
  public static final String R_WORK_OVER_ALLOCATED = 'WORK_OVER_ALLOCATED';
  public static final String R_WORK_INVALID_QUANTITY = 'WORK_INVALID_QUANTITY';
  public static final String R_DUPLICATE_LINE = 'DUPLICATE_LINE';
  public static final String R_INVALID_AMOUNT = 'INVALID_AMOUNT';
  public static final String R_CONTRACT_NOT_BILLABLE = 'CONTRACT_NOT_BILLABLE';

  public class BillingDraftException extends Exception {
    public String code;
    public List<LineIssue> issues = new List<LineIssue>();
  }

  public class LineIssue {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public Id workRecordId;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public String detail;
  }

  public class WorkAllocationInput {
    @AuraEnabled
    public Id workRecordId;
    @AuraEnabled
    public Decimal quantity;
  }

  public class LineInput {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public Id snapshotId;
    @AuraEnabled
    public List<WorkAllocationInput> workAllocations;
  }

  public class ComposeInput {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public Id counterpartyId;
    @AuraEnabled
    public String documentKind;
    @AuraEnabled
    public String seriesKey;
    @AuraEnabled
    public Date periodStart;
    @AuraEnabled
    public Date periodEnd;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String clientRequestId;
    @AuraEnabled
    public List<LineInput> lines;
  }

  public class Candidate {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public Id snapshotId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Date serviceDate;
    @AuraEnabled
    public String lineType;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String snapshotName;
    @AuraEnabled
    public Boolean eligible;
    @AuraEnabled
    public List<String> reasons = new List<String>();
  }

  public class WorkRecordView {
    @AuraEnabled
    public Id workRecordId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal approvedQuantity;
    @AuraEnabled
    public Decimal allocatedQuantity;
    @AuraEnabled
    public Decimal remainingQuantity;
    @AuraEnabled
    public Decimal rate;
    @AuraEnabled
    public String currencyIso;
  }

  public class LineView {
    @AuraEnabled
    public Id lineId;
    @AuraEnabled
    public Integer lineNumber;
    @AuraEnabled
    public String lineType;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal quantity;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Date serviceDate;
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public String financialTransactionName;
    @AuraEnabled
    public Id snapshotId;
    @AuraEnabled
    public String snapshotName;
    @AuraEnabled
    public List<WorkAllocationView> workAllocations = new List<WorkAllocationView>();
  }

  public class WorkAllocationView {
    @AuraEnabled
    public Id workRecordId;
    @AuraEnabled
    public String workRecordName;
    @AuraEnabled
    public Decimal quantity;
    @AuraEnabled
    public Decimal amount;
  }

  public class DraftView {
    @AuraEnabled
    public Id documentId;
    @AuraEnabled
    public String documentName;
    @AuraEnabled
    public Id versionId;
    @AuraEnabled
    public Integer revision;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String lifecycle;
    @AuraEnabled
    public String presentationState;
    @AuraEnabled
    public String documentKind;
    @AuraEnabled
    public String seriesKey;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public String contractName;
    @AuraEnabled
    public Id counterpartyId;
    @AuraEnabled
    public String counterpartyName;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Date periodStart;
    @AuraEnabled
    public Date periodEnd;
    @AuraEnabled
    public Decimal totalAmount;
    @AuraEnabled
    public Decimal linesTotal;
    @AuraEnabled
    public Integer lineCount;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public String summary;
    @AuraEnabled
    public List<LineView> lines = new List<LineView>();
  }

  private class ContractFrame {
    AXF_OBJ_Contract__c contract;
    Account holder;
  }

  private class LineFrame {
    LineInput input;
    AXF_OBJ_FinancialTransaction__c fact;
    AXF_OBJ_ContractApplicationSnapshot__c snapshot;
    List<LineIssue> issues = new List<LineIssue>();
  }

  /**
   * @description Lista lancamentos do contrato dentro do periodo informado, avaliando a
   * compatibilidade de cada um contra o frame do documento (contrato, contraparte, titular,
   * moeda, periodo, tipo) e explicando cada incompatibilidade.
   */
  public List<Candidate> listCandidates(
    Id contractId,
    Date periodStart,
    Date periodEnd,
    String currencyIso
  ) {
    if ((periodStart == null) != (periodEnd == null)) {
      throw failure('INVALID_INPUT', new List<LineIssue>());
    }
    if (periodStart != null && periodEnd < periodStart) {
      throw failure('INVALID_INPUT', new List<LineIssue>());
    }
    ContractFrame frame = loadFrame(contractId);
    String docCurrency = String.isBlank(currencyIso)
      ? frame.contract.AXF_CTR_TXT_CurrencyIsoCode__c
      : currencyIso;
    if (String.isBlank(docCurrency)) {
      throw failure('INVALID_INPUT', new List<LineIssue>());
    }
    docCurrency = docCurrency.trim().toUpperCase();
    Date lower = periodStart == null
      ? Date.newInstance(1900, 1, 1)
      : periodStart;
    Date upper = periodEnd == null ? Date.newInstance(2999, 12, 31) : periodEnd;
    // Service date = DueDate, falling back to PurchaseDate; the period filter mirrors that.
    List<AXF_OBJ_FinancialTransaction__c> facts = [
      SELECT
        Id,
        Name,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_LKP_Contract__c,
        AXF_FTX_LKP_ContractApplicationSnapshot__c,
        AXF_FTX_LKP_ContractApplicationSnapshot__r.Name,
        AXF_FTX_LKP_ContractApplicationSnapshot__r.AXF_CAS_PKL_State__c,
        AXF_FTX_LKP_ContractApplicationSnapshot__r.AXF_CAS_PKL_RemunerationModel__c,
        AXF_FTX_LKP_ContractApplicationSnapshot__r.AXF_CAS_NUM_HoursQuantity__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Contract__c = :contractId
        AND ((AXF_FTX_DAT_DueDate__c >= :lower
        AND AXF_FTX_DAT_DueDate__c <= :upper)
        OR (AXF_FTX_DAT_DueDate__c = NULL
        AND AXF_FTX_DAT_PurchaseDate__c >= :lower
        AND AXF_FTX_DAT_PurchaseDate__c <= :upper))
      WITH USER_MODE
      ORDER BY AXF_FTX_DAT_DueDate__c, AXF_FTX_DAT_PurchaseDate__c, Name
      LIMIT :MAX_CANDIDATES
    ];
    Set<Id> billed = ALT_CLS_BillingIntegrity.billedFacts(
      new Map<Id, SObject>(facts).keySet(),
      EFFECTIVE_STATES
    );
    List<Candidate> result = new List<Candidate>();
    for (AXF_OBJ_FinancialTransaction__c fact : facts) {
      Candidate candidate = new Candidate();
      candidate.financialTransactionId = fact.Id;
      candidate.name = fact.Name;
      candidate.amount = fact.AXF_FTX_NUM_Magnitude__c;
      candidate.currencyIso = fact.AXF_FTX_TXT_CurrencyIsoCode__c;
      candidate.serviceDate = serviceDate(fact);
      candidate.direction = fact.AXF_FTX_PKL_Direction__c;
      candidate.snapshotId = fact.AXF_FTX_LKP_ContractApplicationSnapshot__c;
      candidate.snapshotName = fact.AXF_FTX_LKP_ContractApplicationSnapshot__r
        ?.Name;
      candidate.lineType = fact.AXF_FTX_LKP_ContractApplicationSnapshot__r
        ?.AXF_CAS_PKL_RemunerationModel__c;
      candidate.reasons = frameReasons(
        fact,
        frame,
        frame.contract.AXF_CTR_LKP_Counterparty__c,
        frame.contract.AXF_CTR_LKP_Account__c,
        docCurrency,
        periodStart,
        periodEnd,
        billed
      );
      candidate.eligible = candidate.reasons.isEmpty();
      result.add(candidate);
    }
    return result;
  }

  /** @description WorkRecords aprovados do contrato com saldo remanescente de alocacao. */
  public List<WorkRecordView> listApprovedWork(Id contractId) {
    loadFrame(contractId);
    List<AXF_OBJ_WorkRecord__c> records = [
      SELECT
        Id,
        Name,
        AXF_WR_TXT_Description__c,
        AXF_WR_NUM_Quantity__c,
        AXF_WR_CUR_Rate__c,
        AXF_WR_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_WorkRecord__c
      WHERE
        AXF_WR_LKP_Contract__c = :contractId
        AND AXF_WR_PKL_Status__c = :WORK_APPROVED
      WITH USER_MODE
      ORDER BY AXF_WR_DAT_StartDate__c, Name
      LIMIT :MAX_CANDIDATES
    ];
    Map<Id, Decimal> allocated = ALT_CLS_BillingIntegrity.allocatedByWorkRecord(
      new Map<Id, SObject>(records).keySet(),
      EFFECTIVE_STATES
    );
    List<WorkRecordView> result = new List<WorkRecordView>();
    for (AXF_OBJ_WorkRecord__c record : records) {
      WorkRecordView view = new WorkRecordView();
      view.workRecordId = record.Id;
      view.name = record.Name;
      view.description = record.AXF_WR_TXT_Description__c;
      view.approvedQuantity = nz(record.AXF_WR_NUM_Quantity__c);
      view.allocatedQuantity = nz(allocated.get(record.Id));
      view.remainingQuantity = view.approvedQuantity - view.allocatedQuantity;
      view.rate = record.AXF_WR_CUR_Rate__c;
      view.currencyIso = record.AXF_WR_TXT_CurrencyIsoCode__c;
      result.add(view);
    }
    return result;
  }

  /**
   * @description Compoe o rascunho atomicamente. Rejeita a operacao inteira com todas as
   * incompatibilidades explicadas; idempotente por clientRequestId.
   */
  public Id compose(ComposeInput input) {
    validateInput(input);
    String requestHash = requestHash(input);
    AXF_OBJ_BillingDocument__c existing = findByRequest(input.clientRequestId);
    if (existing != null) {
      if (existingRequestHash(existing.Id) == requestHash) {
        return existing.Id;
      }
      throw failure('CONFLICT', new List<LineIssue>());
    }
    ContractFrame frame = loadFrame(input.contractId);
    if (frame.contract.AXF_CTR_LKP_Account__c != input.accountId) {
      throw failure(R_ACCOUNT_MISMATCH, new List<LineIssue>());
    }
    if (frame.contract.AXF_CTR_LKP_Counterparty__c != input.counterpartyId) {
      throw failure(R_COUNTERPARTY_MISMATCH, new List<LineIssue>());
    }
    String documentKey = documentKey(input);
    if (
      ![
          SELECT Id
          FROM AXF_OBJ_BillingDocument__c
          WHERE AXF_BDO_EXI_DocumentKey__c = :documentKey
          WITH USER_MODE
          LIMIT 1
        ]
        .isEmpty()
    ) {
      throw failure('DOCUMENT_EXISTS', new List<LineIssue>());
    }

    List<LineFrame> frames = evaluateLines(input, frame);
    List<LineIssue> issues = new List<LineIssue>();
    for (LineFrame line : frames) {
      issues.addAll(line.issues);
    }
    if (!issues.isEmpty()) {
      throw failure('INCOMPATIBLE_LINES', issues);
    }

    Savepoint point = Database.setSavepoint();
    try {
      ALT_CLS_BillingGuard.beginWrite();
      AXF_OBJ_BillingDocument__c document = new AXF_OBJ_BillingDocument__c(
        AXF_BDO_LKP_Account__c = input.accountId,
        AXF_BDO_LKP_Contract__c = input.contractId,
        AXF_BDO_LKP_Counterparty__c = input.counterpartyId,
        AXF_BDO_PKL_DocumentKind__c = input.documentKind,
        AXF_BDO_PKL_Lifecycle__c = LIFECYCLE_OPEN,
        AXF_BDO_TXT_SeriesKey__c = input.seriesKey,
        AXF_BDO_TXT_CurrencyIsoCode__c = input.currencyIso,
        AXF_BDO_DAT_PeriodStart__c = input.periodStart,
        AXF_BDO_DAT_PeriodEnd__c = input.periodEnd,
        AXF_BDO_EXI_DocumentKey__c = documentKey,
        AXF_BDO_EXI_ClientRequestId__c = input.clientRequestId,
        AXF_BDO_NUM_Version__c = 1,
        OwnerId = frame.holder.OwnerId
      );
      Database.insert(document, AccessLevel.USER_MODE);

      Decimal total = 0;
      for (LineFrame line : frames) {
        total += line.fact.AXF_FTX_NUM_Magnitude__c.setScale(
          2,
          System.RoundingMode.HALF_UP
        );
      }
      AXF_OBJ_BillingDocumentVersion__c version = new AXF_OBJ_BillingDocumentVersion__c(
        AXF_BDV_LKP_BillingDocument__c = document.Id,
        AXF_BDV_NUM_Revision__c = 1,
        AXF_BDV_PKL_State__c = STATE_DRAFT,
        AXF_BDV_EXI_VersionKey__c = document.Id + ':1',
        AXF_BDV_CUR_TotalAmount__c = total.setScale(2),
        AXF_BDV_TXT_CurrencyIsoCode__c = input.currencyIso,
        AXF_BDV_TAL_Summary__c = summary(
          input,
          frame,
          frames,
          total,
          requestHash
        ),
        AXF_BDV_NUM_Version__c = 1,
        OwnerId = frame.holder.OwnerId
      );
      Database.insert(version, AccessLevel.USER_MODE);

      List<AXF_OBJ_BillingDocumentLine__c> lines = new List<AXF_OBJ_BillingDocumentLine__c>();
      Integer sequence = 0;
      for (LineFrame line : frames) {
        sequence++;
        lines.add(
          new AXF_OBJ_BillingDocumentLine__c(
            AXF_BDL_MDR_DocumentVersion__c = version.Id,
            AXF_BDL_LKP_FinancialTransaction__c = line.fact.Id,
            AXF_BDL_LKP_ContractApplicationSnapshot__c = line.snapshot.Id,
            AXF_BDL_NUM_LineNumber__c = sequence,
            AXF_BDL_EXI_LineKey__c = version.Id + ':' + sequence,
            AXF_BDL_PKL_LineType__c = line.snapshot.AXF_CAS_PKL_RemunerationModel__c,
            AXF_BDL_TXT_Description__c = lineDescription(line),
            AXF_BDL_NUM_Quantity__c = lineQuantity(line),
            AXF_BDL_CUR_UnitPrice__c = unitPrice(line),
            AXF_BDL_CUR_Amount__c = line.fact.AXF_FTX_NUM_Magnitude__c.setScale(
              2,
              System.RoundingMode.HALF_UP
            ),
            AXF_BDL_TXT_CurrencyIsoCode__c = line.fact.AXF_FTX_TXT_CurrencyIsoCode__c,
            AXF_BDL_DAT_ServiceDate__c = serviceDate(line.fact)
          )
        );
      }
      Database.insert(lines, AccessLevel.USER_MODE);

      List<AXF_OBJ_BillingDocumentWorkAllocation__c> allocations = new List<AXF_OBJ_BillingDocumentWorkAllocation__c>();
      Map<Id, AXF_OBJ_WorkRecord__c> work = approvedWork(input, frame);
      for (Integer i = 0; i < frames.size(); i++) {
        LineFrame line = frames[i];
        if (line.input.workAllocations == null) {
          continue;
        }
        for (WorkAllocationInput allocation : line.input.workAllocations) {
          AXF_OBJ_WorkRecord__c record = work.get(allocation.workRecordId);
          Decimal amount = record.AXF_WR_CUR_Rate__c == null
            ? null
            : (allocation.quantity * record.AXF_WR_CUR_Rate__c)
                .setScale(2, System.RoundingMode.HALF_UP);
          allocations.add(
            new AXF_OBJ_BillingDocumentWorkAllocation__c(
              AXF_BWA_MDR_Line__c = lines[i].Id,
              AXF_BWA_LKP_WorkRecord__c = record.Id,
              AXF_BWA_NUM_AllocatedQuantity__c = allocation.quantity,
              AXF_BWA_CUR_AllocatedAmount__c = amount,
              AXF_BWA_EXI_AllocationKey__c = lines[i].Id + ':' + record.Id
            )
          );
        }
      }
      if (!allocations.isEmpty()) {
        Database.insert(allocations, AccessLevel.USER_MODE);
      }
      assertConservation(version.Id, total);
      grantComposerAccess(document.Id, version.Id, frame.holder.OwnerId);
      return document.Id;
    } catch (DmlException failure) {
      Database.rollback(point);
      throw translateDml(failure);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    } finally {
      ALT_CLS_BillingGuard.endWrite();
    }
  }

  /** @description Leitura do rascunho (versao mais recente) com linhas, origem, snapshots, totais e resumo fixo. */
  public DraftView read(Id documentId) {
    List<AXF_OBJ_BillingDocument__c> documents = [
      SELECT
        Id,
        Name,
        AXF_BDO_PKL_Lifecycle__c,
        AXF_BDO_FOR_PresentationState__c,
        AXF_BDO_PKL_DocumentKind__c,
        AXF_BDO_TXT_SeriesKey__c,
        AXF_BDO_LKP_Account__c,
        AXF_BDO_LKP_Account__r.Name,
        AXF_BDO_LKP_Contract__c,
        AXF_BDO_LKP_Contract__r.Name,
        AXF_BDO_LKP_Contract__r.AXF_CTR_TXT_Title__c,
        AXF_BDO_LKP_Counterparty__c,
        AXF_BDO_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c,
        AXF_BDO_TXT_CurrencyIsoCode__c,
        AXF_BDO_DAT_PeriodStart__c,
        AXF_BDO_DAT_PeriodEnd__c,
        AXF_BDO_NUM_Version__c
      FROM AXF_OBJ_BillingDocument__c
      WHERE Id = :documentId
      WITH USER_MODE
      LIMIT 1
    ];
    if (documents.isEmpty()) {
      throw failure(R_NOT_ACCESSIBLE, new List<LineIssue>());
    }
    AXF_OBJ_BillingDocument__c document = documents[0];
    List<AXF_OBJ_BillingDocumentVersion__c> versions = [
      SELECT
        Id,
        AXF_BDV_NUM_Revision__c,
        AXF_BDV_PKL_State__c,
        AXF_BDV_CUR_TotalAmount__c,
        AXF_BDV_CUR_LinesTotal__c,
        AXF_BDV_NUM_LineCount__c,
        AXF_BDV_TAL_Summary__c,
        (
          SELECT
            Id,
            AXF_BDL_NUM_LineNumber__c,
            AXF_BDL_PKL_LineType__c,
            AXF_BDL_TXT_Description__c,
            AXF_BDL_NUM_Quantity__c,
            AXF_BDL_CUR_Amount__c,
            AXF_BDL_TXT_CurrencyIsoCode__c,
            AXF_BDL_DAT_ServiceDate__c,
            AXF_BDL_LKP_FinancialTransaction__c,
            AXF_BDL_LKP_FinancialTransaction__r.Name,
            AXF_BDL_LKP_ContractApplicationSnapshot__c,
            AXF_BDL_LKP_ContractApplicationSnapshot__r.Name
          FROM AXF_REL_Lines__r
          ORDER BY AXF_BDL_NUM_LineNumber__c
        )
      FROM AXF_OBJ_BillingDocumentVersion__c
      WHERE AXF_BDV_LKP_BillingDocument__c = :documentId
      WITH USER_MODE
      ORDER BY AXF_BDV_NUM_Revision__c DESC
      LIMIT 1
    ];
    DraftView view = new DraftView();
    view.documentId = document.Id;
    view.documentName = document.Name;
    view.lifecycle = document.AXF_BDO_PKL_Lifecycle__c;
    view.presentationState = document.AXF_BDO_FOR_PresentationState__c;
    view.documentKind = document.AXF_BDO_PKL_DocumentKind__c;
    view.seriesKey = document.AXF_BDO_TXT_SeriesKey__c;
    view.accountId = document.AXF_BDO_LKP_Account__c;
    view.accountName = document.AXF_BDO_LKP_Account__r?.Name;
    view.contractId = document.AXF_BDO_LKP_Contract__c;
    view.contractName = String.isBlank(
        document.AXF_BDO_LKP_Contract__r?.AXF_CTR_TXT_Title__c
      )
      ? document.AXF_BDO_LKP_Contract__r?.Name
      : document.AXF_BDO_LKP_Contract__r.AXF_CTR_TXT_Title__c;
    view.counterpartyId = document.AXF_BDO_LKP_Counterparty__c;
    view.counterpartyName = document.AXF_BDO_LKP_Counterparty__r
      ?.AXF_CPTY_TXT_DisplayName__c;
    view.currencyIso = document.AXF_BDO_TXT_CurrencyIsoCode__c;
    view.periodStart = document.AXF_BDO_DAT_PeriodStart__c;
    view.periodEnd = document.AXF_BDO_DAT_PeriodEnd__c;
    view.version = document.AXF_BDO_NUM_Version__c;
    if (versions.isEmpty()) {
      return view;
    }
    AXF_OBJ_BillingDocumentVersion__c version = versions[0];
    view.versionId = version.Id;
    view.revision = Integer.valueOf(version.AXF_BDV_NUM_Revision__c);
    view.state = version.AXF_BDV_PKL_State__c;
    view.totalAmount = version.AXF_BDV_CUR_TotalAmount__c;
    view.linesTotal = version.AXF_BDV_CUR_LinesTotal__c;
    view.lineCount = Integer.valueOf(nz(version.AXF_BDV_NUM_LineCount__c));
    view.summary = version.AXF_BDV_TAL_Summary__c;
    Map<Id, LineView> byLine = new Map<Id, LineView>();
    for (AXF_OBJ_BillingDocumentLine__c line : version.AXF_REL_Lines__r) {
      LineView item = new LineView();
      item.lineId = line.Id;
      item.lineNumber = Integer.valueOf(line.AXF_BDL_NUM_LineNumber__c);
      item.lineType = line.AXF_BDL_PKL_LineType__c;
      item.description = line.AXF_BDL_TXT_Description__c;
      item.quantity = line.AXF_BDL_NUM_Quantity__c;
      item.amount = line.AXF_BDL_CUR_Amount__c;
      item.currencyIso = line.AXF_BDL_TXT_CurrencyIsoCode__c;
      item.serviceDate = line.AXF_BDL_DAT_ServiceDate__c;
      item.financialTransactionId = line.AXF_BDL_LKP_FinancialTransaction__c;
      item.financialTransactionName = line.AXF_BDL_LKP_FinancialTransaction__r
        ?.Name;
      item.snapshotId = line.AXF_BDL_LKP_ContractApplicationSnapshot__c;
      item.snapshotName = line.AXF_BDL_LKP_ContractApplicationSnapshot__r?.Name;
      byLine.put(line.Id, item);
      view.lines.add(item);
    }
    for (AXF_OBJ_BillingDocumentWorkAllocation__c allocation : [
      SELECT
        AXF_BWA_MDR_Line__c,
        AXF_BWA_LKP_WorkRecord__c,
        AXF_BWA_LKP_WorkRecord__r.Name,
        AXF_BWA_NUM_AllocatedQuantity__c,
        AXF_BWA_CUR_AllocatedAmount__c
      FROM AXF_OBJ_BillingDocumentWorkAllocation__c
      WHERE AXF_BWA_MDR_Line__c IN :byLine.keySet()
      WITH USER_MODE
      ORDER BY Name
    ]) {
      WorkAllocationView item = new WorkAllocationView();
      item.workRecordId = allocation.AXF_BWA_LKP_WorkRecord__c;
      item.workRecordName = allocation.AXF_BWA_LKP_WorkRecord__r?.Name;
      item.quantity = allocation.AXF_BWA_NUM_AllocatedQuantity__c;
      item.amount = allocation.AXF_BWA_CUR_AllocatedAmount__c;
      byLine.get(allocation.AXF_BWA_MDR_Line__c).workAllocations.add(item);
    }
    return view;
  }

  // ------------------------------------------------------------------ validation

  private void validateInput(ComposeInput input) {
    if (
      input == null ||
      input.accountId == null ||
      input.contractId == null ||
      input.counterpartyId == null ||
      String.isBlank(input.seriesKey) ||
      String.isBlank(input.currencyIso) ||
      input.periodStart == null ||
      input.periodEnd == null ||
      input.periodEnd < input.periodStart ||
      String.isBlank(input.clientRequestId) ||
      input.lines == null ||
      input.lines.isEmpty()
    ) {
      throw failure('INVALID_INPUT', new List<LineIssue>());
    }
    if (String.isBlank(input.documentKind)) {
      input.documentKind = 'GENERIC_INVOICE';
    }
    if (!DOCUMENT_KINDS.contains(input.documentKind)) {
      throw failure('INVALID_INPUT', new List<LineIssue>());
    }
    if (input.lines.size() > MAX_LINES) {
      throw failure('INVALID_INPUT', new List<LineIssue>());
    }
    input.currencyIso = input.currencyIso.trim().toUpperCase();
    if (!Pattern.matches('[A-Z]{3}', input.currencyIso)) {
      throw failure('INVALID_INPUT', new List<LineIssue>());
    }
    input.seriesKey = input.seriesKey.trim();
  }

  private ContractFrame loadFrame(Id contractId) {
    if (contractId == null) {
      throw failure('INVALID_INPUT', new List<LineIssue>());
    }
    List<AXF_OBJ_Contract__c> contracts = [
      SELECT
        Id,
        Name,
        AXF_CTR_TXT_Title__c,
        AXF_CTR_LKP_Account__c,
        AXF_CTR_LKP_Counterparty__c,
        AXF_CTR_TXT_CurrencyIsoCode__c,
        AXF_CTR_PKL_Lifecycle__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
      WITH USER_MODE
      LIMIT 1
    ];
    if (contracts.isEmpty()) {
      throw failure(R_NOT_ACCESSIBLE, new List<LineIssue>());
    }
    if (
      NON_BILLABLE_CONTRACTS.contains(contracts[0].AXF_CTR_PKL_Lifecycle__c)
    ) {
      throw failure(R_CONTRACT_NOT_BILLABLE, new List<LineIssue>());
    }
    if (contracts[0].AXF_CTR_LKP_Counterparty__c == null) {
      throw failure(R_COUNTERPARTY_MISMATCH, new List<LineIssue>());
    }
    List<Account> holders = [
      SELECT Id, Name, OwnerId
      FROM Account
      WHERE Id = :contracts[0].AXF_CTR_LKP_Account__c
      WITH USER_MODE
      LIMIT 1
    ];
    if (holders.isEmpty()) {
      throw failure(R_NOT_ACCESSIBLE, new List<LineIssue>());
    }
    ContractFrame frame = new ContractFrame();
    frame.contract = contracts[0];
    frame.holder = holders[0];
    return frame;
  }

  private List<LineFrame> evaluateLines(
    ComposeInput input,
    ContractFrame frame
  ) {
    Set<Id> factIds = new Set<Id>();
    Set<Id> workIds = new Set<Id>();
    for (LineInput line : input.lines) {
      if (line == null || line.financialTransactionId == null) {
        throw failure('INVALID_INPUT', new List<LineIssue>());
      }
      factIds.add(line.financialTransactionId);
      if (line.workAllocations != null) {
        for (WorkAllocationInput allocation : line.workAllocations) {
          if (allocation == null || allocation.workRecordId == null) {
            throw failure('INVALID_INPUT', new List<LineIssue>());
          }
          workIds.add(allocation.workRecordId);
        }
      }
    }
    Map<Id, AXF_OBJ_FinancialTransaction__c> facts = new Map<Id, AXF_OBJ_FinancialTransaction__c>(
      [
        SELECT
          Id,
          Name,
          AXF_FTX_NUM_Magnitude__c,
          AXF_FTX_TXT_CurrencyIsoCode__c,
          AXF_FTX_DAT_DueDate__c,
          AXF_FTX_DAT_PurchaseDate__c,
          AXF_FTX_PKL_Direction__c,
          AXF_FTX_PKL_PlanKind__c,
          AXF_FTX_PKL_Status__c,
          AXF_FTX_LKP_Account__c,
          AXF_FTX_LKP_Contract__c,
          AXF_FTX_LKP_ContractApplicationSnapshot__c,
          AXF_FTX_LKP_ContractApplicationSnapshot__r.Name,
          AXF_FTX_LKP_ContractApplicationSnapshot__r.AXF_CAS_PKL_State__c,
          AXF_FTX_LKP_ContractApplicationSnapshot__r.AXF_CAS_PKL_RemunerationModel__c,
          AXF_FTX_LKP_ContractApplicationSnapshot__r.AXF_CAS_NUM_HoursQuantity__c,
          AXF_FTX_LKP_ContractApplicationSnapshot__r.AXF_CAS_CUR_AppliedAmount__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id IN :factIds
        WITH USER_MODE
      ]
    );
    lockSources(facts.keySet(), workIds);
    Set<Id> billed = ALT_CLS_BillingIntegrity.billedFacts(
      factIds,
      EFFECTIVE_STATES
    );
    Map<Id, AXF_OBJ_WorkRecord__c> work = approvedWork(input, frame);
    Map<Id, Decimal> allocated = ALT_CLS_BillingIntegrity.allocatedByWorkRecord(
      workIds,
      EFFECTIVE_STATES
    );
    Map<Id, Decimal> requested = new Map<Id, Decimal>();
    Set<Id> seen = new Set<Id>();
    String lineType;
    List<LineFrame> frames = new List<LineFrame>();
    for (LineInput line : input.lines) {
      LineFrame item = new LineFrame();
      item.input = line;
      item.fact = facts.get(line.financialTransactionId);
      frames.add(item);
      if (!seen.add(line.financialTransactionId)) {
        item.issues.add(
          issue(line.financialTransactionId, null, R_DUPLICATE_LINE, null)
        );
        continue;
      }
      if (item.fact == null) {
        item.issues.add(
          issue(line.financialTransactionId, null, R_NOT_ACCESSIBLE, null)
        );
        continue;
      }
      for (
        String reason : frameReasons(
          item.fact,
          frame,
          input.counterpartyId,
          input.accountId,
          input.currencyIso,
          input.periodStart,
          input.periodEnd,
          billed
        )
      ) {
        item.issues.add(issue(item.fact.Id, null, reason, null));
      }
      // The client must name the snapshot it reviewed; a missing or different one is stale.
      if (
        line.snapshotId == null ||
        line.snapshotId != item.fact.AXF_FTX_LKP_ContractApplicationSnapshot__c
      ) {
        item.issues.add(issue(item.fact.Id, null, R_SNAPSHOT_STALE, null));
      }
      item.snapshot = item.fact.AXF_FTX_LKP_ContractApplicationSnapshot__r;
      String model = item.snapshot?.AXF_CAS_PKL_RemunerationModel__c;
      if (item.snapshot != null && !LINE_TYPES.contains(model)) {
        item.issues.add(issue(item.fact.Id, null, R_TYPE_MISMATCH, model));
      } else if (model != null) {
        if (lineType == null) {
          lineType = model;
        } else if (lineType != model) {
          item.issues.add(issue(item.fact.Id, null, R_TYPE_MISMATCH, model));
        }
      }
      if (line.workAllocations == null) {
        continue;
      }
      Set<Id> perLine = new Set<Id>();
      for (WorkAllocationInput allocation : line.workAllocations) {
        if (!perLine.add(allocation.workRecordId)) {
          item.issues.add(
            issue(item.fact.Id, allocation.workRecordId, R_DUPLICATE_LINE, null)
          );
          continue;
        }
        AXF_OBJ_WorkRecord__c record = work.get(allocation.workRecordId);
        if (record == null || record.AXF_WR_PKL_Status__c != WORK_APPROVED) {
          item.issues.add(
            issue(
              item.fact.Id,
              allocation.workRecordId,
              R_WORK_NOT_APPROVED,
              null
            )
          );
          continue;
        }
        if (record.AXF_WR_LKP_Contract__c != frame.contract.Id) {
          item.issues.add(
            issue(item.fact.Id, record.Id, R_WORK_CONTRACT_MISMATCH, null)
          );
          continue;
        }
        if (
          record.AXF_WR_TXT_CurrencyIsoCode__c != null &&
          record.AXF_WR_TXT_CurrencyIsoCode__c.toUpperCase() !=
          input.currencyIso
        ) {
          item.issues.add(
            issue(
              item.fact.Id,
              record.Id,
              R_CURRENCY_BLOCKED_FX,
              record.AXF_WR_TXT_CurrencyIsoCode__c
            )
          );
          continue;
        }
        if (allocation.quantity == null || allocation.quantity <= 0) {
          item.issues.add(
            issue(item.fact.Id, record.Id, R_WORK_INVALID_QUANTITY, null)
          );
          continue;
        }
        Decimal used =
          nz(allocated.get(record.Id)) +
          nz(requested.get(record.Id)) +
          allocation.quantity;
        requested.put(
          record.Id,
          nz(requested.get(record.Id)) + allocation.quantity
        );
        if (used > nz(record.AXF_WR_NUM_Quantity__c)) {
          item.issues.add(
            issue(
              item.fact.Id,
              record.Id,
              R_WORK_OVER_ALLOCATED,
              String.valueOf(
                nz(record.AXF_WR_NUM_Quantity__c) - nz(allocated.get(record.Id))
              )
            )
          );
        }
      }
    }
    return frames;
  }

  private List<String> frameReasons(
    AXF_OBJ_FinancialTransaction__c fact,
    ContractFrame frame,
    Id counterpartyId,
    Id accountId,
    String currencyIso,
    Date periodStart,
    Date periodEnd,
    Set<Id> billed
  ) {
    List<String> reasons = new List<String>();
    if (fact.AXF_FTX_LKP_Contract__c != frame.contract.Id) {
      reasons.add(R_CONTRACT_MISMATCH);
    }
    if (frame.contract.AXF_CTR_LKP_Counterparty__c != counterpartyId) {
      reasons.add(R_COUNTERPARTY_MISMATCH);
    }
    if (
      fact.AXF_FTX_LKP_Account__c != accountId ||
      frame.contract.AXF_CTR_LKP_Account__c != accountId
    ) {
      reasons.add(R_ACCOUNT_MISMATCH);
    }
    if (
      fact.AXF_FTX_TXT_CurrencyIsoCode__c == null ||
      fact.AXF_FTX_TXT_CurrencyIsoCode__c.toUpperCase() != currencyIso
    ) {
      reasons.add(R_CURRENCY_BLOCKED_FX);
    }
    Date effective = serviceDate(fact);
    if (
      periodStart != null &&
      periodEnd != null &&
      (effective == null ||
      effective < periodStart ||
      effective > periodEnd)
    ) {
      reasons.add(R_PERIOD_MISMATCH);
    }
    if (
      fact.AXF_FTX_NUM_Magnitude__c == null ||
      fact.AXF_FTX_NUM_Magnitude__c <= 0
    ) {
      reasons.add(R_INVALID_AMOUNT);
    }
    if (
      (fact.AXF_FTX_PKL_PlanKind__c != null &&
      fact.AXF_FTX_PKL_PlanKind__c != 'PLANNED') ||
      (fact.AXF_FTX_PKL_Status__c != null &&
      fact.AXF_FTX_PKL_Status__c != 'PLANNED')
    ) {
      reasons.add(R_NOT_PLANNED);
    }
    if (fact.AXF_FTX_LKP_ContractApplicationSnapshot__c == null) {
      reasons.add(R_SNAPSHOT_MISSING);
    } else if (
      fact.AXF_FTX_LKP_ContractApplicationSnapshot__r.AXF_CAS_PKL_State__c !=
      ALT_CLS_ContractSnapshotService.STATE_ACTIVE
    ) {
      reasons.add(R_SNAPSHOT_STALE);
    }
    if (billed.contains(fact.Id)) {
      reasons.add(R_ALREADY_BILLED);
    }
    return reasons;
  }

  /** Row locks on the sources being billed so concurrent compositions serialize (lock order: facts, then work). */
  private static void lockSources(Set<Id> factIds, Set<Id> workIds) {
    if (!factIds.isEmpty()) {
      List<AXF_OBJ_FinancialTransaction__c> locked = [
        SELECT Id
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id IN :factIds
        FOR UPDATE
      ];
    }
    if (!workIds.isEmpty()) {
      List<AXF_OBJ_WorkRecord__c> locked = [
        SELECT Id
        FROM AXF_OBJ_WorkRecord__c
        WHERE Id IN :workIds
        FOR UPDATE
      ];
    }
  }

  private Map<Id, AXF_OBJ_WorkRecord__c> approvedWork(
    ComposeInput input,
    ContractFrame frame
  ) {
    Set<Id> ids = new Set<Id>();
    for (LineInput line : input.lines) {
      if (line.workAllocations != null) {
        for (WorkAllocationInput allocation : line.workAllocations) {
          ids.add(allocation.workRecordId);
        }
      }
    }
    if (ids.isEmpty()) {
      return new Map<Id, AXF_OBJ_WorkRecord__c>();
    }
    // Status and contract are checked per allocation so each mismatch gets its own reason.
    return new Map<Id, AXF_OBJ_WorkRecord__c>(
      [
        SELECT
          Id,
          AXF_WR_NUM_Quantity__c,
          AXF_WR_CUR_Rate__c,
          AXF_WR_PKL_Status__c,
          AXF_WR_LKP_Contract__c,
          AXF_WR_TXT_CurrencyIsoCode__c
        FROM AXF_OBJ_WorkRecord__c
        WHERE Id IN :ids
        WITH USER_MODE
      ]
    );
  }

  private void assertConservation(Id versionId, Decimal total) {
    AXF_OBJ_BillingDocumentVersion__c version = [
      SELECT AXF_BDV_CUR_LinesTotal__c, AXF_BDV_CUR_TotalAmount__c
      FROM AXF_OBJ_BillingDocumentVersion__c
      WHERE Id = :versionId
      WITH USER_MODE
    ];
    if (
      nz(version.AXF_BDV_CUR_LinesTotal__c).setScale(2) !=
      nz(version.AXF_BDV_CUR_TotalAmount__c).setScale(2)
    ) {
      throw failure('TOTAL_NOT_CONSERVED', new List<LineIssue>());
    }
  }

  // ------------------------------------------------------------------ helpers

  private AXF_OBJ_BillingDocument__c findByRequest(String clientRequestId) {
    List<AXF_OBJ_BillingDocument__c> rows = [
      SELECT Id
      FROM AXF_OBJ_BillingDocument__c
      WHERE AXF_BDO_EXI_ClientRequestId__c = :clientRequestId
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private String existingRequestHash(Id documentId) {
    for (AXF_OBJ_BillingDocumentVersion__c version : [
      SELECT AXF_BDV_TAL_Summary__c
      FROM AXF_OBJ_BillingDocumentVersion__c
      WHERE AXF_BDV_LKP_BillingDocument__c = :documentId
      WITH USER_MODE
      ORDER BY AXF_BDV_NUM_Revision__c ASC
      LIMIT 1
    ]) {
      if (String.isBlank(version.AXF_BDV_TAL_Summary__c)) {
        return null;
      }
      try {
        Map<String, Object> summary = (Map<String, Object>) JSON.deserializeUntyped(
          version.AXF_BDV_TAL_Summary__c
        );
        return (String) summary.get('requestHash');
      } catch (Exception malformed) {
        return null;
      }
    }
    return null;
  }

  private String requestHash(ComposeInput input) {
    List<String> parts = new List<String>{
      String.valueOf(input.accountId),
      String.valueOf(input.contractId),
      String.valueOf(input.counterpartyId),
      input.documentKind,
      input.seriesKey,
      String.valueOf(input.periodStart),
      String.valueOf(input.periodEnd),
      input.currencyIso
    };
    List<String> lineParts = new List<String>();
    for (LineInput line : input.lines) {
      String part =
        String.valueOf(line.financialTransactionId) +
        '/' +
        String.valueOf(line.snapshotId);
      if (line.workAllocations != null) {
        List<String> allocationParts = new List<String>();
        for (WorkAllocationInput allocation : line.workAllocations) {
          allocationParts.add(
            allocation.workRecordId + '=' + allocation.quantity
          );
        }
        allocationParts.sort();
        part += '/' + String.join(allocationParts, '/');
      }
      lineParts.add(part);
    }
    // Same content in a different order is the same request.
    lineParts.sort();
    parts.addAll(lineParts);
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(String.join(parts, '|')))
    );
  }

  private String documentKey(ComposeInput input) {
    return String.join(
      new List<String>{
        String.valueOf(input.accountId),
        String.valueOf(input.contractId),
        input.documentKind,
        input.seriesKey
      },
      '|'
    );
  }

  private String summary(
    ComposeInput input,
    ContractFrame frame,
    List<LineFrame> frames,
    Decimal total,
    String requestHash
  ) {
    List<Object> origins = new List<Object>();
    for (LineFrame line : frames) {
      origins.add(
        new Map<String, Object>{
          'financialTransaction' => line.fact.Name,
          'snapshot' => line.snapshot.Name,
          'amount' => line.fact.AXF_FTX_NUM_Magnitude__c,
          'serviceDate' => String.valueOf(serviceDate(line.fact))
        }
      );
    }
    return JSON.serialize(
      new Map<String, Object>{
        'contract' => frame.contract.Name,
        'counterpartyId' => input.counterpartyId,
        'accountId' => input.accountId,
        'documentKind' => input.documentKind,
        'seriesKey' => input.seriesKey,
        'currencyIso' => input.currencyIso,
        'periodStart' => String.valueOf(input.periodStart),
        'periodEnd' => String.valueOf(input.periodEnd),
        'lineCount' => frames.size(),
        'total' => total.setScale(2),
        'origins' => origins,
        'requestHash' => requestHash
      }
    );
  }

  private static Date serviceDate(AXF_OBJ_FinancialTransaction__c fact) {
    return fact.AXF_FTX_DAT_DueDate__c != null
      ? fact.AXF_FTX_DAT_DueDate__c
      : fact.AXF_FTX_DAT_PurchaseDate__c;
  }

  private static String lineDescription(LineFrame line) {
    return (line.snapshot.AXF_CAS_PKL_RemunerationModel__c +
      ' ' +
      line.fact.Name +
      ' (' +
      line.snapshot.Name +
      ')')
      .left(255);
  }

  /** Hours drive the quantity only for HOURLY lines; other models bill one unit at the line amount. */
  private static Decimal lineQuantity(LineFrame line) {
    if (line.snapshot.AXF_CAS_PKL_RemunerationModel__c == 'HOURLY') {
      return line.snapshot.AXF_CAS_NUM_HoursQuantity__c;
    }
    return 1;
  }

  private static Decimal unitPrice(LineFrame line) {
    Decimal quantity = lineQuantity(line);
    if (quantity == null || quantity == 0) {
      return null;
    }
    return (line.fact.AXF_FTX_NUM_Magnitude__c / quantity)
      .setScale(2, System.RoundingMode.HALF_UP);
  }

  /** Unique-key collisions raised by the database are explained with the domain code. */
  private static Exception translateDml(DmlException failure) {
    for (Integer i = 0; i < failure.getNumDml(); i++) {
      if (failure.getDmlType(i) != StatusCode.DUPLICATE_VALUE) {
        continue;
      }
      String message = failure.getDmlMessage(i);
      if (
        message != null && message.contains('AXF_BDO_EXI_ClientRequestId__c')
      ) {
        return failure('CONFLICT', new List<LineIssue>());
      }
      if (message != null && message.contains('AXF_BDO_EXI_DocumentKey__c')) {
        return failure('DOCUMENT_EXISTS', new List<LineIssue>());
      }
    }
    return failure;
  }

  /**
   * The document follows the holder's owner (G2); the user who composed it keeps read/edit
   * access through a share row when they are not that owner.
   */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void grantComposerAccess(
    Id documentId,
    Id versionId,
    Id ownerId
  ) {
    Id me = UserInfo.getUserId();
    if (me == ownerId) {
      return;
    }
    List<SObject> shares = new List<SObject>{
      new AXF_OBJ_BillingDocument__Share(
        ParentId = documentId,
        UserOrGroupId = me,
        AccessLevel = 'Edit',
        RowCause = Schema.AXF_OBJ_BillingDocument__Share.RowCause.Manual
      ),
      new AXF_OBJ_BillingDocumentVersion__Share(
        ParentId = versionId,
        UserOrGroupId = me,
        AccessLevel = 'Edit',
        RowCause = Schema.AXF_OBJ_BillingDocumentVersion__Share.RowCause.Manual
      )
    };
    Database.insert(shares, false);
  }

  private static Decimal nz(Decimal value) {
    return value == null ? 0 : value;
  }

  private static LineIssue issue(
    Id factId,
    Id workRecordId,
    String reason,
    String detail
  ) {
    LineIssue result = new LineIssue();
    result.financialTransactionId = factId;
    result.workRecordId = workRecordId;
    result.reason = reason;
    result.detail = detail;
    return result;
  }

  private static BillingDraftException failure(
    String code,
    List<LineIssue> issues
  ) {
    BillingDraftException result = new BillingDraftException(code);
    result.code = code;
    result.issues = issues;
    return result;
  }
}
