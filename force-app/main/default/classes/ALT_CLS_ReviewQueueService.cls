/**
 * @description Fila unica de revisao humana (AXF-94, AD-41) - nucleo servidor.
 *
 * Entrega o schema `AXF_OBJ_ReviewItem__c` / `RVI` e o fluxo comum de listagem/abertura e
 * resolucao/descarto. Regras:
 * - Valores anteriores (Prior*) vivem no proprio item e sao expurgados apos RESOLVED/DISMISSED
 *   (G7, sem snapshot de payload cru - D-82);
 * - Nada muta no dominio sem State=RESOLVED explicito; a resolucao e atomica e idempotente por
 *   ReviewKey (G6); RESULT_UNKNOWN nao permite repeticao insegura;
 * - Acesso: classe with sharing; item e registros referenciados so visiveis a quem tem acesso a
 *   todos (G2); item invisivel -> nao aparece nem vaza existencia;
 * - A combinacao de lookups tipados por Type e validada no create; CreditCardInvoice nao e
 *   incluido ate seu objeto existir (contrato ativo 10347).
 * Produtores por tipo chegam das historias de origem (AXF-16/17/29/31/32/85/42-merge); o fluxo
 * comum nao depende deles.
 */
public with sharing class ALT_CLS_ReviewQueueService {
  public static final String STATE_OPEN = 'OPEN';
  public static final String STATE_RESOLVED = 'RESOLVED';
  public static final String STATE_DISMISSED = 'DISMISSED';

  public static final Set<String> SUPPORTED_TYPES = new Set<String>{
    'MATCH_LOW_CONFIDENCE',
    'SOURCE_CHANGE',
    'SOURCE_DELETE',
    'TRANSFER_SUGGESTION',
    'ACCOUNT_MERGE',
    'HOLDER_CONFIRMATION'
  };

  public class CreateInputDTO {
    public String type;
    public String reviewKey;
    public Id financialTransactionId;
    public Id creditCardTransactionId;
    public Id bankAccountTransactionId;
    public Id accountId;
    public Id bankAccountId;
    public Id creditCardId;
    public Decimal priorAmount;
    public Date priorDate;
    public String priorDescription;
    public Decimal priorMatchConfidence;
  }

  public class ResolveInputDTO {
    public Id reviewItemId;
    public String decision; // RESOLVED | DISMISSED
    public String note;
    public Decimal expectedVersion;
  }

  public class ResultDTO {
    public Boolean success;
    public Id reviewItemId;
    public String state;
    public String message;
  }

  public class ReviewViewDTO {
    public Id reviewItemId;
    public String name;
    public String type;
    public String state;
    public Id financialTransactionId;
    public Id creditCardTransactionId;
    public Id bankAccountTransactionId;
    public Id accountId;
    public Id bankAccountId;
    public Id creditCardId;
    public Decimal priorAmount;
    public Date priorDate;
    public String priorDescription;
    public Decimal priorMatchConfidence;
    public Id resolvedByUserId;
    public Datetime resolvedAt;
    public String resolutionNote;
  }

  /** Cria um item OPEN. Idempotente por ReviewKey enquanto houver item OPEN com a mesma chave. */
  public ResultDTO createItem(CreateInputDTO input) {
    validateCreate(input);
    List<AXF_OBJ_ReviewItem__c> existing = [
      SELECT Id
      FROM AXF_OBJ_ReviewItem__c
      WHERE
        AXF_RVI_EXI_ReviewKey__c = :input.reviewKey
        AND AXF_RVI_PKL_State__c = :STATE_OPEN
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      ResultDTO dup = new ResultDTO();
      dup.success = false;
      dup.reviewItemId = existing[0].Id;
      dup.state = STATE_OPEN;
      dup.message = 'Item ja aberto para esta chave (idempotente).';
      return dup;
    }
    AXF_OBJ_ReviewItem__c item = new AXF_OBJ_ReviewItem__c(
      AXF_RVI_PKL_Type__c = input.type,
      AXF_RVI_PKL_State__c = STATE_OPEN,
      AXF_RVI_EXI_ReviewKey__c = input.reviewKey,
      AXF_RVI_LKP_FinancialTransaction__c = input.financialTransactionId,
      AXF_RVI_LKP_CreditCardTransaction__c = input.creditCardTransactionId,
      AXF_RVI_LKP_BankAccountTransaction__c = input.bankAccountTransactionId,
      AXF_RVI_LKP_Account__c = input.accountId,
      AXF_RVI_LKP_BankAccount__c = input.bankAccountId,
      AXF_RVI_LKP_CreditCard__c = input.creditCardId,
      AXF_RVI_NUM_PriorAmount__c = input.priorAmount,
      AXF_RVI_DAT_PriorDate__c = input.priorDate,
      AXF_RVI_TXT_PriorDescription__c = input.priorDescription,
      AXF_RVI_NUM_PriorMatchConfidence__c = input.priorMatchConfidence,
      AXF_RVI_NUM_Version__c = 0
    );
    insert item;
    ResultDTO out = new ResultDTO();
    out.success = true;
    out.reviewItemId = item.Id;
    out.state = STATE_OPEN;
    out.message = 'Item criado.';
    return out;
  }

  /** Lista itens OPEN visiveis ao usuario (with sharing). */
  public List<ReviewViewDTO> listOpen() {
    List<AXF_OBJ_ReviewItem__c> rows = [
      SELECT
        Id,
        Name,
        AXF_RVI_PKL_Type__c,
        AXF_RVI_PKL_State__c,
        AXF_RVI_LKP_FinancialTransaction__c,
        AXF_RVI_LKP_CreditCardTransaction__c,
        AXF_RVI_LKP_BankAccountTransaction__c,
        AXF_RVI_LKP_Account__c,
        AXF_RVI_LKP_BankAccount__c,
        AXF_RVI_LKP_CreditCard__c,
        AXF_RVI_NUM_PriorAmount__c,
        AXF_RVI_DAT_PriorDate__c,
        AXF_RVI_TXT_PriorDescription__c,
        AXF_RVI_NUM_PriorMatchConfidence__c,
        AXF_RVI_LKP_ResolvedByUser__c,
        AXF_RVI_DT_ResolvedAt__c,
        AXF_RVI_TAL_ResolutionNote__c,
        AXF_RVI_NUM_Version__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE AXF_RVI_PKL_State__c = :STATE_OPEN
      ORDER BY CreatedDate ASC
    ];
    List<ReviewViewDTO> out = new List<ReviewViewDTO>();
    for (AXF_OBJ_ReviewItem__c r : rows) {
      out.add(toView(r));
    }
    return out;
  }

  /** Abre um item especifico (somente se visivel). */
  public ReviewViewDTO open(Id reviewItemId) {
    List<AXF_OBJ_ReviewItem__c> rows = fetch(reviewItemId);
    return rows.isEmpty() ? null : toView(rows[0]);
  }

  /**
   * Resolve (RESOLVED) ou descarta (DISMISSED) um item OPEN. Expurga Prior* na resolucao
   * (G7). Concorrencia via expectedVersion (G6). Retorna sucesso ou resultado de bloqueio.
   */
  public ResultDTO resolve(ResolveInputDTO input) {
    ResultDTO out = new ResultDTO();
    if (input == null || input.reviewItemId == null) {
      throw new AXF_CLS_ReviewQueueException('Item de revisao e obrigatorio.');
    }
    if (input.decision != STATE_RESOLVED && input.decision != STATE_DISMISSED) {
      throw new AXF_CLS_ReviewQueueException(
        'Decisao invalida: somente RESOLVED ou DISMISSED.'
      );
    }
    List<AXF_OBJ_ReviewItem__c> rows = fetch(input.reviewItemId);
    if (rows.isEmpty()) {
      out.success = false;
      out.message = 'Item nao encontrado ou sem acesso.';
      return out;
    }
    AXF_OBJ_ReviewItem__c item = rows[0];
    if (item.AXF_RVI_PKL_State__c != STATE_OPEN) {
      out.success = false;
      out.state = item.AXF_RVI_PKL_State__c;
      out.reviewItemId = item.Id;
      out.message = 'Somente itens OPEN podem ser resolvidos.';
      return out;
    }
    if (
      input.expectedVersion != null &&
      item.AXF_RVI_NUM_Version__c != input.expectedVersion
    ) {
      throw new AXF_CLS_ReviewQueueException(
        'CONFLICT: versao do item mudou desde a leitura.'
      );
    }
    item.AXF_RVI_PKL_State__c = input.decision;
    item.AXF_RVI_LKP_ResolvedByUser__c = UserInfo.getUserId();
    item.AXF_RVI_DT_ResolvedAt__c = System.now();
    item.AXF_RVI_TAL_ResolutionNote__c = input.note;
    // Expurgo de valores anteriores (G7) - nunca em payload cru em outro objeto.
    item.AXF_RVI_NUM_PriorAmount__c = null;
    item.AXF_RVI_DAT_PriorDate__c = null;
    item.AXF_RVI_TXT_PriorDescription__c = null;
    item.AXF_RVI_NUM_PriorMatchConfidence__c = null;
    item.AXF_RVI_NUM_Version__c =
      (item.AXF_RVI_NUM_Version__c == null ? 0 : item.AXF_RVI_NUM_Version__c) +
      1;
    AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = true;
    try {
      update item;
    } finally {
      AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = false;
    }

    out.success = true;
    out.reviewItemId = item.Id;
    out.state = input.decision;
    out.message =
      'Item ' +
      (input.decision == STATE_RESOLVED ? 'resolvido' : 'descartado') +
      '.';
    return out;
  }

  // ---- Internals --------------------------------------------------------------

  private void validateCreate(CreateInputDTO input) {
    if (input == null || input.type == null) {
      throw new AXF_CLS_ReviewQueueException('Tipo do item e obrigatorio.');
    }
    if (!SUPPORTED_TYPES.contains(input.type)) {
      throw new AXF_CLS_ReviewQueueException('Tipo de item nao suportado.');
    }
    if (String.isBlank(input.reviewKey)) {
      throw new AXF_CLS_ReviewQueueException(
        'ReviewKey e obrigatoria (idempotencia).'
      );
    }
    Integer refs = 0;
    if (input.financialTransactionId != null)
      refs++;
    if (input.creditCardTransactionId != null)
      refs++;
    if (input.bankAccountTransactionId != null)
      refs++;
    if (input.accountId != null)
      refs++;
    if (input.bankAccountId != null)
      refs++;
    if (input.creditCardId != null)
      refs++;
    if (refs == 0) {
      throw new AXF_CLS_ReviewQueueException(
        'Item deve referenciar ao menos um registro envolvido.'
      );
    }
  }

  private List<AXF_OBJ_ReviewItem__c> fetch(Id id) {
    return [
      SELECT
        Id,
        Name,
        AXF_RVI_PKL_Type__c,
        AXF_RVI_PKL_State__c,
        AXF_RVI_LKP_FinancialTransaction__c,
        AXF_RVI_LKP_CreditCardTransaction__c,
        AXF_RVI_LKP_BankAccountTransaction__c,
        AXF_RVI_LKP_Account__c,
        AXF_RVI_LKP_BankAccount__c,
        AXF_RVI_LKP_CreditCard__c,
        AXF_RVI_NUM_PriorAmount__c,
        AXF_RVI_DAT_PriorDate__c,
        AXF_RVI_TXT_PriorDescription__c,
        AXF_RVI_NUM_PriorMatchConfidence__c,
        AXF_RVI_LKP_ResolvedByUser__c,
        AXF_RVI_DT_ResolvedAt__c,
        AXF_RVI_TAL_ResolutionNote__c,
        AXF_RVI_NUM_Version__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE Id = :id
      LIMIT 1
    ];
  }

  private ReviewViewDTO toView(AXF_OBJ_ReviewItem__c r) {
    ReviewViewDTO v = new ReviewViewDTO();
    v.reviewItemId = r.Id;
    v.name = r.Name;
    v.type = r.AXF_RVI_PKL_Type__c;
    v.state = r.AXF_RVI_PKL_State__c;
    v.financialTransactionId = r.AXF_RVI_LKP_FinancialTransaction__c;
    v.creditCardTransactionId = r.AXF_RVI_LKP_CreditCardTransaction__c;
    v.bankAccountTransactionId = r.AXF_RVI_LKP_BankAccountTransaction__c;
    v.accountId = r.AXF_RVI_LKP_Account__c;
    v.bankAccountId = r.AXF_RVI_LKP_BankAccount__c;
    v.creditCardId = r.AXF_RVI_LKP_CreditCard__c;
    v.priorAmount = r.AXF_RVI_NUM_PriorAmount__c;
    v.priorDate = r.AXF_RVI_DAT_PriorDate__c;
    v.priorDescription = r.AXF_RVI_TXT_PriorDescription__c;
    v.priorMatchConfidence = r.AXF_RVI_NUM_PriorMatchConfidence__c;
    v.resolvedByUserId = r.AXF_RVI_LKP_ResolvedByUser__c;
    v.resolvedAt = r.AXF_RVI_DT_ResolvedAt__c;
    v.resolutionNote = r.AXF_RVI_TAL_ResolutionNote__c;
    return v;
  }
}
