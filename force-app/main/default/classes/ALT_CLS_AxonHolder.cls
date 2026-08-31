/**
 * @description Registers and maintains holder Accounts (Person Account = pessoa,
 * Business Account = empresa) for the Axon configuration administrator.
 *
 * Contract: ARCHITECTURE-SPINE.md "Fechamento G1" (G1-1 — raiz de titular = Account),
 * SCHEMA-DICTIONARY.md "Account como raiz de titular", AD-4 / AD-6 / AD-14. AXF-80.
 *
 * - Titular = Account (pessoa via Record Type AXF_Person / Person Account,
 *   empresa via Record Type AXF_Business). No Household, no FinancialEntity.
 * - Creating a holder never creates a Salesforce user, bank account, credit card
 *   or holder link. Editing descriptive data never changes OwnerId, user link,
 *   business responsibility or economic attribution (AC1 / AC2).
 * - All record access goes through USER_MODE: object CRUD, FLS and sharing are
 *   enforced by the platform, so a client-supplied Id or a hidden button grants
 *   nothing (AC3).
 * - Config authority: the caller must hold the AXF_CanConfigure custom permission
 *   to create or edit. Listing / reading is gated by sharing only (AC4).
 * - Identity & concurrency are handled natively (Michel, 31/08/2026): optimistic
 *   check against LastModifiedDate for stale edits (CONFLICT), same-name records
 *   surfaced as a warning that never auto-merges and never blocks once confirmed
 *   (AC5). No custom Version / identity-key field is added to Account.
 * - User-facing strings are PT-BR literals with a stable `code`; the LWC localizes
 *   PT-BR / EN from the code (AC6).
 */
