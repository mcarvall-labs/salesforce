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
  }

  public class Overview {
    @AuraEnabled
    public Boolean forbidden = false;
    @AuraEnabled
    public List<SourceView> pending = new List<SourceView>();
    @AuraEnabled
    public List<SourceView> released = new List<SourceView>();
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

  // ================= public API =================
  public Overview overview() {
    Overview o = new Overview();
    if (!callerCanConfigure()) {
      o.forbidden = true;
      return o;
    }
    for (AXF_OBJ_BankAccount__c b : [
      SELECT
        Id,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_TXT_NumberMasked__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_NUM_Version__c,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_Account__r.Name
      FROM AXF_OBJ_BankAccount__c
      WITH SYSTEM_MODE
      ORDER BY AXF_BA_TXT_InstitutionName__c
    ]) {
      SourceView v = bankView(b);
      bucket(o, v);
    }
    for (AXF_OBJ_CreditCard__c c : [
      SELECT
        Id,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_NUM_Version__c,
        AXF_CC_LKP_Account__c,
        AXF_CC_LKP_Account__r.Name
      FROM AXF_OBJ_CreditCard__c
      WITH SYSTEM_MODE
      ORDER BY AXF_CC_TXT_InstitutionName__c
    ]) {
      SourceView v = cardView(c);
      bucket(o, v);
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

    AXF_OBJ_AccountHolder__c ach = upsertPrimary(k, input, holder);
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
    ConfirmInput input,
    Account holder
  ) {
    String key = framed(holder.Id, k, input.sourceId, 'PRIMARY');
    List<AXF_OBJ_AccountHolder__c> existing = [
      SELECT
        Id,
        AXF_ACH_NUM_Version__c,
        AXF_ACH_PKL_State__c,
        AXF_ACH_DAT_ValidTo__c
      FROM AXF_OBJ_AccountHolder__c
      WHERE AXF_ACH_EXI_FramedKey__c = :key
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    AXF_OBJ_AccountHolder__c ach;
    if (existing.isEmpty()) {
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
      ach = existing[0];
      ach.AXF_ACH_EXI_FramedKey__c = key;
      ach.AXF_ACH_PKL_State__c = 'CONFIRMED';
      ach.AXF_ACH_DAT_ValidTo__c = null;
      ach.AXF_ACH_DAT_ValidFrom__c = Date.today();
      ach.AXF_ACH_NUM_Version__c = safeInt(ach.AXF_ACH_NUM_Version__c) + 1;
    }
    if (k == 'BANK') {
      ach.AXF_ACH_LKP_BankAccount__c = input.sourceId;
    } else {
      ach.AXF_ACH_LKP_CreditCard__c = input.sourceId;
    }
    return ach;
  }

  private AXF_OBJ_AccountHolder__c activePrimary(String k, Id sourceId) {
    String field = k == 'BANK'
      ? 'AXF_ACH_LKP_BankAccount__c'
      : 'AXF_ACH_LKP_CreditCard__c';
    List<AXF_OBJ_AccountHolder__c> rows = Database.query(
      'SELECT Id, AXF_ACH_LKP_Account__c, AXF_ACH_NUM_Version__c, ' +
        'AXF_ACH_PKL_State__c, AXF_ACH_DAT_ValidTo__c ' +
        'FROM AXF_OBJ_AccountHolder__c ' +
        'WHERE ' +
        field +
        ' = :sourceId AND AXF_ACH_PKL_Role__c = \'PRIMARY\' ' +
        'AND AXF_ACH_PKL_State__c = \'CONFIRMED\' ' +
        'AND (AXF_ACH_DAT_ValidTo__c = null OR AXF_ACH_DAT_ValidTo__c >= TODAY) ' +
        'ORDER BY AXF_ACH_DAT_ValidFrom__c DESC LIMIT 1',
      AccessLevel.SYSTEM_MODE
    );
    return rows.isEmpty() ? null : rows[0];
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
    if (k == 'BANK') {
      List<AXF_OBJ_BankAccount__c> rows = [
        SELECT
          Id,
          OwnerId,
          AXF_BA_LKP_Account__c,
          AXF_BA_LKP_Account__r.Name,
          AXF_BA_TXT_InstitutionName__c,
          AXF_BA_TXT_NumberMasked__c,
          AXF_BA_TXT_CurrencyIsoCode__c,
          AXF_BA_PKL_AvailabilityState__c,
          AXF_BA_NUM_Version__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :sourceId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      return rows.isEmpty() ? null : rows[0];
    }
    List<AXF_OBJ_CreditCard__c> rows = [
      SELECT
        Id,
        OwnerId,
        AXF_CC_LKP_Account__c,
        AXF_CC_LKP_Account__r.Name,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_NUM_Version__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :sourceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  // ---- views ----
  private static SourceView bankView(AXF_OBJ_BankAccount__c b) {
    SourceView v = new SourceView();
    v.sourceId = b.Id;
    v.kind = 'BANK';
    v.institutionName = b.AXF_BA_TXT_InstitutionName__c;
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
}
