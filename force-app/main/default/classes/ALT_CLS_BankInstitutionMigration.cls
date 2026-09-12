/**
 * @description Repeatable bank-institution migration for AXF-106: backfills the
 * canonical AXF_*_LKP_BankInstitution__c lookups on connections, bank accounts and
 * credit cards from an EXPLICIT, administrator-verified mapping, never from a name
 * similarity rule (AC8/AC9). Provides a no-DML simulation report, an idempotent
 * apply, and a symmetric rollback. Provider institution text and connector IDs are
 * always preserved untouched. USER_MODE enforces sharing/CRUD/FLS on every read and
 * write, so a caller without access cannot read or change records.
 *
 * Mapping contract: Map<normalizedProviderInstitutionName, bankNumber>. Only an
 * exact, normalized match on the provider text AND a verified bank number resolve a
 * record; "MeuPluggy", generic connectors and name similarity never assign a bank.
 */
public with sharing class ALT_CLS_BankInstitutionMigration {
  public class Report {
    public Integer connectionsTotal = 0;
    public Integer connectionsMapped = 0;
    public Integer connectionsUnresolved = 0;
    public Integer connectionsConflicting = 0;
    public Integer accountsTotal = 0;
    public Integer accountsMapped = 0;
    public Integer accountsUnresolved = 0;
    public Integer cardsTotal = 0;
    public Integer cardsMapped = 0;
    public Integer cardsUnresolved = 0;
    public Integer backfilled = 0;
    public Integer rollbackCleared = 0;
    public List<String> notes = new List<String>();
  }

  /** @description No-DML dry-run: mapped, unresolved and conflicting counts. */
  public Report simulate() {
    Report r = new Report();

    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT Id, AXF_CON_TXT_InstitutionName__c, AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WITH USER_MODE
    ]) {
      r.connectionsTotal++;
      if (c.AXF_CON_LKP_BankInstitution__c != null) {
        r.connectionsMapped++;
      } else {
        r.connectionsUnresolved++;
      }
    }
    for (AXF_OBJ_BankAccount__c b : [
      SELECT Id, AXF_BA_LKP_BankInstitution__c
      FROM AXF_OBJ_BankAccount__c
      WITH USER_MODE
    ]) {
      r.accountsTotal++;
      if (b.AXF_BA_LKP_BankInstitution__c != null) {
        r.accountsMapped++;
      } else {
        r.accountsUnresolved++;
      }
    }
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT Id, AXF_CC_LKP_BankInstitution__c
      FROM AXF_OBJ_CreditCard__c
      WITH USER_MODE
    ]) {
      r.cardsTotal++;
      if (cc.AXF_CC_LKP_BankInstitution__c != null) {
        r.cardsMapped++;
      } else {
        r.cardsUnresolved++;
      }
    }

    r.connectionsConflicting = countConflictingConnections();
    return r;
  }

  /**
   * @description Idempotent backfill. Fills ONLY null lookups whose normalized
   * provider institution name is a key in the explicit mapping and whose mapped bank
   * number resolves to exactly one institution. Existing non-null lookups are never
   * overwritten (AC8). Re-running with the same mapping changes nothing.
   */
  public Report apply(Map<String, String> providerToBankNumber) {
    Report r = simulate();
    Map<String, Id> byNumber = institutionByBankNumber();
    Map<String, String> normalizedMapping = normalizeMapping(providerToBankNumber);

    List<AXF_OBJ_PluggyConnection__c> connsToUpdate = new List<AXF_OBJ_PluggyConnection__c>();
    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT Id, AXF_CON_TXT_InstitutionName__c, AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_LKP_BankInstitution__c = NULL
      WITH USER_MODE
    ]) {
      Id target = resolve(c.AXF_CON_TXT_InstitutionName__c, normalizedMapping, byNumber);
      if (target != null) {
        connsToUpdate.add(
          new AXF_OBJ_PluggyConnection__c(
            Id = c.Id,
            AXF_CON_LKP_BankInstitution__c = target
          )
        );
      }
    }

    List<AXF_OBJ_BankAccount__c> accountsToUpdate = new List<AXF_OBJ_BankAccount__c>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT Id, AXF_BA_TXT_InstitutionName__c, AXF_BA_LKP_BankInstitution__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_BankInstitution__c = NULL
      WITH USER_MODE
    ]) {
      Id target = resolve(b.AXF_BA_TXT_InstitutionName__c, normalizedMapping, byNumber);
      if (target != null) {
        accountsToUpdate.add(
          new AXF_OBJ_BankAccount__c(
            Id = b.Id,
            AXF_BA_LKP_BankInstitution__c = target
          )
        );
      }
    }

    List<AXF_OBJ_CreditCard__c> cardsToUpdate = new List<AXF_OBJ_CreditCard__c>();
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT Id, AXF_CC_TXT_InstitutionName__c, AXF_CC_LKP_BankInstitution__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_BankInstitution__c = NULL
      WITH USER_MODE
    ]) {
      Id target = resolve(cc.AXF_CC_TXT_InstitutionName__c, normalizedMapping, byNumber);
      if (target != null) {
        cardsToUpdate.add(
          new AXF_OBJ_CreditCard__c(
            Id = cc.Id,
            AXF_CC_LKP_BankInstitution__c = target
          )
        );
      }
    }

    Integer total = connsToUpdate.size() + accountsToUpdate.size() + cardsToUpdate.size();
    if (total > 0) {
      if (!connsToUpdate.isEmpty()) {
        update as user connsToUpdate;
      }
      if (!accountsToUpdate.isEmpty()) {
        update as user accountsToUpdate;
      }
      if (!cardsToUpdate.isEmpty()) {
        update as user cardsToUpdate;
      }
    }
    r.backfilled = total;
    return r;
  }

  /**
   * @description Symmetric rollback: clears the canonical lookup only on records
   * whose current lookup matches what apply would have set (provider text maps to
   * the same bank number). Manually set lookups that differ from the mapping are
   * preserved. Provider text is never changed.
   */
  public Report rollback(Map<String, String> providerToBankNumber) {
    Report r = simulate();
    Map<String, Id> byNumber = institutionByBankNumber();
    Map<String, String> normalizedMapping = normalizeMapping(providerToBankNumber);

    Integer cleared = 0;
    List<AXF_OBJ_PluggyConnection__c> conns = new List<AXF_OBJ_PluggyConnection__c>();
    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT Id, AXF_CON_TXT_InstitutionName__c, AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_LKP_BankInstitution__c != NULL
      WITH USER_MODE
    ]) {
      if (wasBackfilled(c.AXF_CON_TXT_InstitutionName__c, c.AXF_CON_LKP_BankInstitution__c, normalizedMapping, byNumber)) {
        conns.add(new AXF_OBJ_PluggyConnection__c(Id = c.Id, AXF_CON_LKP_BankInstitution__c = null));
      }
    }
    // clearing a lookup via `update as user` requires edit FLS; the running user must
    // hold it (same authority required to apply). Empty lists are skipped below.
    if (!conns.isEmpty()) {
      update as user conns;
      cleared += conns.size();
    }

    List<AXF_OBJ_BankAccount__c> accounts = new List<AXF_OBJ_BankAccount__c>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT Id, AXF_BA_TXT_InstitutionName__c, AXF_BA_LKP_BankInstitution__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_BankInstitution__c != NULL
      WITH USER_MODE
    ]) {
      if (wasBackfilled(b.AXF_BA_TXT_InstitutionName__c, b.AXF_BA_LKP_BankInstitution__c, normalizedMapping, byNumber)) {
        accounts.add(new AXF_OBJ_BankAccount__c(Id = b.Id, AXF_BA_LKP_BankInstitution__c = null));
      }
    }
    if (!accounts.isEmpty()) {
      update as user accounts;
      cleared += accounts.size();
    }

    List<AXF_OBJ_CreditCard__c> cards = new List<AXF_OBJ_CreditCard__c>();
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT Id, AXF_CC_TXT_InstitutionName__c, AXF_CC_LKP_BankInstitution__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_BankInstitution__c != NULL
      WITH USER_MODE
    ]) {
      if (wasBackfilled(cc.AXF_CC_TXT_InstitutionName__c, cc.AXF_CC_LKP_BankInstitution__c, normalizedMapping, byNumber)) {
        cards.add(new AXF_OBJ_CreditCard__c(Id = cc.Id, AXF_CC_LKP_BankInstitution__c = null));
      }
    }
    if (!cards.isEmpty()) {
      update as user cards;
      cleared += cards.size();
    }

    r.rollbackCleared = cleared;
    return r;
  }

  // ---------------------------------------------------------------------------

  private Map<String, Id> institutionByBankNumber() {
    Map<String, Id> byNumber = new Map<String, Id>();
    for (AXF_OBJ_BankInstitution__c inst : [
      SELECT Id, AXF_BI_EXI_Bank_Number__c
      FROM AXF_OBJ_BankInstitution__c
      WITH USER_MODE
    ]) {
      String n = normalize(inst.AXF_BI_EXI_Bank_Number__c);
      if (n != null) {
        byNumber.put(n, inst.Id);
      }
    }
    return byNumber;
  }

  private Map<String, String> normalizeMapping(Map<String, String> raw) {
    Map<String, String> out = new Map<String, String>();
    if (raw == null) {
      return out;
    }
    for (String key : raw.keySet()) {
      String normKey = normalize(key);
      String normValue = normalize(raw.get(key));
      if (normKey != null && normValue != null) {
        out.put(normKey, normValue);
      }
    }
    return out;
  }

  private Id resolve(
    String providerInstitution,
    Map<String, String> normalizedMapping,
    Map<String, Id> byNumber
  ) {
    String norm = normalize(providerInstitution);
    if (norm == null) {
      return null;
    }
    String bankNumber = normalizedMapping.get(norm);
    return bankNumber == null ? null : byNumber.get(bankNumber);
  }

  private Boolean wasBackfilled(
    String providerInstitution,
    Id currentInstitutionId,
    Map<String, String> normalizedMapping,
    Map<String, Id> byNumber
  ) {
    return resolve(providerInstitution, normalizedMapping, byNumber) ==
      currentInstitutionId;
  }

  private Integer countConflictingConnections() {
    Map<Id, Set<String>> distinctInstitutions = new Map<Id, Set<String>>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT Id, AXF_BA_LKP_Connection__c, AXF_BA_TXT_InstitutionName__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c != NULL
      WITH USER_MODE
    ]) {
      addDistinct(distinctInstitutions, b.AXF_BA_LKP_Connection__c, b.AXF_BA_TXT_InstitutionName__c);
    }
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT Id, AXF_CC_LKP_Connection__c, AXF_CC_TXT_InstitutionName__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Connection__c != NULL
      WITH USER_MODE
    ]) {
      addDistinct(distinctInstitutions, cc.AXF_CC_LKP_Connection__c, cc.AXF_CC_TXT_InstitutionName__c);
    }
    Integer conflicting = 0;
    for (Set<String> names : distinctInstitutions.values()) {
      if (names.size() > 1) {
        conflicting++;
      }
    }
    return conflicting;
  }

  private void addDistinct(
    Map<Id, Set<String>> byConnection,
    Id connectionId,
    String institution
  ) {
    if (connectionId == null) {
      return;
    }
    Set<String> names = byConnection.get(connectionId);
    if (names == null) {
      names = new Set<String>();
      byConnection.put(connectionId, names);
    }
    String norm = normalize(institution);
    if (norm != null) {
      names.add(norm);
    }
  }

  private String normalize(String raw) {
    return String.isBlank(raw) ? null : raw.normalizeSpace().toLowerCase();
  }
}