public with sharing class ALT_CLS_AxonHolder {
  public enum HolderType {
    PERSON,
    BUSINESS
  }

  public enum Outcome {
    SUCCEEDED,
    FORBIDDEN,
    INVALID,
    CONFLICT,
    NOT_FOUND,
    DUPLICATE_WARNING,
    FAILED
  }

  public static final String RT_PERSON = 'AXF_Person';
  public static final String RT_BUSINESS = 'AXF_Business';

  @TestVisible
  private static final String MSG_FORBIDDEN = 'Voce nao tem autorizacao para cadastrar ou editar titulares.';
  @TestVisible
  private static final String MSG_INVALID_TYPE = 'Selecione um tipo de titular valido (Pessoa ou Empresa).';
  @TestVisible
  private static final String MSG_INVALID_PERSON = 'Informe ao menos o sobrenome da pessoa.';
  @TestVisible
  private static final String MSG_INVALID_BUSINESS = 'Informe a razao social ou nome da empresa.';
  @TestVisible
  private static final String MSG_RT_MISSING = 'O tipo de registro de titular nao esta disponivel nesta org. Conclua os passos de instalacao.';
  @TestVisible
  private static final String MSG_NOT_FOUND = 'O titular selecionado nao foi encontrado ou voce nao tem acesso a ele.';
  @TestVisible
  private static final String MSG_CONFLICT = 'Este titular foi alterado por outra pessoa depois que voce abriu a tela. Recarregue e revise antes de salvar.';
  @TestVisible
  private static final String MSG_DUPLICATE = 'Ja existe um titular com este nome. Nomes iguais nao provam que e a mesma pessoa ou empresa. Confirme para cadastrar assim mesmo.';
  @TestVisible
  private static final String MSG_SAVED = 'Titular salvo.';
  @TestVisible
  private static final String MSG_FAILED = 'Nao foi possivel salvar o titular. Nada foi alterado.';

  // ---- read models ----

  public class HolderView {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String type; // PERSON | BUSINESS
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public String lastName;
    @AuraEnabled
    public Boolean isPersonAccount;
    @AuraEnabled
    public Id ownerId;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public Datetime lastModifiedDate;
  }

  public class SaveInput {
    @AuraEnabled
    public Id accountId; // null => create
    @AuraEnabled
    public String type; // PERSON | BUSINESS (create only; ignored on edit)
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public String lastName;
    @AuraEnabled
    public String name; // business
    @AuraEnabled
    public Datetime expectedLastModifiedDate; // edit only
    @AuraEnabled
    public Boolean confirmedDespiteDuplicates;
  }

  public class SaveResult {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<String> invalidFields = new List<String>();
    @AuraEnabled
    public List<HolderView> possibleDuplicates = new List<HolderView>();
  }

  // ---- authority ----

  @TestVisible
  private static Boolean canConfigureOverride;

  private Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  // ---- queries ----

  /**
   * @description Lists holder Accounts visible to the caller, optionally filtered
   * by a name fragment. Sharing + CRUD + FLS enforced by USER_MODE.
   */
  public List<HolderView> listHolders(String search) {
    String pattern =
      '%' +
      String.escapeSingleQuotes((search == null ? '' : search.trim())) +
      '%';
    List<Account> rows = [
      SELECT
        Id,
        Name,
        FirstName,
        LastName,
        IsPersonAccount,
        OwnerId,
        Owner.Name,
        LastModifiedDate,
        RecordType.DeveloperName
      FROM Account
      WHERE
        RecordType.DeveloperName IN (:RT_PERSON, :RT_BUSINESS)
        AND Name LIKE :pattern
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ];
    List<HolderView> views = new List<HolderView>();
    for (Account a : rows) {
      views.add(toView(a));
    }
    return views;
  }

  /**
   * @description Returns a single holder, or null when it is not visible / not a holder.
   */
  public HolderView getHolder(Id accountId) {
    if (
      accountId == null ||
      accountId.getSobjectType() != Account.SObjectType
    ) {
      return null;
    }
    List<Account> rows = [
      SELECT
        Id,
        Name,
        FirstName,
        LastName,
        IsPersonAccount,
        OwnerId,
        Owner.Name,
        LastModifiedDate,
        RecordType.DeveloperName
      FROM Account
      WHERE
        Id = :accountId
        AND RecordType.DeveloperName IN (:RT_PERSON, :RT_BUSINESS)
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : toView(rows[0]);
  }

  // ---- writes ----

  public SaveResult saveHolder(SaveInput input) {
    SaveResult r = new SaveResult();

    if (!callerCanConfigure()) {
      return fail(r, Outcome.FORBIDDEN, MSG_FORBIDDEN);
    }
    if (input == null) {
      return fail(r, Outcome.INVALID, MSG_FAILED);
    }

    return input.accountId == null
      ? createHolder(input, r)
      : updateHolder(input, r);
  }

  private SaveResult createHolder(SaveInput input, SaveResult r) {
    HolderType type = parseType(input.type);
    if (type == null) {
      r.invalidFields.add('type');
      return fail(r, Outcome.INVALID, MSG_INVALID_TYPE);
    }

    Account acc = new Account();
    if (type == HolderType.PERSON) {
      String last = trimToNull(input.lastName);
      if (last == null) {
        r.invalidFields.add('lastName');
        return fail(r, Outcome.INVALID, MSG_INVALID_PERSON);
      }
      acc.LastName = last;
      acc.FirstName = trimToNull(input.firstName);
    } else {
      String bizName = trimToNull(input.name);
      if (bizName == null) {
        r.invalidFields.add('name');
        return fail(r, Outcome.INVALID, MSG_INVALID_BUSINESS);
      }
      acc.Name = bizName;
    }

    Id rtId = recordTypeId(type == HolderType.PERSON ? RT_PERSON : RT_BUSINESS);
    if (rtId == null) {
      return fail(r, Outcome.FAILED, MSG_RT_MISSING);
    }
    acc.RecordTypeId = rtId;

    List<HolderView> dups = findDuplicates(
      type,
      displayName(type, input),
      null
    );
    if (!dups.isEmpty() && input.confirmedDespiteDuplicates != true) {
      r.possibleDuplicates = dups;
      return fail(r, Outcome.DUPLICATE_WARNING, MSG_DUPLICATE);
    }

    try {
      Database.insert(acc, AccessLevel.USER_MODE);
    } catch (Exception e) {
      return fail(r, Outcome.FAILED, MSG_FAILED);
    }

    r.accountId = acc.Id;
    r.outcome = Outcome.SUCCEEDED.name();
    r.message = MSG_SAVED;
    return r;
  }

  private SaveResult updateHolder(SaveInput input, SaveResult r) {
    HolderView current = getHolder(input.accountId);
    if (current == null) {
      return fail(r, Outcome.NOT_FOUND, MSG_NOT_FOUND);
    }
    if (
      input.expectedLastModifiedDate == null ||
      input.expectedLastModifiedDate != current.lastModifiedDate
    ) {
      return fail(r, Outcome.CONFLICT, MSG_CONFLICT);
    }

    HolderType type = current.type == HolderType.PERSON.name()
      ? HolderType.PERSON
      : HolderType.BUSINESS;

    // Only descriptive name fields are ever touched — never OwnerId, never links.
    Account acc = new Account(Id = current.accountId);
    if (type == HolderType.PERSON) {
      String last = trimToNull(input.lastName);
      if (last == null) {
        r.invalidFields.add('lastName');
        return fail(r, Outcome.INVALID, MSG_INVALID_PERSON);
      }
      acc.LastName = last;
      acc.FirstName = trimToNull(input.firstName);
    } else {
      String bizName = trimToNull(input.name);
      if (bizName == null) {
        r.invalidFields.add('name');
        return fail(r, Outcome.INVALID, MSG_INVALID_BUSINESS);
      }
      acc.Name = bizName;
    }

    try {
      Database.update(acc, AccessLevel.USER_MODE);
    } catch (Exception e) {
      return fail(r, Outcome.FAILED, MSG_FAILED);
    }

    r.accountId = acc.Id;
    r.outcome = Outcome.SUCCEEDED.name();
    r.message = MSG_SAVED;
    return r;
  }

  // ---- helpers ----

  @TestVisible
  private List<HolderView> findDuplicates(
    HolderType type,
    String candidateName,
    Id excludeId
  ) {
    String norm = normalize(candidateName);
    if (norm == null) {
      return new List<HolderView>();
    }
    String rtName = type == HolderType.PERSON ? RT_PERSON : RT_BUSINESS;
    List<HolderView> matches = new List<HolderView>();
    for (Account a : [
      SELECT
        Id,
        Name,
        FirstName,
        LastName,
        IsPersonAccount,
        OwnerId,
        Owner.Name,
        LastModifiedDate,
        RecordType.DeveloperName
      FROM Account
      WHERE RecordType.DeveloperName = :rtName
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      if (excludeId != null && a.Id == excludeId) {
        continue;
      }
      if (normalize(a.Name) == norm) {
        matches.add(toView(a));
      }
    }
    return matches;
  }

  private static String normalize(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    return raw.normalizeSpace().toLowerCase();
  }

  private static String displayName(HolderType type, SaveInput input) {
    if (type == HolderType.BUSINESS) {
      return input.name;
    }
    String first = trimToNull(input.firstName);
    String last = trimToNull(input.lastName);
    return first == null ? last : first + ' ' + last;
  }

  private static String trimToNull(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    return raw.trim();
  }

  @TestVisible
  private static HolderType parseType(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String n = raw.trim().toUpperCase();
    for (HolderType t : HolderType.values()) {
      if (t.name() == n) {
        return t;
      }
    }
    return null;
  }

  private static Id recordTypeId(String developerName) {
    Schema.RecordTypeInfo info = Account.SObjectType.getDescribe(
        SObjectDescribeOptions.DEFERRED
      )
      .getRecordTypeInfosByDeveloperName()
      .get(developerName);
    return info == null ? null : info.getRecordTypeId();
  }

  private static HolderView toView(Account a) {
    HolderView v = new HolderView();
    v.accountId = a.Id;
    v.recordTypeDeveloperName = a.RecordType.DeveloperName;
    v.type = a.RecordType.DeveloperName == RT_PERSON
      ? HolderType.PERSON.name()
      : HolderType.BUSINESS.name();
    v.name = a.Name;
    v.firstName = a.FirstName;
    v.lastName = a.LastName;
    v.isPersonAccount = a.IsPersonAccount;
    v.ownerId = a.OwnerId;
    v.ownerName = a.Owner != null ? a.Owner.Name : null;
    v.lastModifiedDate = a.LastModifiedDate;
    return v;
  }

  private static SaveResult fail(
    SaveResult r,
    Outcome outcome,
    String message
  ) {
    r.outcome = outcome.name();
    r.message = message;
    return r;
  }
}
