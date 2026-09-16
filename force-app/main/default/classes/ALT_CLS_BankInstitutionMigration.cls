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
 *
 * AC9 — already-discovered sources. `simulate()` and `apply()` also reach the sources
 * that are ALREADY discovered for a connection that carries a usable reference, so no
 * new discovery is needed: the missing canonical bank is filled from the connection and
 * the eligible sources without a holder are linked and released by the SAME validated
 * operation the discovery uses (`ALT_CLS_SourceHolderConfirmation.applyConnectionReferences`,
 * AXF-85 rules). Nothing is ever overwritten: a source with another CONFIRMED holder and a
 * source whose canonical bank diverges from the connection's are reported as conflicts and
 * preserved for explicit review, and a connection without a usable holder leaves its
 * sources pending. Only the references the caller can really use are handed over, so an
 * unusable bank never blocks the holder application and vice versa, a batch the operation
 * refuses is counted as a failure instead of surviving as a free-text note only, and the
 * dry run classifies every source exactly as the execution treats it. Re-running changes
 * nothing.
 *
 * Rollback semantics. `rollback(mapping)` undoes the CANONICAL BANK work only — the
 * lookups apply() derived from the explicit name mapping, plus the banks a source
 * received from its connection when that connection's own bank is mapping-derived. It
 * deliberately does NOT undo the holder link or the release: a source already released
 * is never sent back to custody (AXF-106 "Never"), and the definitive
 * AXF_OBJ_AccountHolder__c row keeps its own history. A source already in financial use
 * is out of its scope entirely — rollback never deletes, recustodies or edits such a
 * source, so the facts, allocations and snapshots derived from it stay untouched.
 */
