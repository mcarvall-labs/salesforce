/**
 * @description Escrita privilegiada DECLARADA do metadado operacional de execução da reposição
 * rolante (AXF-103 fatia 2).
 *
 * Existe por duas razões de plataforma, ambas VERIFICADAS neste org antes de a decisão ser
 * tomada (e ambas fixadas por teste em `AXF_CLS_ScheduleReplenishmentWorkerTest`):
 *  1. as keywords de compartilhamento da classe governam visibilidade de REGISTRO; `SYSTEM_MODE`
 *     desliga apenas permissão de objeto e FLS. Um leitor `with sharing` com `WITH SYSTEM_MODE`
 *     devolve zero linhas para um registro invisível ao usuário, e um `without sharing` devolve a
 *     linha;
 *  2. DML também respeita o acesso ao REGISTRO: atualizar, de dentro de uma classe `with sharing`,
 *     uma linha que o usuário não enxerga falha com
 *     `INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY` mesmo em `AccessLevel.SYSTEM_MODE`.
 *
 * Sem este caminho, o job não conseguiria registrar um desfecho PERMANENTE justamente quando o
 * principal NÃO enxerga o cronograma — exatamente o caso "titular não visível" — e o cronograma
 * voltaria à fila para sempre, morrendo de fome a cauda do conjunto devido.
 *
 * Ela grava SOMENTE `RetryCount`, `NextAttemptAt` e `LastErrorCode` — a lista é verificada pelo
 * handler da raiz, que aceita apenas estes três campos sob esta capacidade. Nenhum valor
 * financeiro, nenhuma identidade de ocorrência, nenhum cursor de cobertura e nenhum estado do
 * cronograma atravessam esta classe.
 *
 * ORDEM DE LOCK (contrato L64/L68): o titular é o PRIMEIRO lock. A gravação do estado operacional
 * acontece nos caminhos de falha, que nunca tomaram o lock do comando — então ela o adquire aqui,
 * `Account FOR UPDATE` holder-first, ANTES de qualquer DML descendente. Adquirir o lock tarde,
 * depois de a plataforma já ter travado a linha filha, não satisfaz a ordem.
 *
 * O desfecho da gravação é RELATADO, e não engolido: quem chama lê `lastWritten`,
 * `lastHolderLocked` e `lastFailureReason`. Uma gravação recusada que virasse apenas `false`
 * deixaria o cronograma parecendo parado, sem rastro consultável.
 */
