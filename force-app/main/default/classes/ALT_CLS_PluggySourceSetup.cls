/**
 * @description Pluggy connections of the onboarding wizard over the legacy PROD model.
 *
 * - Register: inserts an AXF_OBJ_PluggyConnection__c (Item ID + bank institution, the
 *   legacy Master-Detail) and enqueues the legacy AXF_CLS_PluggyItemSyncQueueable.
 * - Discover: runs the legacy item sync synchronously for one connection (callouts first,
 *   then the legacy upserts), which creates/updates the bank accounts and credit cards
 *   through AXF_CLS_PluggyAccountSync_Service (holder by CPF, bank by bank number).
 * - Status: read from the connection's SyncStatus / ExecutionStatus / LastSyncDatetime /
 *   SyncErrorMessage. Discovered sources: the BA/CC linked to the connection.
 * - The legacy connection has no holder field: the connection holder is derived from its
 *   sources, and setting it propagates the Account lookup to every linked BA/CC.
 *
 * Authority: writes require AXF_CanConfigure; queries and DML run in USER_MODE.
 */
public with sharing class ALT_CLS_PluggySourceSetup {
  public class SourceSetupException extends Exception {
  }

  public static final String RUN_SUCCEEDED = 'SUCCEEDED';
  public static final String RUN_RUNNING = 'RUNNING';
  public static final String RUN_RETRYABLE = 'FAILED_RETRYABLE';
  public static final String RUN_TERMINAL = 'FAILED_TERMINAL';
  private static final String ITEM_UPDATED = 'UPDATED';
  private static final String ITEM_UPDATING = 'UPDATING';
  private static final String ITEM_LOGIN_ERROR = 'LOGIN_ERROR';
  private static final Pattern ITEM_ID_PATTERN = Pattern.compile(
    '^[A-Za-z0-9_-]{3,255}$'
  );
  private static final Integer MAX_ROWS = 500;

  @TestVisible
  private static String lastFailure;

  private class Counts {
    Integer accounts = 0;
    Integer cards = 0;
    Integer withHolder = 0;
    Id holderId;
  }

  // ---------------------------------------------------------------- register

  public AXF_CLS_SourceSetupDTO.RegisterResult registerConnection(
    String pluggyItemId,
    Id bankInstitutionId
  ) {
    requireConfigure();
    String itemId = pluggyItemId == null ? null : pluggyItemId.trim();
    if (itemId == null || !ITEM_ID_PATTERN.matcher(itemId).matches()) {
      throw new SourceSetupException(
        'Informe um Item ID da Pluggy válido (copiado do Dashboard da Pluggy).'
      );
    }
    AXF_CLS_SourceSetupDTO.RegisterResult r = new AXF_CLS_SourceSetupDTO.RegisterResult();
    List<AXF_OBJ_PluggyConnection__c> existing = [
      SELECT Id, Name
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_EXI_PluggyItemId__c = :itemId
      WITH USER_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      r.connectionId = existing[0].Id;
      r.institution = existing[0].Name;
      r.created = false;
      r.message = 'Esta conexão já está registrada.';
      return r;
    }
    if (bankInstitutionId == null) {
      throw new SourceSetupException(
        'Selecione o banco da conexão antes de registrar: toda conexão pertence a uma instituição financeira.'
      );
    }
    AXF_OBJ_BankInstitution__c bank = findBank(bankInstitutionId);
    AXF_OBJ_PluggyConnection__c conn = new AXF_OBJ_PluggyConnection__c(
      Name = (bank.Name + ' · ' + hint(itemId)).left(80),
      AXF_CON_EXI_PluggyItemId__c = itemId,
      AXF_CON_LKP_BankInstitution__c = bank.Id
    );
    try {
      insert as user conn;
    } catch (DmlException e) {
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      throw new SourceSetupException(
        'Não foi possível registrar a conexão: verifique se o Item ID já está cadastrado.'
      );
    }
    System.enqueueJob(
      new AXF_CLS_PluggyItemSyncQueueable(
        new List<AXF_OBJ_PluggyConnection__c>{ conn }
      )
    );
    r.connectionId = conn.Id;
    r.institution = conn.Name;
    r.created = true;
    r.message = 'Conexão registrada. A sincronização com a Pluggy foi iniciada.';
    return r;
  }

  // ---------------------------------------------------------------- reads

  public AXF_CLS_SourceSetupDTO.DiscoveryResult status(Id connectionId) {
    AXF_CLS_SourceSetupDTO.DiscoveryResult r = new AXF_CLS_SourceSetupDTO.DiscoveryResult();
    r.connectionId = connectionId;
    if (connectionId == null) {
      return r;
    }
    AXF_OBJ_PluggyConnection__c conn = load(connectionId);
    if (conn == null) {
      r.message = 'Conexão não encontrada.';
      return r;
    }
    return fill(r, conn, countSources(new Set<Id>{ conn.Id }).get(conn.Id));
  }

  public List<AXF_CLS_SourceSetupDTO.ConnectionOverview> overview() {
    List<AXF_OBJ_PluggyConnection__c> conns = [
      SELECT
        Id,
        Name,
        AXF_CON_EXI_PluggyItemId__c,
        AXF_CON_LKP_BankInstitution__c,
        AXF_CON_LKP_BankInstitution__r.Name,
        AXF_CON_TXT_SyncStatus__c,
        AXF_CON_TXT_SyncErrorMessage__c
      FROM AXF_OBJ_PluggyConnection__c
      WITH USER_MODE
      ORDER BY CreatedDate
      LIMIT :MAX_ROWS
    ];
    Map<Id, Counts> counts = countSources(new Map<Id, SObject>(conns).keySet());
    Set<Id> holderIds = new Set<Id>();
    for (Counts c : counts.values()) {
      if (c.holderId != null) {
        holderIds.add(c.holderId);
      }
    }
    Map<Id, Account> holders = new Map<Id, Account>(
      [SELECT Id, Name FROM Account WHERE Id IN :holderIds WITH USER_MODE]
    );
    List<AXF_CLS_SourceSetupDTO.ConnectionOverview> out = new List<AXF_CLS_SourceSetupDTO.ConnectionOverview>();
    for (AXF_OBJ_PluggyConnection__c conn : conns) {
      Counts c = counts.get(conn.Id);
      AXF_CLS_SourceSetupDTO.ConnectionOverview o = new AXF_CLS_SourceSetupDTO.ConnectionOverview();
      o.connectionId = conn.Id;
      o.itemIdHint = hint(conn.AXF_CON_EXI_PluggyItemId__c);
      o.institution = conn.Name;
      o.consentState = consentState(conn.AXF_CON_TXT_SyncStatus__c);
      o.runState = runState(conn);
      o.accountsFound = c.accounts;
      o.cardsFound = c.cards;
      o.discovered = conn.AXF_CON_TXT_SyncStatus__c == ITEM_UPDATED;
      o.bankInstitutionId = conn.AXF_CON_LKP_BankInstitution__c;
      o.bankInstitutionName = conn.AXF_CON_LKP_BankInstitution__r?.Name;
      o.holderId = c.holderId;
      o.holderName = holders.get(c.holderId)?.Name;
      out.add(o);
    }
    return out;
  }

  public List<AXF_CLS_SourceSetupDTO.DiscoveredSource> discovered(
    Id connectionId
  ) {
    List<AXF_CLS_SourceSetupDTO.DiscoveredSource> out = new List<AXF_CLS_SourceSetupDTO.DiscoveredSource>();
    if (connectionId == null) {
      return out;
    }
    for (AXF_OBJ_BankAccount__c ba : [
      SELECT
        Id,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_BankInstitution__r.Name,
        AXF_BA_PKL_Currency__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_PluggyConnection__c = :connectionId
      WITH USER_MODE
      ORDER BY Name
      LIMIT :MAX_ROWS
    ]) {
      out.add(
        source(
          ba.Id,
          ALT_CLS_SourceHolderLink.KIND_BANK,
          ba.AXF_BA_LKP_BankInstitution__r?.Name,
          ba.AXF_BA_PKL_Currency__c,
          ba.AXF_BA_LKP_Account__c
        )
      );
    }
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT Id, AXF_CC_LKP_Account__c, AXF_CC_LKP_BankInstitution__r.Name
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_PluggyConnection__c = :connectionId
      WITH USER_MODE
      ORDER BY Name
      LIMIT :MAX_ROWS
    ]) {
      out.add(
        source(
          cc.Id,
          ALT_CLS_SourceHolderLink.KIND_CARD,
          cc.AXF_CC_LKP_BankInstitution__r?.Name,
          null,
          cc.AXF_CC_LKP_Account__c
        )
      );
    }
    return out;
  }

  // ---------------------------------------------------------------- discovery

  /**
   * @description Runs the legacy item sync for one connection in this transaction. No DML
   * happens before the sync, so its callouts are allowed; the holder derived from the
   * connection's sources is then applied to the sources that still have none.
   */
  public AXF_CLS_SourceSetupDTO.DiscoveryResult startOrResume(Id connectionId) {
    AXF_CLS_SourceSetupDTO.DiscoveryResult r = new AXF_CLS_SourceSetupDTO.DiscoveryResult();
    r.connectionId = connectionId;
    if (!ALT_CLS_SourceHolderLink.canConfigure()) {
      return failed(
        r,
        RUN_TERMINAL,
        'Você não tem autorização para descobrir contas e cartões.'
      );
    }
    AXF_OBJ_PluggyConnection__c conn = connectionId == null
      ? null
      : load(connectionId);
    if (conn == null) {
      return failed(r, RUN_TERMINAL, 'Conexão não encontrada.');
    }
    try {
      new AXF_CLS_PluggyItemSyncQueueable(
          new List<AXF_OBJ_PluggyConnection__c>{ conn }
        )
        .execute(null);
    } catch (Exception e) {
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      return failed(
        r,
        RUN_TERMINAL,
        'Não foi possível consultar a Pluggy. Verifique as credenciais da integração e tente novamente.'
      );
    }
    conn = load(connectionId);
    Counts c = countSources(new Set<Id>{ conn.Id }).get(conn.Id);
    if (c.holderId != null && c.withHolder < c.accounts + c.cards) {
      applyHolder(conn.Id, c.holderId, true);
      c = countSources(new Set<Id>{ conn.Id }).get(conn.Id);
    }
    fill(r, conn, c);
    if (r.state == RUN_SUCCEEDED) {
      r.message =
        'Descoberta concluída: ' +
        c.accounts +
        ' conta(s) e ' +
        c.cards +
        ' cartão(ões) nesta conexão.';
    } else if (conn.AXF_CON_TXT_SyncStatus__c == ITEM_UPDATING) {
      r.state = RUN_RETRYABLE;
      r.message = 'A Pluggy ainda está atualizando esta conexão. Tente novamente em instantes.';
    } else if (String.isBlank(r.message)) {
      r.message = 'A descoberta não foi concluída.';
    }
    return r;
  }

  // ---------------------------------------------------------------- references

  public AXF_CLS_SourceSetupDTO.UpdateReferencesResult updateReferences(
    Id connectionId,
    Id bankInstitutionId,
    Id holderId
  ) {
    requireConfigure();
    AXF_OBJ_PluggyConnection__c conn = connectionId == null
      ? null
      : load(connectionId);
    if (conn == null) {
      throw new SourceSetupException('Conexão não encontrada.');
    }
    if (
      bankInstitutionId != null &&
      bankInstitutionId != conn.AXF_CON_LKP_BankInstitution__c
    ) {
      // AXF_CON_LKP_BankInstitution__c is a non-reparentable Master-Detail.
      throw new SourceSetupException(
        'O banco de uma conexão já registrada não pode ser alterado. Exclua a conexão e registre-a novamente com o banco correto.'
      );
    }
    AXF_CLS_SourceSetupDTO.UpdateReferencesResult r = new AXF_CLS_SourceSetupDTO.UpdateReferencesResult();
    r.connectionId = conn.Id;
    r.bankInstitutionId = conn.AXF_CON_LKP_BankInstitution__c;
    if (holderId != null) {
      Account holder = ALT_CLS_SourceHolderLink.findHolder(holderId);
      if (holder == null) {
        throw new SourceSetupException(
          'Selecione um titular válido (pessoa ou empresa).'
        );
      }
      try {
        applyHolder(conn.Id, holder.Id, false);
      } catch (DmlException e) {
        lastFailure = e.getTypeName() + ': ' + e.getMessage();
        throw new SourceSetupException(
          'Não foi possível aplicar o titular às contas e cartões desta conexão.'
        );
      }
      r.holderId = holder.Id;
    }
    r.outcome = 'UPDATED';
    r.message = 'Banco e titular da conexão atualizados.';
    return r;
  }

  // ---------------------------------------------------------------- delete

  public AXF_CLS_SourceSetupDTO.DeleteResult deleteConnection(Id connectionId) {
    requireConfigure();
    AXF_CLS_SourceSetupDTO.DeleteResult r = new AXF_CLS_SourceSetupDTO.DeleteResult();
    r.connectionId = connectionId;
    AXF_OBJ_PluggyConnection__c conn = connectionId == null
      ? null
      : load(connectionId);
    if (conn == null) {
      r.outcome = 'NOT_FOUND';
      r.message = 'Conexão não encontrada.';
      return r;
    }
    List<AXF_OBJ_BankAccount__c> accounts = [
      SELECT
        Id,
        AXF_BA_LKP_Account__c,
        (SELECT Id FROM Transactions__r LIMIT 1),
        (SELECT Id FROM CashFlows__r LIMIT 1)
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_PluggyConnection__c = :conn.Id
      WITH USER_MODE
    ];
    List<AXF_OBJ_CreditCard__c> cards = [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        (SELECT Id FROM Transactions__r LIMIT 1),
        (SELECT Id FROM CashFlows__r LIMIT 1),
        (SELECT Id FROM CreditCardInvoices__r LIMIT 1)
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_PluggyConnection__c = :conn.Id
      WITH USER_MODE
    ];
    Boolean inUse = false;
    for (AXF_OBJ_BankAccount__c ba : accounts) {
      inUse |=
        ba.AXF_BA_LKP_Account__c != null ||
        !ba.Transactions__r.isEmpty() ||
        !ba.CashFlows__r.isEmpty();
    }
    for (AXF_OBJ_CreditCard__c cc : cards) {
      inUse |=
        cc.AXF_CC_LKP_Account__c != null ||
        !cc.Transactions__r.isEmpty() ||
        !cc.CashFlows__r.isEmpty() ||
        !cc.CreditCardInvoices__r.isEmpty();
    }
    r.accounts = accounts.size();
    r.cards = cards.size();
    if (inUse) {
      r.outcome = 'BLOCKED';
      r.message = 'A conexão tem contas ou cartões com titular ou movimentos financeiros e não pode ser excluída.';
      return r;
    }
    Savepoint sp = Database.setSavepoint();
    try {
      if (!accounts.isEmpty()) {
        delete as user accounts;
      }
      if (!cards.isEmpty()) {
        delete as user cards;
      }
      delete as user new AXF_OBJ_PluggyConnection__c(Id = conn.Id);
    } catch (Exception e) {
      Database.rollback(sp);
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      r.outcome = 'BLOCKED';
      r.message = 'Não foi possível excluir a conexão. Nada foi alterado.';
      return r;
    }
    r.outcome = 'DELETED';
    r.message = 'Conexão excluída.';
    return r;
  }

  // ---------------------------------------------------------------- helpers

  private static void requireConfigure() {
    if (!ALT_CLS_SourceHolderLink.canConfigure()) {
      throw new SourceSetupException(
        'Você não tem autorização para configurar conexões Pluggy.'
      );
    }
  }

  private static AXF_OBJ_BankInstitution__c findBank(Id bankInstitutionId) {
    if (
      bankInstitutionId.getSObjectType() !=
      AXF_OBJ_BankInstitution__c.SObjectType
    ) {
      throw new SourceSetupException('Instituição financeira não encontrada.');
    }
    List<AXF_OBJ_BankInstitution__c> rows = [
      SELECT Id, Name
      FROM AXF_OBJ_BankInstitution__c
      WHERE Id = :bankInstitutionId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new SourceSetupException('Instituição financeira não encontrada.');
    }
    return rows[0];
  }

  private static AXF_OBJ_PluggyConnection__c load(Id connectionId) {
    if (
      connectionId.getSObjectType() != AXF_OBJ_PluggyConnection__c.SObjectType
    ) {
      return null;
    }
    List<AXF_OBJ_PluggyConnection__c> rows = [
      SELECT
        Id,
        Name,
        AXF_CON_EXI_PluggyItemId__c,
        AXF_CON_LKP_BankInstitution__c,
        AXF_CON_TXT_SyncStatus__c,
        AXF_CON_TXT_ExecutionStatus__c,
        AXF_CON_DT_LastSyncDatetime__c,
        AXF_CON_TXT_SyncErrorMessage__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /** @description Sets the holder on the connection's BA/CC (all, or only unlinked ones). */
  private static void applyHolder(
    Id connectionId,
    Id holderId,
    Boolean onlyUnlinked
  ) {
    List<AXF_OBJ_BankAccount__c> accounts = new List<AXF_OBJ_BankAccount__c>();
    for (AXF_OBJ_BankAccount__c ba : [
      SELECT Id, AXF_BA_LKP_Account__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_PluggyConnection__c = :connectionId
      WITH USER_MODE
    ]) {
      if (
        ba.AXF_BA_LKP_Account__c != holderId &&
        (!onlyUnlinked || ba.AXF_BA_LKP_Account__c == null)
      ) {
        accounts.add(
          new AXF_OBJ_BankAccount__c(
            Id = ba.Id,
            AXF_BA_LKP_Account__c = holderId
          )
        );
      }
    }
    List<AXF_OBJ_CreditCard__c> cards = new List<AXF_OBJ_CreditCard__c>();
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT Id, AXF_CC_LKP_Account__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_PluggyConnection__c = :connectionId
      WITH USER_MODE
    ]) {
      if (
        cc.AXF_CC_LKP_Account__c != holderId &&
        (!onlyUnlinked || cc.AXF_CC_LKP_Account__c == null)
      ) {
        cards.add(
          new AXF_OBJ_CreditCard__c(
            Id = cc.Id,
            AXF_CC_LKP_Account__c = holderId
          )
        );
      }
    }
    if (!accounts.isEmpty()) {
      update as user accounts;
    }
    if (!cards.isEmpty()) {
      update as user cards;
    }
  }

  private static Map<Id, Counts> countSources(Set<Id> connectionIds) {
    Map<Id, Counts> out = new Map<Id, Counts>();
    for (Id connId : connectionIds) {
      out.put(connId, new Counts());
    }
    if (connectionIds.isEmpty()) {
      return out;
    }
    for (AggregateResult ar : [
      SELECT
        AXF_BA_LKP_PluggyConnection__c conn,
        AXF_BA_LKP_Account__c holder,
        COUNT(Id) n
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_PluggyConnection__c IN :connectionIds
      WITH USER_MODE
      GROUP BY AXF_BA_LKP_PluggyConnection__c, AXF_BA_LKP_Account__c
    ]) {
      Counts c = out.get((Id) ar.get('conn'));
      Integer n = (Integer) ar.get('n');
      c.accounts += n;
      tally(c, (Id) ar.get('holder'), n);
    }
    for (AggregateResult ar : [
      SELECT
        AXF_CC_LKP_PluggyConnection__c conn,
        AXF_CC_LKP_Account__c holder,
        COUNT(Id) n
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_PluggyConnection__c IN :connectionIds
      WITH USER_MODE
      GROUP BY AXF_CC_LKP_PluggyConnection__c, AXF_CC_LKP_Account__c
    ]) {
      Counts c = out.get((Id) ar.get('conn'));
      Integer n = (Integer) ar.get('n');
      c.cards += n;
      tally(c, (Id) ar.get('holder'), n);
    }
    return out;
  }

  private static void tally(Counts c, Id holderId, Integer n) {
    if (holderId != null) {
      c.withHolder += n;
      if (c.holderId == null) {
        c.holderId = holderId;
      }
    }
  }

  private static AXF_CLS_SourceSetupDTO.DiscoveryResult fill(
    AXF_CLS_SourceSetupDTO.DiscoveryResult r,
    AXF_OBJ_PluggyConnection__c conn,
    Counts c
  ) {
    r.state = runState(conn);
    r.complete = r.state == RUN_SUCCEEDED;
    r.accountsFound = c.accounts;
    r.cardsFound = c.cards;
    r.released = c.withHolder;
    r.applied = c.withHolder;
    r.pending = c.accounts + c.cards - c.withHolder;
    r.message = String.isBlank(conn.AXF_CON_TXT_SyncErrorMessage__c)
      ? null
      : conn.AXF_CON_TXT_SyncErrorMessage__c.left(255);
    return r;
  }

  @TestVisible
  private static String runState(AXF_OBJ_PluggyConnection__c conn) {
    String status = conn.AXF_CON_TXT_SyncStatus__c;
    if (String.isBlank(status)) {
      return String.isBlank(conn.AXF_CON_TXT_SyncErrorMessage__c)
        ? null
        : RUN_RETRYABLE;
    }
    if (status == ITEM_UPDATED) {
      return RUN_SUCCEEDED;
    }
    if (status == ITEM_UPDATING) {
      return RUN_RUNNING;
    }
    if (status == ITEM_LOGIN_ERROR) {
      return RUN_TERMINAL;
    }
    return RUN_RETRYABLE;
  }

  @TestVisible
  private static String consentState(String status) {
    if (String.isBlank(status)) {
      return null;
    }
    if (status == ITEM_UPDATED || status == ITEM_UPDATING) {
      return 'ACTIVE';
    }
    if (status == ITEM_LOGIN_ERROR) {
      return 'REVOKED';
    }
    return 'STALE';
  }

  private static String hint(String itemId) {
    if (String.isBlank(itemId)) {
      return null;
    }
    return '••••' + (itemId.length() > 4 ? itemId.right(4) : itemId);
  }

  private static AXF_CLS_SourceSetupDTO.DiscoveredSource source(
    Id recordId,
    String kind,
    String institutionName,
    String currencyIsoCode,
    Id holderId
  ) {
    AXF_CLS_SourceSetupDTO.DiscoveredSource s = new AXF_CLS_SourceSetupDTO.DiscoveredSource();
    s.recordId = recordId;
    s.kind = kind;
    s.institution = institutionName;
    s.bankInstitutionName = institutionName;
    s.currencyIsoCode = String.isBlank(currencyIsoCode)
      ? UserInfo.getDefaultCurrency()
      : currencyIsoCode;
    s.hasHolder = holderId != null;
    s.availability = holderId == null
      ? ALT_CLS_SourceHolderLink.STATE_CUSTODY
      : ALT_CLS_SourceHolderLink.STATE_AVAILABLE;
    return s;
  }

  private static AXF_CLS_SourceSetupDTO.DiscoveryResult failed(
    AXF_CLS_SourceSetupDTO.DiscoveryResult r,
    String state,
    String message
  ) {
    r.state = state;
    r.complete = false;
    r.message = message;
    return r;
  }
}
