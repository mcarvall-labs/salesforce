/**
 * @description Manual financial sources (bank account, credit card, wallet) and the bank
 * institution directory over the legacy PROD model.
 *
 * - A manual bank account / wallet is an AXF_OBJ_BankAccount__c and a manual card an
 *   AXF_OBJ_CreditCard__c, with the holder in the Account lookup. Both external ids are
 *   required and unique in the legacy model, so a manual source gets 'MANUAL-' + the
 *   client idempotency key (UUID); repeating the same key replays the result instead of
 *   duplicating the source.
 * - The legacy model has no free-text institution: a typed institution name must match
 *   an existing AXF_OBJ_BankInstitution__c.
 * - Names are set by the legacy trigger (AXF_CLS_TH_AccountCardNaming).
 * - Authority: AXF_CanConfigure; all queries and DML run in USER_MODE.
 */
public with sharing class ALT_CLS_ManualFinancialSource {
  public static final String MANUAL_PREFIX = 'MANUAL-';
  public static final String WALLET = 'WALLET';
  private static final Integer MAX_BANK_NAME = 80;
  private static final Integer MAX_BANK_NUMBER = 8;
  private static final Pattern UUID_PATTERN = Pattern.compile(
    '(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );

  @TestVisible
  private static String lastFailure;

  /** @description Primitive input of a manual source save (mirrors the LWC call). */
  public class SaveInput {
    public String kind;
    public Id sourceId;
    public Id holderId;
    public String currencyIsoCode;
    public String institutionName;
    public Id bankInstitutionId;
    public String maskedNumber;
    public String sourceType;
    public String brand;
    public String manualKey;
  }

  // ---------------------------------------------------------------- bank institutions

  public AXF_CLS_SourceSetupDTO.BankInstitutionResult createBankInstitution(
    String name,
    String bankNumber
  ) {
    AXF_CLS_SourceSetupDTO.BankInstitutionResult r = new AXF_CLS_SourceSetupDTO.BankInstitutionResult();
    if (!ALT_CLS_SourceHolderLink.canConfigure()) {
      return bankOutcome(
        r,
        'FORBIDDEN',
        'Você não tem autorização para cadastrar instituições financeiras.'
      );
    }
    String cleanName = trim(name);
    String cleanNumber = trim(bankNumber);
    if (cleanName == null || cleanName.length() > MAX_BANK_NAME) {
      r.invalidFields.add('name');
      return bankOutcome(
        r,
        'INVALID',
        'Informe o nome da instituição (até 80 caracteres).'
      );
    }
    if (cleanNumber == null || cleanNumber.length() > MAX_BANK_NUMBER) {
      r.invalidFields.add('bankNumber');
      return bankOutcome(
        r,
        'INVALID',
        'Informe o código bancário (até 8 caracteres).'
      );
    }
    try {
      // The bank number is the external identity: never duplicate nor rename.
      List<AXF_OBJ_BankInstitution__c> existing = [
        SELECT Id, Name, AXF_BI_EXI_Bank_Number__c
        FROM AXF_OBJ_BankInstitution__c
        WHERE AXF_BI_EXI_Bank_Number__c = :cleanNumber
        WITH USER_MODE
        LIMIT 1
      ];
      if (!existing.isEmpty()) {
        r.institutionId = existing[0].Id;
        r.name = existing[0].Name;
        r.bankNumber = existing[0].AXF_BI_EXI_Bank_Number__c;
        return bankOutcome(
          r,
          'ALREADY',
          'Instituição financeira já cadastrada para este código bancário.'
        );
      }
      AXF_OBJ_BankInstitution__c row = new AXF_OBJ_BankInstitution__c(
        Name = cleanName,
        AXF_BI_EXI_Bank_Number__c = cleanNumber
      );
      insert as user row;
      r.institutionId = row.Id;
      r.name = cleanName;
      r.bankNumber = cleanNumber;
      return bankOutcome(r, 'CREATED', 'Instituição financeira cadastrada.');
    } catch (Exception e) {
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      return bankOutcome(
        r,
        'FAILED',
        'Não foi possível cadastrar a instituição. Nada foi alterado.'
      );
    }
  }

  // ---------------------------------------------------------------- manual sources

  public AXF_CLS_SourceSetupDTO.ManualSaveResult save(SaveInput i) {
    if (!ALT_CLS_SourceHolderLink.canConfigure()) {
      return result(
        'FORBIDDEN',
        'Você não tem autorização para configurar fontes financeiras.'
      );
    }
    AXF_CLS_SourceSetupDTO.ManualSaveResult invalid = validate(i);
    if (invalid != null) {
      return invalid;
    }
    Boolean walletSource = isWallet(i);
    try {
      Account holder = ALT_CLS_SourceHolderLink.findHolder(i.holderId);
      if (holder == null && i.sourceId == null) {
        return result(
          'FORBIDDEN',
          'O titular não foi encontrado ou não está acessível.'
        );
      }
      Id bankId = null;
      if (!walletSource) {
        bankId = resolveInstitution(i);
        if (bankId == null) {
          return invalidField(
            'bankInstitutionId',
            'Selecione a instituição financeira no cadastro ou cadastre um novo banco.'
          );
        }
      }
      if (i.sourceId != null) {
        return updateSource(i, bankId, walletSource);
      }
      return kind(i) == ALT_CLS_SourceHolderLink.KIND_BANK
        ? createBank(i, holder.Id, bankId, walletSource)
        : createCard(i, holder.Id, bankId);
    } catch (Exception e) {
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      return result(
        'FAILED',
        'Não foi possível salvar a fonte. Nada foi alterado.'
      );
    }
  }

  private AXF_CLS_SourceSetupDTO.ManualSaveResult createBank(
    SaveInput i,
    Id holderId,
    Id bankId,
    Boolean walletSource
  ) {
    String key = MANUAL_PREFIX + i.manualKey.toLowerCase();
    List<AXF_OBJ_BankAccount__c> replay = [
      SELECT Id, AXF_BA_LKP_Account__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = :key
      WITH USER_MODE
      LIMIT 1
    ];
    if (!replay.isEmpty()) {
      return replayed(replay[0].Id, replay[0].AXF_BA_LKP_Account__c, holderId);
    }
    AXF_OBJ_BankAccount__c row = new AXF_OBJ_BankAccount__c(
      AXF_BA_EXI_PluggyAccountId__c = key,
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_LKP_BankInstitution__c = bankId,
      AXF_BA_PKL_Currency__c = i.currencyIsoCode.toUpperCase(),
      AXF_BA_PKL_Type__c = walletSource ? WALLET : accountType(i.sourceType),
      AXF_BA_TXT_AccountNumber__c = trim(i.maskedNumber)
    );
    insert as user row;
    return created(row.Id, holderId);
  }

  private AXF_CLS_SourceSetupDTO.ManualSaveResult createCard(
    SaveInput i,
    Id holderId,
    Id bankId
  ) {
    String key = MANUAL_PREFIX + i.manualKey.toLowerCase();
    List<AXF_OBJ_CreditCard__c> replay = [
      SELECT Id, AXF_CC_LKP_Account__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = :key
      WITH USER_MODE
      LIMIT 1
    ];
    if (!replay.isEmpty()) {
      return replayed(replay[0].Id, replay[0].AXF_CC_LKP_Account__c, holderId);
    }
    AXF_OBJ_CreditCard__c row = new AXF_OBJ_CreditCard__c(
      AXF_CC_EXI_PluggyCreditCardId__c = key,
      AXF_CC_LKP_Account__c = holderId,
      AXF_CC_LKP_BankInstitution__c = bankId,
      AXF_CC_TXT_Brand__c = trim(i.brand),
      AXF_CC_TXT_LastFourDigits__c = lastFour(i.maskedNumber)
    );
    insert as user row;
    return created(row.Id, holderId);
  }

  private AXF_CLS_SourceSetupDTO.ManualSaveResult updateSource(
    SaveInput i,
    Id bankId,
    Boolean walletSource
  ) {
    String sourceKind = kind(i);
    Schema.SObjectType expected = sourceKind ==
      ALT_CLS_SourceHolderLink.KIND_BANK
      ? AXF_OBJ_BankAccount__c.SObjectType
      : AXF_OBJ_CreditCard__c.SObjectType;
    if (i.sourceId.getSObjectType() != expected) {
      return invalidField('sourceId', 'A fonte informada não é deste tipo.');
    }
    AXF_CLS_SourceSetupDTO.ManualSaveResult r;
    if (sourceKind == ALT_CLS_SourceHolderLink.KIND_BANK) {
      List<AXF_OBJ_BankAccount__c> rows = [
        SELECT Id, AXF_BA_LKP_Account__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :i.sourceId
        WITH USER_MODE
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        return notFound();
      }
      AXF_OBJ_BankAccount__c row = new AXF_OBJ_BankAccount__c(
        Id = i.sourceId,
        AXF_BA_LKP_BankInstitution__c = bankId,
        AXF_BA_PKL_Type__c = walletSource ? WALLET : accountType(i.sourceType),
        AXF_BA_TXT_AccountNumber__c = trim(i.maskedNumber)
      );
      update as user row;
      r = result('UPDATED', 'Fonte financeira atualizada.');
      r.accountHolderId = rows[0].AXF_BA_LKP_Account__c;
    } else {
      List<AXF_OBJ_CreditCard__c> rows = [
        SELECT Id, AXF_CC_LKP_Account__c
        FROM AXF_OBJ_CreditCard__c
        WHERE Id = :i.sourceId
        WITH USER_MODE
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        return notFound();
      }
      AXF_OBJ_CreditCard__c row = new AXF_OBJ_CreditCard__c(
        Id = i.sourceId,
        AXF_CC_LKP_BankInstitution__c = bankId,
        AXF_CC_TXT_Brand__c = trim(i.brand),
        AXF_CC_TXT_LastFourDigits__c = lastFour(i.maskedNumber)
      );
      update as user row;
      r = result('UPDATED', 'Fonte financeira atualizada.');
      r.accountHolderId = rows[0].AXF_CC_LKP_Account__c;
    }
    r.sourceId = i.sourceId;
    return r;
  }

  private static Id resolveInstitution(SaveInput i) {
    if (i.bankInstitutionId != null) {
      if (
        i.bankInstitutionId.getSObjectType() !=
        AXF_OBJ_BankInstitution__c.SObjectType
      ) {
        return null;
      }
      List<AXF_OBJ_BankInstitution__c> rows = [
        SELECT Id
        FROM AXF_OBJ_BankInstitution__c
        WHERE Id = :i.bankInstitutionId
        WITH USER_MODE
        LIMIT 1
      ];
      return rows.isEmpty() ? null : rows[0].Id;
    }
    String name = trim(i.institutionName);
    if (name == null) {
      return null;
    }
    List<AXF_OBJ_BankInstitution__c> byName = [
      SELECT Id
      FROM AXF_OBJ_BankInstitution__c
      WHERE Name = :name
      WITH USER_MODE
      LIMIT 1
    ];
    return byName.isEmpty() ? null : byName[0].Id;
  }

  private static AXF_CLS_SourceSetupDTO.ManualSaveResult validate(SaveInput i) {
    if (i == null || kind(i) == null) {
      return invalidField('kind', 'Selecione conta bancária ou cartão.');
    }
    if (
      i.sourceId == null &&
      (i.holderId == null ||
      i.holderId.getSObjectType() != Account.SObjectType)
    ) {
      return invalidField('holderId', 'Selecione um titular válido.');
    }
    if (
      i.sourceId == null &&
      (String.isBlank(i.currencyIsoCode) ||
      !activeCurrencies().contains(i.currencyIsoCode.trim().toUpperCase()))
    ) {
      return invalidField(
        'currencyIsoCode',
        'Informe uma moeda disponível (' +
          String.join(new List<String>(activeCurrencies()), ', ') +
          ').'
      );
    }
    if (i.currencyIsoCode != null) {
      i.currencyIsoCode = i.currencyIsoCode.trim();
    }
    if (
      !isWallet(i) &&
      String.isBlank(i.institutionName) &&
      i.bankInstitutionId == null
    ) {
      return invalidField('institutionName', 'Informe a instituição.');
    }
    String masked = trim(i.maskedNumber);
    if (
      masked != null &&
      (masked.replaceAll('[^0-9]', '').length() > 4 ||
      Pattern.matches('^[0-9]+$', masked))
    ) {
      return invalidField(
        'maskedNumber',
        'Informe somente um valor mascarado, com no máximo quatro dígitos visíveis.'
      );
    }
    if (masked != null && masked.length() > 30) {
      return invalidField(
        'maskedNumber',
        'O valor mascarado excede o limite permitido.'
      );
    }
    if (trim(i.sourceType) != null && trim(i.sourceType).length() > 40) {
      return invalidField(
        'sourceType',
        'O tipo da conta excede 40 caracteres.'
      );
    }
    if (trim(i.brand) != null && trim(i.brand).length() > 50) {
      return invalidField('brand', 'A bandeira excede 50 caracteres.');
    }
    if (
      i.sourceId == null &&
      (String.isBlank(i.manualKey) ||
      !UUID_PATTERN.matcher(i.manualKey).matches())
    ) {
      return invalidField('manualKey', 'Informe uma chave UUID válida.');
    }
    return null;
  }

  /** @description Currencies a legacy bank account accepts (AXF_BA_PKL_Currency__c). */
  private static Set<String> activeCurrencies() {
    Set<String> values = new Set<String>();
    for (
      Schema.PicklistEntry entry : AXF_OBJ_BankAccount__c.AXF_BA_PKL_Currency__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive()) {
        values.add(entry.getValue().toUpperCase());
      }
    }
    values.add(UserInfo.getDefaultCurrency().toUpperCase());
    return values;
  }

  /** @description Maps the free-text account type onto the legacy picklist values. */
  private static String accountType(String sourceType) {
    String t = trim(sourceType);
    if (t == null) {
      return 'CHECKING_ACCOUNT';
    }
    String normalized = t.toUpperCase().replaceAll('[^A-Z0-9]+', '_');
    for (
      Schema.PicklistEntry entry : AXF_OBJ_BankAccount__c.AXF_BA_PKL_Type__c.getDescribe()
        .getPicklistValues()
    ) {
      if (
        entry.isActive() &&
        (entry.getValue().toUpperCase() == normalized ||
        entry.getLabel().toUpperCase() == t.toUpperCase())
      ) {
        return entry.getValue();
      }
    }
    return normalized;
  }

  private static Boolean isWallet(SaveInput i) {
    return kind(i) == ALT_CLS_SourceHolderLink.KIND_BANK &&
      trim(i.sourceType) != null &&
      trim(i.sourceType).toUpperCase() == WALLET;
  }

  private static String kind(SaveInput i) {
    if (i == null || String.isBlank(i.kind)) {
      return null;
    }
    String k = i.kind.trim().toUpperCase();
    return k == ALT_CLS_SourceHolderLink.KIND_BANK ||
      k == ALT_CLS_SourceHolderLink.KIND_CARD
      ? k
      : null;
  }

  private static String lastFour(String masked) {
    String digits = masked == null ? '' : masked.replaceAll('[^0-9]', '');
    return String.isBlank(digits) ? null : digits.right(4);
  }

  private static String trim(String s) {
    return String.isBlank(s) ? null : s.trim();
  }

  private static AXF_CLS_SourceSetupDTO.ManualSaveResult replayed(
    Id sourceId,
    Id existingHolder,
    Id holderId
  ) {
    Boolean same = existingHolder == holderId;
    AXF_CLS_SourceSetupDTO.ManualSaveResult r = result(
      same ? 'ALREADY' : 'CONFLICT',
      same
        ? 'Esta operação já foi concluída.'
        : 'A chave já foi usada com dados diferentes.'
    );
    r.sourceId = sourceId;
    r.accountHolderId = existingHolder;
    return r;
  }

  private static AXF_CLS_SourceSetupDTO.ManualSaveResult created(
    Id sourceId,
    Id holderId
  ) {
    AXF_CLS_SourceSetupDTO.ManualSaveResult r = result(
      'CREATED',
      'Fonte financeira criada.'
    );
    r.sourceId = sourceId;
    r.accountHolderId = holderId;
    return r;
  }

  private static AXF_CLS_SourceSetupDTO.ManualSaveResult notFound() {
    return result(
      'FORBIDDEN',
      'A fonte não foi encontrada ou não está acessível.'
    );
  }

  private static AXF_CLS_SourceSetupDTO.ManualSaveResult invalidField(
    String field,
    String message
  ) {
    AXF_CLS_SourceSetupDTO.ManualSaveResult r = result('INVALID', message);
    r.invalidFields.add(field);
    return r;
  }

  private static AXF_CLS_SourceSetupDTO.ManualSaveResult result(
    String outcome,
    String message
  ) {
    AXF_CLS_SourceSetupDTO.ManualSaveResult r = new AXF_CLS_SourceSetupDTO.ManualSaveResult();
    r.outcome = outcome;
    r.message = message;
    return r;
  }

  private static AXF_CLS_SourceSetupDTO.BankInstitutionResult bankOutcome(
    AXF_CLS_SourceSetupDTO.BankInstitutionResult r,
    String outcome,
    String message
  ) {
    r.outcome = outcome;
    r.message = message;
    return r;
  }
}