public without sharing class AXF_CLS_ScheduleReplenishmentStateWriter {
  /** Campos operacionais que esta capacidade libera no handler da raiz. */
  public static final Set<String> OPERATIONAL_FIELDS = new Set<String>{
    'AXF_FSC_NUM_RetryCount__c',
    'AXF_FSC_DT_NextAttemptAt__c',
    'AXF_FSC_TXT_LastErrorCode__c'
  };

  public static final String REASON_HOLDER_LOCK_UNAVAILABLE = 'HOLDER_LOCK_UNAVAILABLE';
  public static final String REASON_DML_REFUSED = 'DML_REFUSED';
  public static final String REASON_NOT_FOUND = 'SCHEDULE_NOT_FOUND';
  public static final String REASON_FORCED = 'FORCED_REFUSAL';

  private static Boolean writing = false;

  /** Rastro consultável do ÚLTIMO desfecho da gravação operacional nesta transação. */
  private static Boolean lastWritten = false;
  private static Boolean lastHolderLocked = false;
  private static String lastFailureReason;

  /** Força a recusa da gravação, para exercitar o caminho de escrita recusada. */
  @TestVisible
  private static Integer forcedRefusalsForTest = 0;

  /** @description A última gravação foi efetivada? */
  public static Boolean wasWritten() {
    return lastWritten;
  }

  /** @description O lock do titular foi adquirido ANTES da DML, no último desfecho? */
  public static Boolean lockedHolderBeforeWrite() {
    return lastHolderLocked;
  }

  /** @description Motivo higienizado da última recusa, ou nulo quando gravou. */
  public static String failureReason() {
    return lastFailureReason;
  }

  private AXF_CLS_ScheduleReplenishmentStateWriter() {
  }

  /** @description Descrição higienizada do último desfecho, para log e asserção. */
  public static String describeLastOutcome() {
    return 'estadoOperacional gravado=' +
      lastWritten +
      ' lockTitular=' +
      lastHolderLocked +
      ' motivo=' +
      ((lastFailureReason == null) ? 'n/a' : lastFailureReason);
  }

  /**
   * @description Capacidade somente-leitura para o handler da raiz. Ninguém fora desta classe
   * consegue habilitá-la: a escrita só é ligada pelo próprio método `write`.
   */
  public static Boolean isWriting() {
    return writing;
  }

  /** @description Estado de execução do cronograma, ou nulo quando a identidade não existe. */
  public static AXF_OBJ_FinancialSchedule__c read(Id scheduleId) {
    if (scheduleId == null) {
      return null;
    }
    List<AXF_OBJ_FinancialSchedule__c> rows = [
      SELECT
        Id,
        AXF_FSC_LKP_Account__c,
        AXF_FSC_NUM_RetryCount__c,
        AXF_FSC_TXT_LastErrorCode__c,
        AXF_FSC_DT_NextAttemptAt__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :scheduleId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /**
   * @description Grava o metadado operacional de UMA linha, com o lock do titular adquirido
   * ANTES da escrita. Devolve `true` quando gravou; o motivo de uma recusa fica em
   * `lastFailureReason` e o lock obtido em `lastHolderLocked`. O desfecho classificado pelo
   * chamador nunca é derrubado por este registro operacional.
   */
  public static Boolean write(
    Id scheduleId,
    String errorCode,
    Integer retryCount,
    DateTime nextAttemptAt
  ) {
    lastWritten = false;
    lastHolderLocked = false;
    lastFailureReason = null;
    if (scheduleId == null) {
      lastFailureReason = REASON_NOT_FOUND;
      return false;
    }
    AXF_OBJ_FinancialSchedule__c current = read(scheduleId);
    if (current == null) {
      lastFailureReason = REASON_NOT_FOUND;
      return false;
    }
    // Serialização holder-first (contrato L64/L68): o lock do titular é adquirido AQUI, antes de
    // qualquer DML descendente, porque este caminho é alcançado sem o lock do comando.
    lastHolderLocked = lockHolder(current.AXF_FSC_LKP_Account__c);
    if (current.AXF_FSC_LKP_Account__c != null && !lastHolderLocked) {
      lastFailureReason = REASON_HOLDER_LOCK_UNAVAILABLE;
      return false;
    }
    if (
      Test.isRunningTest() &&
      forcedRefusalsForTest != null &&
      forcedRefusalsForTest > 0
    ) {
      forcedRefusalsForTest--;
      lastFailureReason = REASON_FORCED;
      return false;
    }
    AXF_OBJ_FinancialSchedule__c row = new AXF_OBJ_FinancialSchedule__c(
      Id = scheduleId,
      AXF_FSC_TXT_LastErrorCode__c = errorCode,
      AXF_FSC_NUM_RetryCount__c = (retryCount == null) ? 0 : retryCount,
      AXF_FSC_DT_NextAttemptAt__c = nextAttemptAt
    );
    writing = true;
    try {
      Database.update(
        new List<AXF_OBJ_FinancialSchedule__c>{ row },
        AccessLevel.SYSTEM_MODE
      );
      lastWritten = true;
      return true;
    } catch (DmlException refused) {
      lastFailureReason = REASON_DML_REFUSED;
      return false;
    } finally {
      writing = false;
    }
  }

  /**
   * @description Lock do titular pela capacidade privilegiada declarada. É o PRIMEIRO lock deste
   * caminho: nada abaixo dele é lido ou gravado antes.
   */
  private static Boolean lockHolder(Id accountId) {
    if (accountId == null) {
      return false;
    }
    List<SObject> holders = Database.queryWithBinds(
      'SELECT Id FROM Account WHERE Id = :holderId FOR UPDATE',
      new Map<String, Object>{ 'holderId' => accountId },
      AccessLevel.SYSTEM_MODE
    );
    return holders.size() == 1;
  }
}
