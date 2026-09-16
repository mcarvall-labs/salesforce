/**
 * @description Confirms the financial holder of a discovered bank account or
 * credit card and corrects a wrong link (AXF-85).
 *
 * Contract: ARCHITECTURE-SPINE.md "Fechamento G1" (G1-4 `AccountHolder`/ACH
 * junction, G1-7 reparenting) + "Fechamento G2" (G2-2 owner sync, G2-5
 * unassigned/custody) + "Fechamento G5" (G5-5 custody isolation) + G6
 * (framed identity). AD-42 / AD-19 / D-43.
 *
 * Model:
 * - A discovered source lands in `AvailabilityState = CUSTODY`, owner = the
 *   configurador, hidden from every financial surface (AXF-84 / G5-5).
 * - Confirming a holder creates the authoritative `AXF_OBJ_AccountHolder__c`
 *   (ACH) row — Role PRIMARY, State CONFIRMED, framed identity key (G6) — then
 *   points the source's denormalised holder lookup, syncs its OwnerId to the
 *   holder's owner (G2-2) and flips it to `AVAILABLE`.
 * - Correcting the holder (AC5) supersedes the previous ACH row (State
 *   SUPERSEDED + ValidTo = today), never rewrites transactions/currency/external
 *   identity, and re-points the source. The convergent revalidation of the
 *   ex-holder's derived access is AXF-8; a hook is left here.
 * - Discovery applies, in one batch, the bank and the holder the administrator
 *   chose on the Pluggy connection to every source it just discovered (AXF-106,
 *   `applyConnectionReferences`). Same definitive link, same release rule, one
 *   explicit and re-executable trigger. A source whose CONFIRMED PRIMARY holder
 *   differs from the connection's is reported DIVERGENT and left untouched — a
 *   confirmed holder is never overwritten by a discovery run.
 *
 * Boundaries:
 * - The financial holder is NOT the OwnerId, NOT a Salesforce user and NOT a
 *   business responsible (AXF-83). Never assigned by name/document similarity —
 *   an explicit holderId is always required (AC2).
 * - A source with no confirmed PRIMARY ACH stays unusable and invisible to
 *   participants; no generic/placeholder holder is ever created (AC3).
 * - Credit cards are independent in the approved model — there is no card→bank
 *   lookup; a bank relation reported by the source is not persisted and no
 *   checking account is invented (AC4).
 * - Never grants Delete; never deletes financial facts.
 *
 * Authority: every entry point requires `AXF_CanConfigure` — that is the real
 * access control for this privileged config flow (AC2/AC3). The custody sources
 * and ACH rows are read/written in SYSTEM_MODE (config workspace, hidden from
 * the product, owner = configurador — AD-27, matches AXF-86); the **holder**
 * Account is read `WITH USER_MODE` so the caller genuinely has access to the
 * person/company being assigned (AC2). PT-BR literals for the MVP (D-86).
 *
 * AXF-85.
 */
