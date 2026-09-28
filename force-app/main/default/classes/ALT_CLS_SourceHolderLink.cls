/**
 * @description Holder linkage of Pluggy-discovered sources over the legacy PROD model.
 *
 * The legacy model has no custody state, holder junction or record version: the holder
 * of a bank account / credit card is its Account lookup (AXF_BA_LKP_Account__c /
 * AXF_CC_LKP_Account__c). A source linked to a Pluggy connection without that lookup is
 * pending; with it, it is released. Divergence does not exist in this model, so the
 * divergent list is always empty and the version is always 0.
 *
 * Authority: reads and writes require the AXF_CanConfigure custom permission; every
 * query and DML runs in USER_MODE (object CRUD, FLS and sharing).
 */
public with sharing class ALT_CLS_SourceHolderLink {
  public static final String KIND_BANK = 'BANK';
  public static final String KIND_CARD = 'CARD';
  public static final String STATE_AVAILABLE = 'AVAILABLE';
  public static final String STATE_CUSTODY = 'CUSTODY';
  public static final Set<String> HOLDER_RECORD_TYPES = new Set<String>{
    'AXF_Business',
    'PersonAccount'
  };
  private static final Integer MAX_ROWS = 1000;

  @TestVisible
  private static Boolean canConfigureOverride;
  @TestVisible
  private static String lastFailure;

  public static Boolean canConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  /**
   * @description Returns the accessible holder Account (AXF_Business or PersonAccount), or
   * null when the id is not an Account, not a holder or not visible to the caller.
   */
  public static Account findHolder(Id holderId) {
    if (holderId == null || holderId.getSObjectType() != Account.SObjectType) {
      return null;
    }
    Set<String> recordTypes = HOLDER_RECORD_TYPES;
    List<Account> rows = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :holderId AND RecordType.DeveloperName IN :recordTypes
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /** @description Masks an account/card number, keeping at most the last four characters. */
  public static String mask(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String clean = value.trim();
    return '•••• ' + (clean.length() > 4 ? clean.right(4) : clean);
  }

  public AXF_CLS_SourceSetupDTO.HolderOverview overview() {
    AXF_CLS_SourceSetupDTO.HolderOverview o = new AXF_CLS_SourceSetupDTO.HolderOverview();
    if (!canConfigure()) {
      o.forbidden = true;
      return o;
    }
    List<AXF_OBJ_BankAccount__c> accounts = [
      SELECT
        Id,
        AXF_BA_LKP_PluggyConnection__c,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_Account__r.Name,
        AXF_BA_LKP_BankInstitution__r.Name,
        AXF_BA_TXT_AccountNumber__c,
        AXF_BA_PKL_Currency__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_PluggyConnection__c != NULL
      WITH USER_MODE
      ORDER BY Name
      LIMIT :MAX_ROWS
    ];
    List<AXF_OBJ_CreditCard__c> cards = [
      SELECT
        Id,
        AXF_CC_LKP_PluggyConnection__c,
        AXF_CC_LKP_Account__c,
        AXF_CC_LKP_Account__r.Name,
        AXF_CC_LKP_BankInstitution__r.Name,
        AXF_CC_TXT_LastFourDigits__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_PluggyConnection__c != NULL
      WITH USER_MODE
      ORDER BY Name
      LIMIT :MAX_ROWS
    ];
    // The connection's holder is whichever holder its own sources already carry
    // (same rule as ALT_CLS_PluggySourceSetup.applyHolder): a still-pending source
    // of a connection that already has a confirmed sibling is pre-filled with that
    // same holder, never left blank for no reason.
    Map<Id, Id> holderIdByConnection = new Map<Id, Id>();
    Map<Id, String> holderNameByConnection = new Map<Id, String>();
    for (AXF_OBJ_BankAccount__c ba : accounts) {
      if (
        ba.AXF_BA_LKP_Account__c != null &&
        !holderIdByConnection.containsKey(ba.AXF_BA_LKP_PluggyConnection__c)
      ) {
        holderIdByConnection.put(
          ba.AXF_BA_LKP_PluggyConnection__c,
          ba.AXF_BA_LKP_Account__c
        );
        holderNameByConnection.put(
          ba.AXF_BA_LKP_PluggyConnection__c,
          ba.AXF_BA_LKP_Account__r?.Name
        );
      }
    }
    for (AXF_OBJ_CreditCard__c cc : cards) {
      if (
        cc.AXF_CC_LKP_Account__c != null &&
        !holderIdByConnection.containsKey(cc.AXF_CC_LKP_PluggyConnection__c)
      ) {
        holderIdByConnection.put(
          cc.AXF_CC_LKP_PluggyConnection__c,
          cc.AXF_CC_LKP_Account__c
        );
        holderNameByConnection.put(
          cc.AXF_CC_LKP_PluggyConnection__c,
          cc.AXF_CC_LKP_Account__r?.Name
        );
      }
    }
    for (AXF_OBJ_BankAccount__c ba : accounts) {
      add(
        o,
        withSuggestion(
          bankView(ba),
          ba.AXF_BA_LKP_PluggyConnection__c,
          holderIdByConnection,
          holderNameByConnection
        )
      );
    }
    for (AXF_OBJ_CreditCard__c cc : cards) {
      add(
        o,
        withSuggestion(
          cardView(cc),
          cc.AXF_CC_LKP_PluggyConnection__c,
          holderIdByConnection,
          holderNameByConnection
        )
      );
    }
    return o;
  }

  private static AXF_CLS_SourceSetupDTO.SourceView withSuggestion(
    AXF_CLS_SourceSetupDTO.SourceView v,
    Id connectionId,
    Map<Id, Id> holderIdByConnection,
    Map<Id, String> holderNameByConnection
  ) {
    if (v.holderId != null) {
      v.suggestedHolderId = v.holderId;
      v.suggestedHolderName = v.holderName;
    } else {
      v.suggestedHolderId = holderIdByConnection.get(connectionId);
      v.suggestedHolderName = holderNameByConnection.get(connectionId);
    }
    return v;
  }

  public AXF_CLS_SourceSetupDTO.ConfirmResult confirmHolder(
    Id sourceId,
    String kind,
    Id holderId
  ) {
    AXF_CLS_SourceSetupDTO.ConfirmResult r = new AXF_CLS_SourceSetupDTO.ConfirmResult();
    r.sourceId = sourceId;
    if (!canConfigure()) {
      return outcome(
        r,
        'FORBIDDEN',
        'Você não tem autorização para confirmar titulares.'
      );
    }
    String sourceKind = kindOf(sourceId);
    if (
      sourceKind == null ||
      (String.isNotBlank(kind) && kind.trim().toUpperCase() != sourceKind)
    ) {
      r.invalidFields.add('sourceId');
      return outcome(r, 'INVALID', 'Selecione uma conta ou cartão válido.');
    }
    Account holder = findHolder(holderId);
    if (holder == null) {
      r.invalidFields.add('holderId');
      return outcome(
        r,
        'INVALID',
        'Selecione um titular válido (pessoa ou empresa).'
      );
    }
    try {
      Id current;
      SObject row;
      if (sourceKind == KIND_BANK) {
        List<AXF_OBJ_BankAccount__c> rows = [
          SELECT Id, AXF_BA_LKP_Account__c
          FROM AXF_OBJ_BankAccount__c
          WHERE Id = :sourceId
          WITH USER_MODE
          LIMIT 1
        ];
        if (rows.isEmpty()) {
          return notFound(r);
        }
        current = rows[0].AXF_BA_LKP_Account__c;
        row = new AXF_OBJ_BankAccount__c(
          Id = sourceId,
          AXF_BA_LKP_Account__c = holder.Id
        );
      } else {
        List<AXF_OBJ_CreditCard__c> rows = [
          SELECT Id, AXF_CC_LKP_Account__c
          FROM AXF_OBJ_CreditCard__c
          WHERE Id = :sourceId
          WITH USER_MODE
          LIMIT 1
        ];
        if (rows.isEmpty()) {
          return notFound(r);
        }
        current = rows[0].AXF_CC_LKP_Account__c;
        row = new AXF_OBJ_CreditCard__c(
          Id = sourceId,
          AXF_CC_LKP_Account__c = holder.Id
        );
      }
      r.accountHolderId = holder.Id;
      r.availabilityState = STATE_AVAILABLE;
      if (current == holder.Id) {
        return outcome(r, 'ALREADY', 'Este titular já está vinculado à fonte.');
      }
      update as user row;
      return current == null
        ? outcome(r, 'CONFIRMED', 'Titular confirmado. A fonte está liberada.')
        : outcome(r, 'CORRECTED', 'Titular corrigido.');
    } catch (Exception e) {
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      r.accountHolderId = null;
      r.availabilityState = null;
      return outcome(
        r,
        'FAILED',
        'Não foi possível confirmar o titular. Nada foi alterado.'
      );
    }
  }

  private static String kindOf(Id sourceId) {
    if (sourceId == null) {
      return null;
    }
    Schema.SObjectType t = sourceId.getSObjectType();
    if (t == AXF_OBJ_BankAccount__c.SObjectType) {
      return KIND_BANK;
    }
    if (t == AXF_OBJ_CreditCard__c.SObjectType) {
      return KIND_CARD;
    }
    return null;
  }

  private static void add(
    AXF_CLS_SourceSetupDTO.HolderOverview o,
    AXF_CLS_SourceSetupDTO.SourceView v
  ) {
    if (v.holderId == null) {
      o.pending.add(v);
    } else {
      o.released.add(v);
    }
  }

  private static AXF_CLS_SourceSetupDTO.SourceView bankView(
    AXF_OBJ_BankAccount__c ba
  ) {
    AXF_CLS_SourceSetupDTO.SourceView v = new AXF_CLS_SourceSetupDTO.SourceView();
    v.sourceId = ba.Id;
    v.kind = KIND_BANK;
    v.institutionName = ba.AXF_BA_LKP_BankInstitution__r?.Name;
    v.bankInstitutionName = v.institutionName;
    v.maskedNumber = mask(ba.AXF_BA_TXT_AccountNumber__c);
    v.currencyIsoCode = String.isBlank(ba.AXF_BA_PKL_Currency__c)
      ? UserInfo.getDefaultCurrency()
      : ba.AXF_BA_PKL_Currency__c;
    return withHolder(
      v,
      ba.AXF_BA_LKP_Account__c,
      ba.AXF_BA_LKP_Account__r?.Name
    );
  }

  private static AXF_CLS_SourceSetupDTO.SourceView cardView(
    AXF_OBJ_CreditCard__c cc
  ) {
    AXF_CLS_SourceSetupDTO.SourceView v = new AXF_CLS_SourceSetupDTO.SourceView();
    v.sourceId = cc.Id;
    v.kind = KIND_CARD;
    v.institutionName = cc.AXF_CC_LKP_BankInstitution__r?.Name;
    v.bankInstitutionName = v.institutionName;
    v.maskedNumber = mask(cc.AXF_CC_TXT_LastFourDigits__c);
    // Legacy credit cards carry no currency: they use the org currency.
    v.currencyIsoCode = UserInfo.getDefaultCurrency();
    return withHolder(
      v,
      cc.AXF_CC_LKP_Account__c,
      cc.AXF_CC_LKP_Account__r?.Name
    );
  }

  private static AXF_CLS_SourceSetupDTO.SourceView withHolder(
    AXF_CLS_SourceSetupDTO.SourceView v,
    Id holderId,
    String holderName
  ) {
    v.holderId = holderId;
    v.holderName = holderName;
    v.accountHolderId = holderId;
    v.availabilityState = holderId == null ? STATE_CUSTODY : STATE_AVAILABLE;
    return v;
  }

  private static AXF_CLS_SourceSetupDTO.ConfirmResult notFound(
    AXF_CLS_SourceSetupDTO.ConfirmResult r
  ) {
    return outcome(
      r,
      'NOT_FOUND',
      'A conta ou o cartão não foi encontrado ou não está acessível.'
    );
  }

  private static AXF_CLS_SourceSetupDTO.ConfirmResult outcome(
    AXF_CLS_SourceSetupDTO.ConfirmResult r,
    String outcome,
    String message
  ) {
    r.outcome = outcome;
    r.message = message;
    return r;
  }
}