public with sharing class ALT_CLS_BankInstitutionMigration {
  /**
   * @description AXF-106 (AC9) test seam: the canonical banks the caller must treat as
   * unusable. The reference-usability probe decides which reference is handed over, and an
   * Apex test cannot make a USER_MODE read hide an otherwise readable institution, so the
   * probe is injectable. Production never sets it.
   */
  @TestVisible
  private static Set<Id> usableBanksForTests;

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
    // ---- AC9: already-discovered sources of connections with a usable reference ----
    public Integer discoveredSourcesTotal = 0;
    /** sources whose missing canonical bank would be / was filled from the connection */
    public Integer discoveredSourcesBankMapped = 0;
    /** sources with no usable connection bank to fill from */
    public Integer discoveredSourcesBankUnresolved = 0;
    /** eligible sources without a holder: linked and released by the same operation */
    public Integer discoveredSourcesReleasable = 0;
    /** sources already linked to the connection's holder */
    public Integer discoveredSourcesAlreadyAssigned = 0;
    /** eligible sources that stay in custody (connection without a usable holder) */
    public Integer discoveredSourcesPending = 0;
    /** sources preserved for explicit review: another CONFIRMED holder or a divergent bank */
    public Integer discoveredSourcesConflicting = 0;
    /** apply(): sources this run actually wrote */
    public Integer discoveredSourcesApplied = 0;
    /** apply(): sources this run newly released */
    public Integer discoveredSourcesReleased = 0;
    /** apply(): sources the database refused — never reported as released */
    public Integer discoveredSourcesFailed = 0;
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
    simulateDiscoveredSources(r);
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
    Map<String, String> normalizedMapping = normalizeMapping(
      providerToBankNumber
    );

    List<AXF_OBJ_PluggyConnection__c> connsToUpdate = new List<AXF_OBJ_PluggyConnection__c>();
    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT Id, AXF_CON_TXT_InstitutionName__c, AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_LKP_BankInstitution__c = NULL
      WITH USER_MODE
    ]) {
      Id target = resolve(
        c.AXF_CON_TXT_InstitutionName__c,
        normalizedMapping,
        byNumber
      );
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
      Id target = resolve(
        b.AXF_BA_TXT_InstitutionName__c,
        normalizedMapping,
        byNumber
      );
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
      Id target = resolve(
        cc.AXF_CC_TXT_InstitutionName__c,
        normalizedMapping,
        byNumber
      );
      if (target != null) {
        cardsToUpdate.add(
          new AXF_OBJ_CreditCard__c(
            Id = cc.Id,
            AXF_CC_LKP_BankInstitution__c = target
          )
        );
      }
    }

    Integer total =
      connsToUpdate.size() +
      accountsToUpdate.size() +
      cardsToUpdate.size();
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

    // AC9 — the already-discovered sources go through the SAME validated operation, so a
    // new discovery is never required to fill the canonical bank and release them.
    applyToDiscoveredSources(r);
    return r;
  }

  /**
   * @description Symmetric rollback of the CANONICAL BANK work: clears the lookup on
   * records whose current lookup matches what apply would have set — either the explicit
   * mapping for the record's provider text, or the bank the source received from a
   * connection whose own bank is mapping-derived. Manually set lookups that differ are
   * preserved, and provider text is never changed.
   *
   * It deliberately does NOT undo the holder link or the release performed by
   * `apply()` (AC9): a released source is never sent back to custody, and the definitive
   * AXF_OBJ_AccountHolder__c row keeps its own history.
   */
  public Report rollback(Map<String, String> providerToBankNumber) {
    Report r = simulate();
    Map<String, Id> byNumber = institutionByBankNumber();
    Map<String, String> normalizedMapping = normalizeMapping(
      providerToBankNumber
    );
    // read the connection banks BEFORE clearing them: a source bank that came from its
    // connection is only mapping-derived when the connection itself was.
    Map<Id, AXF_OBJ_PluggyConnection__c> connBanks = new Map<Id, AXF_OBJ_PluggyConnection__c>(
      [
        SELECT
          Id,
          AXF_CON_TXT_InstitutionName__c,
          AXF_CON_LKP_BankInstitution__c
        FROM AXF_OBJ_PluggyConnection__c
        WITH USER_MODE
      ]
    );

    Integer cleared = 0;
    List<AXF_OBJ_PluggyConnection__c> conns = new List<AXF_OBJ_PluggyConnection__c>();
    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT Id, AXF_CON_TXT_InstitutionName__c, AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_LKP_BankInstitution__c != NULL
      WITH USER_MODE
    ]) {
      if (
        wasBackfilled(
          c.AXF_CON_TXT_InstitutionName__c,
          c.AXF_CON_LKP_BankInstitution__c,
          normalizedMapping,
          byNumber
        )
      ) {
        conns.add(
          new AXF_OBJ_PluggyConnection__c(
            Id = c.Id,
            AXF_CON_LKP_BankInstitution__c = null
          )
        );
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
      SELECT
        Id,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_LKP_Connection__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_BankInstitution__c != NULL
      WITH USER_MODE
    ]) {
      if (
        wasBackfilled(
          b.AXF_BA_TXT_InstitutionName__c,
          b.AXF_BA_LKP_BankInstitution__c,
          normalizedMapping,
          byNumber
        ) ||
        cameFromConnection(
          b.AXF_BA_LKP_Connection__c,
          b.AXF_BA_LKP_BankInstitution__c,
          connBanks,
          normalizedMapping,
          byNumber
        )
      ) {
        accounts.add(
          new AXF_OBJ_BankAccount__c(
            Id = b.Id,
            AXF_BA_LKP_BankInstitution__c = null
          )
        );
      }
    }
    if (!accounts.isEmpty()) {
      update as user accounts;
      cleared += accounts.size();
    }

    List<AXF_OBJ_CreditCard__c> cards = new List<AXF_OBJ_CreditCard__c>();
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT
        Id,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_LKP_BankInstitution__c,
        AXF_CC_LKP_Connection__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_BankInstitution__c != NULL
      WITH USER_MODE
    ]) {
      if (
        wasBackfilled(
          cc.AXF_CC_TXT_InstitutionName__c,
          cc.AXF_CC_LKP_BankInstitution__c,
          normalizedMapping,
          byNumber
        ) ||
        cameFromConnection(
          cc.AXF_CC_LKP_Connection__c,
          cc.AXF_CC_LKP_BankInstitution__c,
          connBanks,
          normalizedMapping,
          byNumber
        )
      ) {
        cards.add(
          new AXF_OBJ_CreditCard__c(
            Id = cc.Id,
            AXF_CC_LKP_BankInstitution__c = null
          )
        );
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

  /**
   * @description True when the source carries the bank of its connection AND that
   * connection's own bank is mapping-derived — i.e. the value the AC9 application would
   * have copied over, so the rollback clears it too. A manually chosen connection bank
   * leaves its sources untouched.
   */
  private Boolean cameFromConnection(
    Id connectionId,
    Id sourceInstitutionId,
    Map<Id, AXF_OBJ_PluggyConnection__c> connBanks,
    Map<String, String> normalizedMapping,
    Map<String, Id> byNumber
  ) {
    if (connectionId == null || sourceInstitutionId == null) {
      return false;
    }
    AXF_OBJ_PluggyConnection__c c = connBanks.get(connectionId);
    if (c == null || c.AXF_CON_LKP_BankInstitution__c != sourceInstitutionId) {
      return false;
    }
    return wasBackfilled(
      c.AXF_CON_TXT_InstitutionName__c,
      c.AXF_CON_LKP_BankInstitution__c,
      normalizedMapping,
      byNumber
    );
  }

  private Integer countConflictingConnections() {
    Map<Id, Set<String>> distinctInstitutions = new Map<Id, Set<String>>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT Id, AXF_BA_LKP_Connection__c, AXF_BA_TXT_InstitutionName__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c != NULL
      WITH USER_MODE
    ]) {
      addDistinct(
        distinctInstitutions,
        b.AXF_BA_LKP_Connection__c,
        b.AXF_BA_TXT_InstitutionName__c
      );
    }
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT Id, AXF_CC_LKP_Connection__c, AXF_CC_TXT_InstitutionName__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Connection__c != NULL
      WITH USER_MODE
    ]) {
      addDistinct(
        distinctInstitutions,
        cc.AXF_CC_LKP_Connection__c,
        cc.AXF_CC_TXT_InstitutionName__c
      );
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

  // ---- AC9: the already-discovered sources of these connections ----

  /** @description One already-discovered source with the fields the AC9 classification needs. */
  private class Discovered {
    Id sourceId;
    String kind;
    Id connectionId;
    Integer version;
    Id bankId;
    Id holderId;
    String availability;
    Boolean bankDiverges = false;
  }

  private List<AXF_OBJ_PluggyConnection__c> readConnections() {
    return [
      SELECT
        Id,
        AXF_CON_TXT_InstitutionName__c,
        AXF_CON_LKP_BankInstitution__c,
        AXF_CON_LKP_Account__c
      FROM AXF_OBJ_PluggyConnection__c
      WITH USER_MODE
    ];
  }

  /** @description Canonical banks of these connections the caller can really use. */
  private Set<Id> usableBankIds(List<AXF_OBJ_PluggyConnection__c> conns) {
    Set<Id> candidates = new Set<Id>();
    for (AXF_OBJ_PluggyConnection__c c : conns) {
      if (c.AXF_CON_LKP_BankInstitution__c != null) {
        candidates.add(c.AXF_CON_LKP_BankInstitution__c);
      }
    }
    Set<Id> out = new Set<Id>();
    if (candidates.isEmpty()) {
      return out;
    }
    for (AXF_OBJ_BankInstitution__c b : [
      SELECT Id
      FROM AXF_OBJ_BankInstitution__c
      WHERE Id IN :candidates
      WITH USER_MODE
    ]) {
      out.add(b.Id);
    }
    return out;
  }

  /**
   * @description The usable canonical banks of these connections, honouring the test probe.
   * The dry run and the execution share this ONE probe, so they can never disagree about
   * what is usable.
   */
  private Set<Id> usableBankIdsFor(List<AXF_OBJ_PluggyConnection__c> conns) {
    return usableBanksForTests != null
      ? usableBanksForTests
      : usableBankIds(conns);
  }

  /** @description Holders of these connections that are a usable person/business (AC2). */
  private Set<Id> usableHolderAccountIds(
    List<AXF_OBJ_PluggyConnection__c> conns
  ) {
    Set<Id> candidates = new Set<Id>();
    for (AXF_OBJ_PluggyConnection__c c : conns) {
      if (c.AXF_CON_LKP_Account__c != null) {
        candidates.add(c.AXF_CON_LKP_Account__c);
      }
    }
    Set<Id> out = new Set<Id>();
    if (candidates.isEmpty()) {
      return out;
    }
    for (Account a : [
      SELECT Id, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :candidates
      WITH USER_MODE
    ]) {
      String rt = a.RecordType == null ? null : a.RecordType.DeveloperName;
      if (
        rt == ALT_CLS_AxonHolder.RT_PERSON ||
        rt == ALT_CLS_AxonHolder.RT_BUSINESS
      ) {
        out.add(a.Id);
      }
    }
    return out;
  }

  /**
   * @description Already-discovered sources of these connections, in one read per kind.
   * A source without a PluggyAccountId is not eligible for the shared application, so it
   * is left out entirely (it stays for explicit resolution).
   */
  private List<Discovered> readDiscovered(Set<Id> connectionIds) {
    List<Discovered> out = new List<Discovered>();
    if (connectionIds.isEmpty()) {
      return out;
    }
    for (AXF_OBJ_BankAccount__c b : [
      SELECT
        Id,
        AXF_BA_LKP_Connection__c,
        AXF_BA_NUM_Version__c,
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_LKP_Account__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_EXI_PluggyAccountId__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c IN :connectionIds
      WITH USER_MODE
    ]) {
      if (String.isBlank(b.AXF_BA_EXI_PluggyAccountId__c)) {
        continue;
      }
      Discovered d = new Discovered();
      d.sourceId = b.Id;
      d.kind = 'BANK';
      d.connectionId = b.AXF_BA_LKP_Connection__c;
      d.version = safeInt(b.AXF_BA_NUM_Version__c);
      d.bankId = b.AXF_BA_LKP_BankInstitution__c;
      d.holderId = b.AXF_BA_LKP_Account__c;
      d.availability = b.AXF_BA_PKL_AvailabilityState__c;
      out.add(d);
    }
    for (AXF_OBJ_CreditCard__c cc : [
      SELECT
        Id,
        AXF_CC_LKP_Connection__c,
        AXF_CC_NUM_Version__c,
        AXF_CC_LKP_BankInstitution__c,
        AXF_CC_LKP_Account__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_EXI_PluggyAccountId__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Connection__c IN :connectionIds
      WITH USER_MODE
    ]) {
      if (String.isBlank(cc.AXF_CC_EXI_PluggyAccountId__c)) {
        continue;
      }
      Discovered d = new Discovered();
      d.sourceId = cc.Id;
      d.kind = 'CARD';
      d.connectionId = cc.AXF_CC_LKP_Connection__c;
      d.version = safeInt(cc.AXF_CC_NUM_Version__c);
      d.bankId = cc.AXF_CC_LKP_BankInstitution__c;
      d.holderId = cc.AXF_CC_LKP_Account__c;
      d.availability = cc.AXF_CC_PKL_AvailabilityState__c;
      out.add(d);
    }
    return out;
  }

  /** @description The CURRENT PRIMARY/CONFIRMED link per source, in one read per kind. */
  private Map<Id, AXF_OBJ_AccountHolder__c> confirmedPrimaryFor(
    List<Discovered> sources
  ) {
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (Discovered s : sources) {
      if (s.kind == 'BANK') {
        bankIds.add(s.sourceId);
      } else {
        cardIds.add(s.sourceId);
      }
    }
    Map<Id, AXF_OBJ_AccountHolder__c> out = new Map<Id, AXF_OBJ_AccountHolder__c>();
    if (!bankIds.isEmpty()) {
      for (AXF_OBJ_AccountHolder__c row : [
        SELECT
          Id,
          AXF_ACH_LKP_Account__c,
          AXF_ACH_LKP_BankAccount__c,
          AXF_ACH_DAT_ValidFrom__c
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_LKP_BankAccount__c IN :bankIds
          AND AXF_ACH_PKL_Role__c = 'PRIMARY'
          AND AXF_ACH_PKL_State__c = 'CONFIRMED'
          AND (AXF_ACH_DAT_ValidTo__c = NULL
          OR AXF_ACH_DAT_ValidTo__c >= TODAY)
        WITH USER_MODE
        ORDER BY AXF_ACH_DAT_ValidFrom__c DESC
      ]) {
        if (!out.containsKey(row.AXF_ACH_LKP_BankAccount__c)) {
          out.put(row.AXF_ACH_LKP_BankAccount__c, row);
        }
      }
    }
    if (!cardIds.isEmpty()) {
      for (AXF_OBJ_AccountHolder__c row : [
        SELECT
          Id,
          AXF_ACH_LKP_Account__c,
          AXF_ACH_LKP_CreditCard__c,
          AXF_ACH_DAT_ValidFrom__c
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_LKP_CreditCard__c IN :cardIds
          AND AXF_ACH_PKL_Role__c = 'PRIMARY'
          AND AXF_ACH_PKL_State__c = 'CONFIRMED'
          AND (AXF_ACH_DAT_ValidTo__c = NULL
          OR AXF_ACH_DAT_ValidTo__c >= TODAY)
        WITH USER_MODE
        ORDER BY AXF_ACH_DAT_ValidFrom__c DESC
      ]) {
        if (!out.containsKey(row.AXF_ACH_LKP_CreditCard__c)) {
          out.put(row.AXF_ACH_LKP_CreditCard__c, row);
        }
      }
    }
    return out;
  }

  /**
   * @description No-DML view of what `apply()` would do with the already-discovered
   * sources. Two independent axes are reported: the canonical bank (fillable from the
   * connection vs. unresolved) and the holder link (releasable, already assigned, pending
   * because the connection has no usable holder, or conflicting and preserved for review).
   */
  private void simulateDiscoveredSources(Report r) {
    List<AXF_OBJ_PluggyConnection__c> conns = readConnections();
    if (conns.isEmpty()) {
      return;
    }
    Map<Id, AXF_OBJ_PluggyConnection__c> byId = new Map<Id, AXF_OBJ_PluggyConnection__c>(
      conns
    );
    Set<Id> usableBanks = usableBankIdsFor(conns);
    Set<Id> usableHolders = usableHolderAccountIds(conns);
    List<Discovered> sources = readDiscovered(byId.keySet());
    Map<Id, AXF_OBJ_AccountHolder__c> confirmed = confirmedPrimaryFor(sources);

    for (Discovered s : sources) {
      r.discoveredSourcesTotal++;
      AXF_OBJ_PluggyConnection__c c = byId.get(s.connectionId);
      Id connBank = c == null ? null : c.AXF_CON_LKP_BankInstitution__c;
      Id connHolder = c == null ? null : c.AXF_CON_LKP_Account__c;
      Boolean bankFillable = connBank != null && usableBanks.contains(connBank);
      Boolean holderUsable =
        connHolder != null && usableHolders.contains(connHolder);
      if (bankFillable && s.bankId != null && s.bankId != connBank) {
        // AC8 — preserved, and reported as a conflict rather than a reuse
        s.bankDiverges = true;
      }

      if (s.bankId == null) {
        if (bankFillable) {
          r.discoveredSourcesBankMapped++;
        } else {
          r.discoveredSourcesBankUnresolved++;
        }
      }

      // The classification mirrors the execution exactly, so the dry run never contradicts
      // what apply() does with the same source.
      AXF_OBJ_AccountHolder__c ach = confirmed.get(s.sourceId);
      Boolean holderDivergent =
        holderUsable &&
        ach != null &&
        ach.AXF_ACH_LKP_Account__c != connHolder;
      if (holderDivergent) {
        // a CONFIRMED holder different from the connection's is never overwritten
        r.discoveredSourcesConflicting++;
      } else if (!holderUsable) {
        // nothing is released; a divergent bank stays for explicit review
        if (s.bankDiverges) {
          r.discoveredSourcesConflicting++;
        } else {
          r.discoveredSourcesPending++;
        }
      } else if (
        ach != null &&
        s.availability == 'AVAILABLE' &&
        s.holderId == connHolder
      ) {
        // already linked and available: only a divergent bank is left to review (AC8)
        if (s.bankDiverges) {
          r.discoveredSourcesConflicting++;
        } else {
          r.discoveredSourcesAlreadyAssigned++;
        }
      } else {
        // The holder axis and the bank axis are independent (AC9): a divergent canonical
        // bank is preserved, but the holder link is still written and the source released —
        // exactly what the execution does.
        r.discoveredSourcesReleasable++;
      }
    }
  }

  /**
   * @description AC9 — reconciles the already-discovered sources through the SAME
   * validated operation the discovery uses, without requiring a new discovery. Only
   * connections that actually carry a usable reference are sent, one call per connection,
   * and only the references the caller can really use are handed over, so an unusable bank
   * never refuses the holder application and vice versa; a batch the operation refuses is
   * counted per source. The operation itself never overwrites a divergent holder or bank.
   * Idempotent: a second run writes nothing.
   */
  private void applyToDiscoveredSources(Report r) {
    List<AXF_OBJ_PluggyConnection__c> conns = readConnections();
    if (conns.isEmpty()) {
      return;
    }
    Map<Id, AXF_OBJ_PluggyConnection__c> byId = new Map<Id, AXF_OBJ_PluggyConnection__c>(
      conns
    );
    Set<Id> usableBanks = usableBankIdsFor(conns);
    Set<Id> usableHolders = usableHolderAccountIds(conns);
    List<Discovered> sources = readDiscovered(byId.keySet());

    Map<Id, List<ALT_CLS_SourceHolderConfirmation.SourceRef>> refsByConnection = new Map<Id, List<ALT_CLS_SourceHolderConfirmation.SourceRef>>();
    for (Discovered s : sources) {
      AXF_OBJ_PluggyConnection__c c = byId.get(s.connectionId);
      if (c == null) {
        continue;
      }
      Boolean bankUsable =
        c.AXF_CON_LKP_BankInstitution__c != null &&
        usableBanks.contains(c.AXF_CON_LKP_BankInstitution__c);
      Boolean holderUsable =
        c.AXF_CON_LKP_Account__c != null &&
        usableHolders.contains(c.AXF_CON_LKP_Account__c);
      if (!bankUsable && !holderUsable) {
        continue; // nothing to apply to this connection
      }
      List<ALT_CLS_SourceHolderConfirmation.SourceRef> refs = refsByConnection.get(
        s.connectionId
      );
      if (refs == null) {
        refs = new List<ALT_CLS_SourceHolderConfirmation.SourceRef>();
        refsByConnection.put(s.connectionId, refs);
      }
      ALT_CLS_SourceHolderConfirmation.SourceRef ref = new ALT_CLS_SourceHolderConfirmation.SourceRef();
      ref.sourceId = s.sourceId;
      ref.kind = s.kind;
      ref.expectedVersion = s.version;
      refs.add(ref);
    }

    for (Id connectionId : refsByConnection.keySet()) {
      AXF_OBJ_PluggyConnection__c c = byId.get(connectionId);
      List<ALT_CLS_SourceHolderConfirmation.SourceRef> refs = refsByConnection.get(
        connectionId
      );
      Boolean bankUsable =
        c.AXF_CON_LKP_BankInstitution__c != null &&
        usableBanks.contains(c.AXF_CON_LKP_BankInstitution__c);
      Boolean holderUsable =
        c.AXF_CON_LKP_Account__c != null &&
        usableHolders.contains(c.AXF_CON_LKP_Account__c);
      ALT_CLS_SourceHolderConfirmation.ConnectionReferenceInput input = new ALT_CLS_SourceHolderConfirmation.ConnectionReferenceInput();
      input.connectionId = connectionId;
      // Only the references the caller can really use are handed over (AC9): an unusable
      // bank must not refuse the whole batch and block the holder application, and an
      // unusable holder must not block the bank application either.
      input.bankInstitutionId = bankUsable
        ? c.AXF_CON_LKP_BankInstitution__c
        : null;
      input.holderId = holderUsable ? c.AXF_CON_LKP_Account__c : null;
      input.sources = refs;

      ALT_CLS_SourceHolderConfirmation.ApplyResult res = new ALT_CLS_SourceHolderConfirmation()
        .applyConnectionReferences(input);
      r.notes.add(res.message);
      r.discoveredSourcesFailed += res.failed;
      // A refused batch wrote nothing at all: every source it carried is a failure of this
      // run, counted instead of leaving all the counters at zero with a note only.
      if (isRefusedBatch(res.outcome)) {
        r.discoveredSourcesFailed += refs.size();
      }
      for (ALT_CLS_SourceHolderConfirmation.SourceApplyView v : res.details) {
        if (v.outcome == 'APPLIED' || v.outcome == 'CORRECTED') {
          r.discoveredSourcesApplied++;
          // only a source whose definitive link really exists counts as released (AC6)
          if (v.availabilityState == 'AVAILABLE') {
            r.discoveredSourcesReleased++;
          }
        }
      }
    }
  }

  /**
   * @description Outcomes in which the operation wrote nothing for the whole batch: the
   * connection references could not be used at all (AC9/AC6).
   */
  private static Boolean isRefusedBatch(String outcome) {
    return outcome == 'FORBIDDEN' ||
      outcome == 'NOT_FOUND' ||
      outcome == 'INVALID' ||
      outcome == 'EMPTY';
  }

  private Integer safeInt(Decimal d) {
    return d == null ? 0 : d.intValue();
  }

  private String normalize(String raw) {
    return String.isBlank(raw) ? null : raw.normalizeSpace().toLowerCase();
  }
}