public with sharing class ALT_CLS_SourceHolderConfirmation {
  public enum Outcome {
    CONFIRMED,
    ALREADY,
    CORRECTED,
    CONFLICT,
    FORBIDDEN,
    INVALID,
    NOT_FOUND
  }

  /**
   * @description Per-source classification of `applyConnectionReferences` (AXF-106):
   * APPLIED = the connection's bank and/or the definitive holder link was written;
   * REUSED = the source already matched what the connection defines, nothing written;
   * CORRECTED = the confirmed link was kept and the source state repaired;
   * DIVERGENT = another holder is already CONFIRMED, nothing written;
   * IGNORED = not eligible (no PluggyAccountId, outside the connection) or nothing to
   * apply. CONFLICT = the source changed meanwhile, or its canonical bank diverges from
   * the connection's (AC8) — nothing was overwritten. FAILED = the database refused the
   * write; the source keeps its previous state and no link is left behind (AC6).
   */
  public enum ApplyClass {
    APPLIED,
    REUSED,
    CORRECTED,
    DIVERGENT,
    IGNORED,
    CONFLICT,
    FAILED
  }

  private static final Set<String> HOLDER_RTS = new Set<String>{
    'AXF_Person',
    'AXF_Business'
  };

  @TestVisible
  private static Boolean canConfigureOverride;

  @TestVisible
  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  // ================= DTOs =================
  public class SourceView {
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String kind; // BANK | CARD
    @AuraEnabled
    public String institutionName;
    @AuraEnabled
    public String bankInstitutionName;
    @AuraEnabled
    public String maskedNumber;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public String availabilityState;
    @AuraEnabled
    public Integer version;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderName;
    @AuraEnabled
    public Id accountHolderId;
    // true when the connection's holder differs from the source's CONFIRMED PRIMARY
    // holder — the source is preserved and must be resolved explicitly (AXF-106).
    @AuraEnabled
    public Boolean divergent = false;
  }

  public class Overview {
    @AuraEnabled
    public Boolean forbidden = false;
    @AuraEnabled
    public List<SourceView> pending = new List<SourceView>();
    @AuraEnabled
    public List<SourceView> released = new List<SourceView>();
    @AuraEnabled
    public List<SourceView> divergent = new List<SourceView>();
  }

  public class ConfirmInput {
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public Integer expectedVersion;
    @AuraEnabled
    public String note;
  }

  public class ConfirmResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public Id accountHolderId;
    @AuraEnabled
    public Integer version;
    @AuraEnabled
    public String availabilityState;
    @AuraEnabled
    public List<String> invalidFields = new List<String>();
  }

  /** @description One discovered source to reconcile with the connection (AXF-106). */
  public class SourceRef {
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String kind; // BANK | CARD
    // Version read by the caller before its callouts; null => no staleness check.
    @AuraEnabled
    public Integer expectedVersion;
  }

  /** @description Connection references plus the sources to apply them to (AXF-106). */
  public class ConnectionReferenceInput {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public Id bankInstitutionId;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public List<SourceRef> sources = new List<SourceRef>();
  }

  public class SourceApplyView {
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String outcome; // ApplyClass
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String availabilityState;
    @AuraEnabled
    public Integer version;
    // AC8: the canonical bank already stored on the source differs from the connection's.
    // The stored value is preserved and surfaced for explicit review — never reported as
    // a silent reuse.
    @AuraEnabled
    public Boolean bankDivergent = false;
    // state before the batch, kept so a refused write reports the truth and can be
    // reverted inside the same transaction
    private String priorAvailability;
    private Integer priorVersion;
    private Id priorHolderId;
    private Id priorOwnerId;
    private Id priorBankId;
    // true only when THIS batch wrote the definitive link and left the source AVAILABLE,
    // so the release counters report the action of the run and not the state it inherited
    private Boolean releasedThisRun = false;
  }

  public class ApplyResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer applied = 0;
    @AuraEnabled
    public Integer reused = 0;
    @AuraEnabled
    public Integer corrected = 0;
    @AuraEnabled
    public Integer divergent = 0;
    @AuraEnabled
    public Integer ignored = 0;
    @AuraEnabled
    public Integer conflicts = 0;
    @AuraEnabled
    public Integer bankDivergent = 0;
    // AC6: writes the database refused. Counted, reported and never hidden behind a
    // success marker.
    @AuraEnabled
    public Integer failed = 0;
    @AuraEnabled
    public Integer released = 0;
    @AuraEnabled
    public Integer pending = 0;
    @AuraEnabled
    public List<SourceApplyView> details = new List<SourceApplyView>();
  }

  // ================= public API =================
  public Overview overview() {
    Overview o = new Overview();
    if (!callerCanConfigure()) {
      o.forbidden = true;
      return o;
    }
    List<SourceView> views = new List<SourceView>();
    // connection holder per source — divergence is only meaningful against it (AXF-106)
    Map<Id, Id> connectionHolder = new Map<Id, Id>();
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT
        Id,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_LKP_BankInstitution__r.Name,
        AXF_BA_TXT_NumberMasked__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_NUM_Version__c,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_Account__r.Name,
        AXF_BA_LKP_Connection__c,
        AXF_BA_LKP_Connection__r.AXF_CON_LKP_Account__c
      FROM AXF_OBJ_BankAccount__c
      WITH SYSTEM_MODE
      ORDER BY AXF_BA_TXT_InstitutionName__c
    ]) {
      SourceView v = bankView(b);
      views.add(v);
      bankIds.add(b.Id);
      connectionHolder.put(
        b.Id,
        b.AXF_BA_LKP_Connection__r == null
          ? null
          : b.AXF_BA_LKP_Connection__r.AXF_CON_LKP_Account__c
      );
    }
    for (AXF_OBJ_CreditCard__c c : [
      SELECT
        Id,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_LKP_BankInstitution__r.Name,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_NUM_Version__c,
        AXF_CC_LKP_Account__c,
        AXF_CC_LKP_Account__r.Name,
        AXF_CC_LKP_Connection__c,
        AXF_CC_LKP_Connection__r.AXF_CON_LKP_Account__c
      FROM AXF_OBJ_CreditCard__c
      WITH SYSTEM_MODE
      ORDER BY AXF_CC_TXT_InstitutionName__c
    ]) {
      SourceView v = cardView(c);
      views.add(v);
      cardIds.add(c.Id);
      connectionHolder.put(
        c.Id,
        c.AXF_CC_LKP_Connection__r == null
          ? null
          : c.AXF_CC_LKP_Connection__r.AXF_CON_LKP_Account__c
      );
    }

    Map<Id, AXF_OBJ_AccountHolder__c> confirmed = activePrimaryBySource(
      'BANK',
      bankIds
    );
    confirmed.putAll(activePrimaryBySource('CARD', cardIds));

    for (SourceView v : views) {
      AXF_OBJ_AccountHolder__c ach = confirmed.get(v.sourceId);
      if (ach != null) {
        v.accountHolderId = ach.Id;
        Id fromConnection = connectionHolder.get(v.sourceId);
        v.divergent =
          fromConnection != null &&
          ach.AXF_ACH_LKP_Account__c != null &&
          fromConnection != ach.AXF_ACH_LKP_Account__c;
      }
      bucket(o, v);
      if (v.divergent == true) {
        o.divergent.add(v);
      }
    }
    return o;
  }

  public ConfirmResult confirmHolder(ConfirmInput input) {
    if (!callerCanConfigure()) {
      return err(Outcome.FORBIDDEN, MSG_FORBIDDEN);
    }
    String k = normalizeKind(input == null ? null : input.kind);
    if (
      input == null ||
      input.sourceId == null ||
      input.holderId == null ||
      k == null
    ) {
      return err(Outcome.INVALID, MSG_INVALID);
    }
    if (input.expectedVersion == null) {
      return invalid('expectedVersion', MSG_NEED_VERSION);
    }

    // holder — real record access + allowed type (AC2)
    List<Account> holders = [
      SELECT Id, OwnerId, RecordType.DeveloperName
      FROM Account
      WHERE Id = :input.holderId
      WITH USER_MODE
      LIMIT 1
    ];
    if (holders.isEmpty()) {
      return err(Outcome.NOT_FOUND, MSG_HOLDER_NOT_FOUND);
    }
    if (!HOLDER_RTS.contains(holders[0].RecordType.DeveloperName)) {
      return invalid('holderId', MSG_HOLDER_TYPE);
    }
    Account holder = holders[0];

    SObject source = readSource(k, input.sourceId);
    if (source == null) {
      return err(Outcome.NOT_FOUND, MSG_SOURCE_NOT_FOUND);
    }
    Integer currentVersion = safeInt((Decimal) source.get(versionField(k)));
    if (currentVersion != input.expectedVersion) {
      return err(Outcome.CONFLICT, MSG_CONFLICT);
    }

    // current active PRIMARY ACH for this source (persisted link — AC7)
    AXF_OBJ_AccountHolder__c activePrimary = activePrimary(k, input.sourceId);

    if (
      activePrimary != null &&
      activePrimary.AXF_ACH_LKP_Account__c == holder.Id
    ) {
      ensureAvailable(k, source, holder, currentVersion);
      return done(
        Outcome.ALREADY,
        MSG_ALREADY,
        input.sourceId,
        activePrimary.Id,
        currentVersion,
        (String) source.get(availabilityField(k))
      );
    }

    Outcome oc;
    if (activePrimary != null) {
      // correction (AC5) — supersede the previous holder, keep history
      activePrimary.AXF_ACH_PKL_State__c = 'SUPERSEDED';
      activePrimary.AXF_ACH_DAT_ValidTo__c = Date.today();
      if (String.isNotBlank(input.note)) {
        activePrimary.AXF_ACH_TXT_Note__c = input.note.abbreviate(255);
      }
      Database.update(activePrimary, AccessLevel.SYSTEM_MODE);
      oc = Outcome.CORRECTED;
      // hook: convergent revalidation of the ex-holder's derived access = AXF-8
    } else {
      oc = Outcome.CONFIRMED;
    }

    AXF_OBJ_AccountHolder__c ach = upsertPrimary(k, input.sourceId, holder);
    if (String.isNotBlank(input.note)) {
      ach.AXF_ACH_TXT_Note__c = input.note.abbreviate(255);
    }

    // point the source, sync owner (G2-2), release it (G5-5)
    Integer nextVersion = currentVersion + 1;
    SObject sourceUpdate = source.getSObjectType().newSObject(source.Id);
    sourceUpdate.put(holderField(k), holder.Id);
    sourceUpdate.put('OwnerId', holder.OwnerId);
    sourceUpdate.put(availabilityField(k), 'AVAILABLE');
    sourceUpdate.put(versionField(k), nextVersion);

    Database.upsert(
      ach,
      AXF_OBJ_AccountHolder__c.AXF_ACH_EXI_FramedKey__c,
      AccessLevel.SYSTEM_MODE
    );
    Database.update(sourceUpdate, AccessLevel.SYSTEM_MODE);

    return done(
      oc,
      oc == Outcome.CORRECTED ? MSG_CORRECTED : MSG_CONFIRMED,
      input.sourceId,
      reloadAchId(k, input.sourceId, holder.Id),
      nextVersion,
      'AVAILABLE'
    );
  }

  public SourceView getSourceHolder(Id sourceId, String kind) {
    String k = normalizeKind(kind);
    if (!callerCanConfigure() || sourceId == null || k == null) {
      return null;
    }
    SObject s = readSource(k, sourceId);
    if (s == null) {
      return null;
    }
    return k == 'BANK'
      ? bankView((AXF_OBJ_BankAccount__c) s)
      : cardView((AXF_OBJ_CreditCard__c) s);
  }

  /**
   * @description Applies the bank and the definitive holder chosen on a Pluggy
   * connection to the sources just discovered for it (AXF-106). One batch entry point
   * so the AXF-85 rules live in a single place: HOLDER_RTS, framed(), activePrimary()
   * and the PRIMARY/CONFIRMED link with the source lookup, OwnerId and
   * AvailabilityState='AVAILABLE' synced and Version+1.
   *
   * Eligibility (Design Notes): the source belongs to the connection and carries a
   * PluggyAccountId. The bank is applied only where the source has none — a bank
   * already filled in differently is preserved and reported as a bank divergence
   * (AC8), never overwritten and never reported as a silent reuse. The holder link is
   * created only for a reachable AXF_Person/AXF_Business Account; without a holder the
   * source stays in CUSTODY and is reported pending.
   *
   * Nothing is applied at all when an informed reference is unusable (bank not
   * found/inaccessible, holder missing or of the wrong record type): INVALID/NOT_FOUND,
   * no partial write. A source whose CONFIRMED PRIMARY holder differs from the
   * connection's is DIVERGENT and is left exactly as it is. `expectedVersion` closes
   * the window the caller spent on callouts: a source changed meanwhile is CONFLICT,
   * never a silent overwrite.
   *
   * Failure handling (AC6): the source is written first and the definitive link second,
   * so a refused link write never leaves a CONFIRMED row pointing at a source still in
   * custody — the source write is reverted inside the same transaction instead. Both
   * batches report per record, so one refused source never discards the others, and
   * every refusal is counted in `failed`, reflected in `outcome` and stated in the
   * summary. A source is only ever counted as released when its definitive link was
   * really written.
   *
   * Authority: AXF_CanConfigure, the same gate as discovery and confirmation. Sources
   * and ACH rows run in SYSTEM_MODE (config workspace — AD-27 / AXF-85); the holder
   * Account is read WITH USER_MODE so the caller genuinely has access to it.
   */
  public ApplyResult applyConnectionReferences(ConnectionReferenceInput input) {
    ApplyResult r = new ApplyResult();
    if (!callerCanConfigure()) {
      r.outcome = 'FORBIDDEN';
      r.message = MSG_FORBIDDEN;
      return r;
    }
    if (input == null || input.connectionId == null) {
      r.outcome = 'INVALID';
      r.message = MSG_INVALID;
      return r;
    }

    // ---- reference validation: an unusable reference applies nothing whatsoever ----
    if (input.bankInstitutionId != null) {
      List<AXF_OBJ_BankInstitution__c> banks = [
        SELECT Id
        FROM AXF_OBJ_BankInstitution__c
        WHERE Id = :input.bankInstitutionId
        WITH USER_MODE
        LIMIT 1
      ];
      if (banks.isEmpty()) {
        r.outcome = 'NOT_FOUND';
        r.message = MSG_BANK_REF_UNUSABLE;
        return r;
      }
    }
    Account holder = null;
    if (input.holderId != null) {
      List<Account> holders = [
        SELECT Id, OwnerId, RecordType.DeveloperName
        FROM Account
        WHERE Id = :input.holderId
        WITH USER_MODE
        LIMIT 1
      ];
      if (holders.isEmpty()) {
        r.outcome = 'NOT_FOUND';
        r.message = MSG_HOLDER_NOT_FOUND;
        return r;
      }
      if (!HOLDER_RTS.contains(holders[0].RecordType.DeveloperName)) {
        r.outcome = 'INVALID';
        r.message = MSG_HOLDER_TYPE;
        return r;
      }
      holder = holders[0];
    }

    if (input.sources == null || input.sources.isEmpty()) {
      r.outcome = 'EMPTY';
      r.message = MSG_NO_SOURCES;
      return r;
    }

    // ---- reads: sources by kind, then the persisted links, then the framed keys ----
    Map<Id, SObject> sources = new Map<Id, SObject>();
    Map<Integer, String> kinds = new Map<Integer, String>();
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    Set<Id> seen = new Set<Id>();
    for (SourceRef ref : input.sources) {
      SourceApplyView v = new SourceApplyView();
      v.sourceId = ref == null ? null : ref.sourceId;
      v.kind = ref == null ? null : ref.kind;
      Integer idx = r.details.size();
      r.details.add(v);
      String k = normalizeKind(v.kind);
      if (v.sourceId == null || k == null) {
        ignore(v, MSG_SOURCE_INCOMPLETE);
        continue;
      }
      // Dedupe: the same source informed twice is processed once, so the batch never
      // carries two writes for the same record.
      if (!seen.add(v.sourceId)) {
        ignore(v, MSG_DUPLICATE_SOURCE);
        continue;
      }
      kinds.put(idx, k);
      if (k == 'BANK') {
        bankIds.add(v.sourceId);
      } else {
        cardIds.add(v.sourceId);
      }
    }
    Map<Id, SObject> bankRows = readSources('BANK', bankIds);
    Map<Id, SObject> cardRows = readSources('CARD', cardIds);
    sources.putAll(bankRows);
    sources.putAll(cardRows);

    Map<Id, AXF_OBJ_AccountHolder__c> confirmed = activePrimaryBySource(
      'BANK',
      bankIds
    );
    confirmed.putAll(activePrimaryBySource('CARD', cardIds));

    // framed keys for every eligible source: one lookup instead of one per source
    Map<Integer, String> framedKeys = new Map<Integer, String>();
    Set<String> keys = new Set<String>();
    for (Integer idx : kinds.keySet()) {
      SourceApplyView v = r.details[idx];
      SObject source = sources.get(v.sourceId);
      if (source == null) {
        ignore(v, MSG_SOURCE_NOT_FOUND);
        continue;
      }
      v.priorAvailability = (String) source.get(
        availabilityField(kinds.get(idx))
      );
      v.priorVersion = safeInt(
        (Decimal) source.get(versionField(kinds.get(idx)))
      );
      v.priorHolderId = (Id) source.get(holderField(kinds.get(idx)));
      v.priorOwnerId = (Id) source.get('OwnerId');
      v.priorBankId = (Id) source.get(bankField(kinds.get(idx)));
      v.availabilityState = v.priorAvailability;
      v.version = v.priorVersion;
      if (
        String.isBlank((String) source.get(pluggyField(kinds.get(idx)))) ||
        (Id) source.get(connectionField(kinds.get(idx))) != input.connectionId
      ) {
        ignore(v, MSG_SOURCE_INCOMPLETE);
        continue;
      }
      if (
        input.sources[idx].expectedVersion != null &&
        input.sources[idx].expectedVersion != v.priorVersion
      ) {
        v.outcome = ApplyClass.CONFLICT.name();
        v.message = MSG_CONFLICT;
        r.conflicts++;
        continue;
      }
      if (holder != null) {
        String key = framed(holder.Id, kinds.get(idx), v.sourceId, 'PRIMARY');
        framedKeys.put(idx, key);
        keys.add(key);
      }
    }
    Map<String, AXF_OBJ_AccountHolder__c> existingAch = achByFramedKey(keys);

    // ---- decide + build every write, still with no DML ----
    List<AXF_OBJ_AccountHolder__c> achUpserts = new List<AXF_OBJ_AccountHolder__c>();
    List<Integer> achIndex = new List<Integer>();
    List<SObject> sourceUpdates = new List<SObject>();
    List<Integer> updateIndex = new List<Integer>();

    for (Integer idx = 0; idx < r.details.size(); idx++) {
      SourceApplyView v = r.details[idx];
      if (v.outcome != null) {
        continue; // incomplete, foreign, absent or stale — already reported
      }
      String k = kinds.get(idx);

      // AC8 — an existing canonical bank that differs from the connection's is
      // preserved and surfaced as an explicit divergence, never silently reused.
      Id bankToApply = null;
      if (input.bankInstitutionId != null) {
        if (v.priorBankId == null) {
          bankToApply = input.bankInstitutionId;
        } else if (v.priorBankId != input.bankInstitutionId) {
          v.bankDivergent = true;
          v.message = MSG_BANK_DIVERGENT;
        }
      }

      if (holder == null) {
        // No holder on the connection: the bank is descriptive and is still applied;
        // without a holder the source stays in CUSTODY and counts as pending.
        if (bankToApply != null) {
          sourceUpdates.add(
            sourceWrite(
              k,
              v.sourceId,
              null,
              null,
              v.priorVersion + 1,
              bankToApply
            )
          );
          updateIndex.add(idx);
          v.outcome = ApplyClass.APPLIED.name();
          v.version = v.priorVersion + 1;
        } else if (v.bankDivergent) {
          v.outcome = ApplyClass.CONFLICT.name();
        } else {
          v.outcome = ApplyClass.REUSED.name();
        }
        continue;
      }

      AXF_OBJ_AccountHolder__c active = confirmed.get(v.sourceId);
      // a CONFIRMED holder different from the connection's is never overwritten
      if (active != null && active.AXF_ACH_LKP_Account__c != holder.Id) {
        v.outcome = ApplyClass.DIVERGENT.name();
        v.message = MSG_DIVERGENT;
        continue;
      }

      Boolean needsLink = (active == null);
      Boolean needsRepair =
        v.priorAvailability != 'AVAILABLE' ||
        v.priorHolderId != holder.Id ||
        v.priorOwnerId != holder.OwnerId;

      if (needsLink) {
        achUpserts.add(
          buildPrimary(
            k,
            v.sourceId,
            holder,
            framedKeys.get(idx),
            existingAch.get(framedKeys.get(idx))
          )
        );
        achIndex.add(idx);
      }
      if (needsLink || needsRepair) {
        sourceUpdates.add(
          sourceWrite(
            k,
            v.sourceId,
            holder,
            'AVAILABLE',
            v.priorVersion + 1,
            bankToApply
          )
        );
        updateIndex.add(idx);
        v.outcome = needsLink
          ? ApplyClass.APPLIED.name()
          : ApplyClass.CORRECTED.name();
        v.availabilityState = 'AVAILABLE';
        v.version = v.priorVersion + 1;
        v.releasedThisRun = true;
      } else if (bankToApply != null) {
        sourceUpdates.add(
          sourceWrite(
            k,
            v.sourceId,
            null,
            null,
            v.priorVersion + 1,
            bankToApply
          )
        );
        updateIndex.add(idx);
        v.outcome = ApplyClass.APPLIED.name();
        v.version = v.priorVersion + 1;
      } else if (v.bankDivergent) {
        // Nothing was written, but this is a divergence to review — never a reuse.
        v.outcome = ApplyClass.CONFLICT.name();
      } else {
        v.outcome = ApplyClass.REUSED.name();
      }
    }

    // ---- write: the pair (source + definitive link) is effectively atomic ----
    // The source goes first and the link second, so a refused link never leaves a
    // CONFIRMED row pointing at a source still in custody: the source write is reverted
    // in the same transaction instead (AC6). Both batches carry per-record results, so
    // one refused source never discards the others.
    if (!sourceUpdates.isEmpty()) {
      Database.SaveResult[] upResults = Database.update(
        sourceUpdates,
        false,
        AccessLevel.SYSTEM_MODE
      );
      for (Integer i = 0; i < upResults.size(); i++) {
        if (!upResults[i].isSuccess()) {
          refuse(r.details[updateIndex[i]]);
        }
      }
    }
    if (!achUpserts.isEmpty()) {
      List<AXF_OBJ_AccountHolder__c> linkable = new List<AXF_OBJ_AccountHolder__c>();
      List<Integer> linkableIndex = new List<Integer>();
      for (Integer i = 0; i < achUpserts.size(); i++) {
        // a source whose own write was refused never gets a link written for it
        if (r.details[achIndex[i]].outcome != ApplyClass.FAILED.name()) {
          linkable.add(achUpserts[i]);
          linkableIndex.add(achIndex[i]);
        }
      }
      if (!linkable.isEmpty()) {
        Database.UpsertResult[] achResults = Database.upsert(
          linkable,
          AXF_OBJ_AccountHolder__c.AXF_ACH_EXI_FramedKey__c,
          false,
          AccessLevel.SYSTEM_MODE
        );
        List<SObject> reverts = new List<SObject>();
        for (Integer i = 0; i < achResults.size(); i++) {
          if (achResults[i].isSuccess()) {
            continue;
          }
          SourceApplyView v = r.details[linkableIndex[i]];
          reverts.add(restoreSource(kinds.get(linkableIndex[i]), v));
          refuse(v);
        }
        if (!reverts.isEmpty()) {
          Database.update(reverts, false, AccessLevel.SYSTEM_MODE);
        }
      }
    }

    for (SourceApplyView v : r.details) {
      if (v.bankDivergent == true) {
        r.bankDivergent++;
      }
      String outcome = v.outcome;
      if (outcome == ApplyClass.APPLIED.name()) {
        r.applied++;
      } else if (outcome == ApplyClass.REUSED.name()) {
        r.reused++;
      } else if (outcome == ApplyClass.CORRECTED.name()) {
        r.corrected++;
      } else if (outcome == ApplyClass.DIVERGENT.name()) {
        r.divergent++;
      } else if (outcome == ApplyClass.IGNORED.name()) {
        r.ignored++;
      } else if (outcome == ApplyClass.FAILED.name()) {
        r.failed++;
      }
      // The counters state what THIS run did, never the state it inherited (AXF-106): only
      // a source this batch really linked and released counts as released, so a source
      // that was already AVAILABLE and merely reused, and a source whose write was refused
      // and rolled back, are never reported as a release (AC6). Whatever is left outside
      // AVAILABLE stays visible as pending.
      if (v.releasedThisRun == true) {
        r.released++;
      } else if (
        v.availabilityState != null &&
        v.availabilityState != 'AVAILABLE'
      ) {
        r.pending++;
      }
    }

    // A refusal is never hidden behind a success marker (AC6).
    if (r.failed > 0) {
      r.outcome = ApplyClass.FAILED.name();
    } else if (r.applied > 0) {
      r.outcome = ApplyClass.APPLIED.name();
    } else if (r.corrected > 0) {
      r.outcome = ApplyClass.CORRECTED.name();
    } else if (r.divergent > 0) {
      r.outcome = ApplyClass.DIVERGENT.name();
    } else if (r.conflicts > 0 || r.bankDivergent > 0) {
      r.outcome = ApplyClass.CONFLICT.name();
    } else if (r.reused > 0) {
      r.outcome = ApplyClass.REUSED.name();
    } else {
      r.outcome = ApplyClass.IGNORED.name();
    }
    // Every counter is always stated, so a failure or a divergence can never be
    // summarised away as a plain success.
    r.message =
      r.applied +
      ' aplicada(s), ' +
      r.reused +
      ' reutilizada(s), ' +
      r.corrected +
      ' corrigida(s), ' +
      r.released +
      ' liberada(s) com titular, ' +
      r.pending +
      ' pendente(s), ' +
      r.divergent +
      ' divergente(s) de titular, ' +
      r.bankDivergent +
      ' com banco divergente, ' +
      r.ignored +
      ' ignorada(s), ' +
      r.conflicts +
      ' em conflito de versao e ' +
      r.failed +
      ' com falha.';
    return r;
  }

  // ================= internals =================
  private void bucket(Overview o, SourceView v) {
    if (v.availabilityState == 'AVAILABLE' && v.holderId != null) {
      o.released.add(v);
    } else {
      o.pending.add(v);
    }
  }

  private void ensureAvailable(
    String k,
    SObject source,
    Account holder,
    Integer currentVersion
  ) {
    if ((String) source.get(availabilityField(k)) == 'AVAILABLE') {
      return;
    }
    SObject u = source.getSObjectType().newSObject(source.Id);
    u.put(holderField(k), holder.Id);
    u.put('OwnerId', holder.OwnerId);
    u.put(availabilityField(k), 'AVAILABLE');
    u.put(versionField(k), currentVersion + 1);
    Database.update(u, AccessLevel.SYSTEM_MODE);
  }

  private AXF_OBJ_AccountHolder__c upsertPrimary(
    String k,
    Id sourceId,
    Account holder
  ) {
    String key = framed(holder.Id, k, sourceId, 'PRIMARY');
    return buildPrimary(
      k,
      sourceId,
      holder,
      key,
      achByFramedKey(new Set<String>{ key }).get(key)
    );
  }

  /** @description PRIMARY/CONFIRMED ACH row for one source and holder (AXF-85 rules). */
  private static AXF_OBJ_AccountHolder__c buildPrimary(
    String k,
    Id sourceId,
    Account holder,
    String key,
    AXF_OBJ_AccountHolder__c existing
  ) {
    AXF_OBJ_AccountHolder__c ach;
    if (existing == null) {
      ach = new AXF_OBJ_AccountHolder__c(
        OwnerId = holder.OwnerId,
        AXF_ACH_LKP_Account__c = holder.Id,
        AXF_ACH_PKL_Role__c = 'PRIMARY',
        AXF_ACH_PKL_State__c = 'CONFIRMED',
        AXF_ACH_DAT_ValidFrom__c = Date.today(),
        AXF_ACH_NUM_Version__c = 1,
        AXF_ACH_EXI_FramedKey__c = key
      );
    } else {
      // holder re-confirmed after a prior correction back-and-forth
      ach = existing;
      ach.AXF_ACH_EXI_FramedKey__c = key;
      ach.AXF_ACH_PKL_State__c = 'CONFIRMED';
      ach.AXF_ACH_DAT_ValidTo__c = null;
      ach.AXF_ACH_DAT_ValidFrom__c = Date.today();
      ach.AXF_ACH_NUM_Version__c = safeInt(ach.AXF_ACH_NUM_Version__c) + 1;
    }
    if (k == 'BANK') {
      ach.AXF_ACH_LKP_BankAccount__c = sourceId;
    } else {
      ach.AXF_ACH_LKP_CreditCard__c = sourceId;
    }
    return ach;
  }

  private Map<String, AXF_OBJ_AccountHolder__c> achByFramedKey(
    Set<String> keys
  ) {
    Map<String, AXF_OBJ_AccountHolder__c> out = new Map<String, AXF_OBJ_AccountHolder__c>();
    if (keys.isEmpty()) {
      return out;
    }
    for (AXF_OBJ_AccountHolder__c row : [
      SELECT
        Id,
        AXF_ACH_EXI_FramedKey__c,
        AXF_ACH_NUM_Version__c,
        AXF_ACH_PKL_State__c,
        AXF_ACH_DAT_ValidTo__c
      FROM AXF_OBJ_AccountHolder__c
      WHERE AXF_ACH_EXI_FramedKey__c IN :keys
      WITH SYSTEM_MODE
    ]) {
      out.put(row.AXF_ACH_EXI_FramedKey__c, row);
    }
    return out;
  }

  private AXF_OBJ_AccountHolder__c activePrimary(String k, Id sourceId) {
    return activePrimaryBySource(k, new Set<Id>{ sourceId }).get(sourceId);
  }

  /** @description Every CURRENT PRIMARY/CONFIRMED link for the given sources, in one read. */
  private static Map<Id, AXF_OBJ_AccountHolder__c> activePrimaryBySource(
    String k,
    Set<Id> sourceIds
  ) {
    Map<Id, AXF_OBJ_AccountHolder__c> out = new Map<Id, AXF_OBJ_AccountHolder__c>();
    if (sourceIds.isEmpty()) {
      return out;
    }
    if (k == 'BANK') {
      for (AXF_OBJ_AccountHolder__c row : [
        SELECT
          Id,
          AXF_ACH_LKP_Account__c,
          AXF_ACH_LKP_BankAccount__c,
          AXF_ACH_NUM_Version__c,
          AXF_ACH_PKL_State__c,
          AXF_ACH_DAT_ValidTo__c
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_LKP_BankAccount__c IN :sourceIds
          AND AXF_ACH_PKL_Role__c = 'PRIMARY'
          AND AXF_ACH_PKL_State__c = 'CONFIRMED'
          AND (AXF_ACH_DAT_ValidTo__c = NULL
          OR AXF_ACH_DAT_ValidTo__c >= TODAY)
        WITH SYSTEM_MODE
        ORDER BY AXF_ACH_DAT_ValidFrom__c DESC
      ]) {
        if (!out.containsKey(row.AXF_ACH_LKP_BankAccount__c)) {
          out.put(row.AXF_ACH_LKP_BankAccount__c, row);
        }
      }
      return out;
    }
    for (AXF_OBJ_AccountHolder__c row : [
      SELECT
        Id,
        AXF_ACH_LKP_Account__c,
        AXF_ACH_LKP_CreditCard__c,
        AXF_ACH_NUM_Version__c,
        AXF_ACH_PKL_State__c,
        AXF_ACH_DAT_ValidTo__c
      FROM AXF_OBJ_AccountHolder__c
      WHERE
        AXF_ACH_LKP_CreditCard__c IN :sourceIds
        AND AXF_ACH_PKL_Role__c = 'PRIMARY'
        AND AXF_ACH_PKL_State__c = 'CONFIRMED'
        AND (AXF_ACH_DAT_ValidTo__c = NULL
        OR AXF_ACH_DAT_ValidTo__c >= TODAY)
      WITH SYSTEM_MODE
      ORDER BY AXF_ACH_DAT_ValidFrom__c DESC
    ]) {
      if (!out.containsKey(row.AXF_ACH_LKP_CreditCard__c)) {
        out.put(row.AXF_ACH_LKP_CreditCard__c, row);
      }
    }
    return out;
  }

  private Id reloadAchId(String k, Id sourceId, Id holderId) {
    String key = framed(holderId, k, sourceId, 'PRIMARY');
    List<AXF_OBJ_AccountHolder__c> rows = [
      SELECT Id
      FROM AXF_OBJ_AccountHolder__c
      WHERE AXF_ACH_EXI_FramedKey__c = :key
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }

  private SObject readSource(String k, Id sourceId) {
    return readSources(k, new Set<Id>{ sourceId }).get(sourceId);
  }

  /**
   * @description Sources by Id, in one read per kind. Carries the fields the holder
   * views need plus the discovery identity the batch application validates (AXF-106):
   * PluggyAccountId, connection and the canonical bank lookup.
   */
  private static Map<Id, SObject> readSources(String k, Set<Id> sourceIds) {
    Map<Id, SObject> out = new Map<Id, SObject>();
    if (sourceIds.isEmpty()) {
      return out;
    }
    if (k == 'BANK') {
      for (AXF_OBJ_BankAccount__c b : [
        SELECT
          Id,
          OwnerId,
          AXF_BA_LKP_Account__c,
          AXF_BA_LKP_Account__r.Name,
          AXF_BA_TXT_InstitutionName__c,
          AXF_BA_LKP_BankInstitution__c,
          AXF_BA_LKP_BankInstitution__r.Name,
          AXF_BA_TXT_NumberMasked__c,
          AXF_BA_TXT_CurrencyIsoCode__c,
          AXF_BA_PKL_AvailabilityState__c,
          AXF_BA_NUM_Version__c,
          AXF_BA_EXI_PluggyAccountId__c,
          AXF_BA_LKP_Connection__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id IN :sourceIds
        WITH SYSTEM_MODE
      ]) {
        out.put(b.Id, b);
      }
      return out;
    }
    for (AXF_OBJ_CreditCard__c c : [
      SELECT
        Id,
        OwnerId,
        AXF_CC_LKP_Account__c,
        AXF_CC_LKP_Account__r.Name,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_LKP_BankInstitution__c,
        AXF_CC_LKP_BankInstitution__r.Name,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_NUM_Version__c,
        AXF_CC_EXI_PluggyAccountId__c,
        AXF_CC_LKP_Connection__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id IN :sourceIds
      WITH SYSTEM_MODE
    ]) {
      out.put(c.Id, c);
    }
    return out;
  }

  // ---- views ----
  private static SourceView bankView(AXF_OBJ_BankAccount__c b) {
    SourceView v = new SourceView();
    v.sourceId = b.Id;
    v.kind = 'BANK';
    v.institutionName = b.AXF_BA_TXT_InstitutionName__c;
    v.bankInstitutionName = b.AXF_BA_LKP_BankInstitution__r == null
      ? null
      : b.AXF_BA_LKP_BankInstitution__r.Name;
    v.maskedNumber = b.AXF_BA_TXT_NumberMasked__c;
    v.currencyIsoCode = b.AXF_BA_TXT_CurrencyIsoCode__c;
    v.availabilityState = b.AXF_BA_PKL_AvailabilityState__c;
    v.version = safeInt(b.AXF_BA_NUM_Version__c);
    v.holderId = b.AXF_BA_LKP_Account__c;
    v.holderName = b.AXF_BA_LKP_Account__r != null
      ? b.AXF_BA_LKP_Account__r.Name
      : null;
    return v;
  }

  private static SourceView cardView(AXF_OBJ_CreditCard__c c) {
    SourceView v = new SourceView();
    v.sourceId = c.Id;
    v.kind = 'CARD';
    v.institutionName = c.AXF_CC_TXT_InstitutionName__c;
    v.bankInstitutionName = c.AXF_CC_LKP_BankInstitution__r == null
      ? null
      : c.AXF_CC_LKP_BankInstitution__r.Name;
    v.maskedNumber = c.AXF_CC_TXT_LastFourMasked__c;
    v.currencyIsoCode = c.AXF_CC_TXT_CurrencyIsoCode__c;
    v.availabilityState = c.AXF_CC_PKL_AvailabilityState__c;
    v.version = safeInt(c.AXF_CC_NUM_Version__c);
    v.holderId = c.AXF_CC_LKP_Account__c;
    v.holderName = c.AXF_CC_LKP_Account__r != null
      ? c.AXF_CC_LKP_Account__r.Name
      : null;
    return v;
  }

  // ---- field-name helpers ----
  private static String holderField(String k) {
    return k == 'BANK' ? 'AXF_BA_LKP_Account__c' : 'AXF_CC_LKP_Account__c';
  }
  private static String availabilityField(String k) {
    return k == 'BANK'
      ? 'AXF_BA_PKL_AvailabilityState__c'
      : 'AXF_CC_PKL_AvailabilityState__c';
  }
  private static String versionField(String k) {
    return k == 'BANK' ? 'AXF_BA_NUM_Version__c' : 'AXF_CC_NUM_Version__c';
  }
  private static String bankField(String k) {
    return k == 'BANK'
      ? 'AXF_BA_LKP_BankInstitution__c'
      : 'AXF_CC_LKP_BankInstitution__c';
  }
  private static String pluggyField(String k) {
    return k == 'BANK'
      ? 'AXF_BA_EXI_PluggyAccountId__c'
      : 'AXF_CC_EXI_PluggyAccountId__c';
  }
  private static String connectionField(String k) {
    return k == 'BANK'
      ? 'AXF_BA_LKP_Connection__c'
      : 'AXF_CC_LKP_Connection__c';
  }

  /**
   * @description Source payload of a discovery application (AXF-106). Only the fields
   * the batch actually applies are set; a null holder/bank never clears a value, and
   * the provider identity, currency, balances and discovered-at are left alone.
   */
  private static SObject sourceWrite(
    String k,
    Id sourceId,
    Account holder,
    String availability,
    Integer version,
    Id bankInstitutionId
  ) {
    SObject u = (k == 'BANK'
        ? AXF_OBJ_BankAccount__c.SObjectType
        : AXF_OBJ_CreditCard__c.SObjectType)
      .newSObject(sourceId);
    if (holder != null) {
      u.put(holderField(k), holder.Id);
      u.put('OwnerId', holder.OwnerId);
    }
    if (availability != null) {
      u.put(availabilityField(k), availability);
    }
    if (bankInstitutionId != null) {
      u.put(bankField(k), bankInstitutionId);
    }
    u.put(versionField(k), version);
    return u;
  }

  // ---- batch-result helpers (AXF-106) ----
  private static void ignore(SourceApplyView v, String message) {
    v.outcome = ApplyClass.IGNORED.name();
    v.message = message;
  }

  /** @description A refused write: the source keeps the state it had before the batch. */
  private static void refuse(SourceApplyView v) {
    v.outcome = ApplyClass.FAILED.name();
    v.message = MSG_APPLY_FAILED;
    v.availabilityState = v.priorAvailability;
    v.version = v.priorVersion;
    // a refused write released nothing, whatever the batch intended for this source
    v.releasedThisRun = false;
  }

  /**
   * @description Undo the source write of this batch when the definitive link could not
   * be written (AC6). Only the fields this batch touched are restored, so a release is
   * never left without its link. Runs in the same transaction as the write being undone.
   */
  private static SObject restoreSource(String k, SourceApplyView v) {
    SObject u = (k == 'BANK'
        ? AXF_OBJ_BankAccount__c.SObjectType
        : AXF_OBJ_CreditCard__c.SObjectType)
      .newSObject(v.sourceId);
    u.put(holderField(k), v.priorHolderId);
    u.put('OwnerId', v.priorOwnerId);
    u.put(bankField(k), v.priorBankId);
    u.put(availabilityField(k), v.priorAvailability);
    u.put(versionField(k), v.priorVersion);
    return u;
  }

  private static String normalizeKind(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String k = raw.trim().toUpperCase();
    return (k == 'BANK' || k == 'CARD') ? k : null;
  }

  // ---- framed identity key — same algorithm as AXF-86 (G6) ----
  private static String framed(Id h, String t, Id id, String role) {
    return frame(String.valueOf(h)) +
      frame(t) +
      frame(String.valueOf(id)) +
      frame(role);
  }
  private static String frame(String s) {
    return s.length() + ':' + s;
  }

  private static Integer safeInt(Decimal d) {
    return d == null ? 0 : d.intValue();
  }

  // ---- result builders ----
  private static ConfirmResult done(
    Outcome o,
    String msg,
    Id sourceId,
    Id achId,
    Integer version,
    String availability
  ) {
    ConfirmResult r = new ConfirmResult();
    r.outcome = o.name();
    r.message = msg;
    r.sourceId = sourceId;
    r.accountHolderId = achId;
    r.version = version;
    r.availabilityState = availability;
    return r;
  }
  private static ConfirmResult err(Outcome o, String msg) {
    ConfirmResult r = new ConfirmResult();
    r.outcome = o.name();
    r.message = msg;
    return r;
  }
  private static ConfirmResult invalid(String field, String msg) {
    ConfirmResult r = err(Outcome.INVALID, msg);
    r.invalidFields.add(field);
    return r;
  }

  // ---- PT-BR messages (MVP) ----
  @TestVisible
  private static final String MSG_FORBIDDEN = 'Você não tem autorização para confirmar titulares de fontes financeiras.';
  @TestVisible
  private static final String MSG_INVALID = 'Selecione a fonte, o tipo e o titular.';
  @TestVisible
  private static final String MSG_NEED_VERSION = 'Informe a versão esperada da fonte.';
  @TestVisible
  private static final String MSG_HOLDER_NOT_FOUND = 'O titular não foi encontrado ou você não tem acesso a ele.';
  @TestVisible
  private static final String MSG_HOLDER_TYPE = 'O titular precisa ser uma pessoa ou empresa cadastrada.';
  @TestVisible
  private static final String MSG_SOURCE_NOT_FOUND = 'A fonte não foi encontrada ou você não tem acesso a ela.';
  @TestVisible
  private static final String MSG_CONFLICT = 'A fonte foi alterada em outra sessão. Recarregue antes de confirmar.';
  @TestVisible
  private static final String MSG_ALREADY = 'Este titular já estava confirmado nesta fonte.';
  @TestVisible
  private static final String MSG_CONFIRMED = 'Titular confirmado. A fonte foi liberada para uso.';
  @TestVisible
  private static final String MSG_CORRECTED = 'Titular corrigido. O vínculo anterior foi mantido no histórico.';
  // ---- discovery application (AXF-106) ----
  @TestVisible
  private static final String MSG_BANK_REF_UNUSABLE = 'A instituição financeira definida na conexão não foi encontrada ou você não tem acesso a ela. Nada foi aplicado às fontes.';
  @TestVisible
  private static final String MSG_DIVERGENT = 'Esta fonte já tem outro titular confirmado. Nada foi sobrescrito: resolva a divergência antes de aplicar o titular da conexão.';
  @TestVisible
  private static final String MSG_SOURCE_INCOMPLETE = 'Fonte sem identificação Pluggy ou fora desta conexão. Nada foi aplicado.';
  @TestVisible
  private static final String MSG_NO_SOURCES = 'Nenhuma fonte desta conexão para aplicar.';
  @TestVisible
  private static final String MSG_APPLY_FAILED = 'Não foi possível aplicar o banco e o titular nesta fonte. Nada foi sobrescrito.';
  @TestVisible
  private static final String MSG_BANK_DIVERGENT = 'O banco gravado nesta fonte difere do banco da conexão. O valor existente foi preservado; revise a divergência explicitamente.';
  @TestVisible
  private static final String MSG_DUPLICATE_SOURCE = 'Fonte informada mais de uma vez nesta aplicação. A entrada repetida foi ignorada.';
}
