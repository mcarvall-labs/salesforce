/** AXF-86 domain service for manual bank accounts and credit cards. */
public with sharing class ALT_CLS_ManualFinancialSource {
  public enum Outcome {
    CREATED,
    ALREADY,
    UPDATED,
    CONFLICT,
    FORBIDDEN,
    INVALID,
    FAILED
  }
  public class SaveInput {
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public String institutionName;
    @AuraEnabled
    public String maskedNumber;
    @AuraEnabled
    public String sourceType;
    @AuraEnabled
    public String brand;
    @AuraEnabled
    public String manualKey;
    @AuraEnabled
    public Integer expectedVersion;
  }
  public class SaveResult {
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
    public List<String> invalidFields = new List<String>();
  }

  @TestVisible
  private static Boolean canConfigureOverride;
  @TestVisible
  private static Boolean sourceAccessOverride;
  @TestVisible
  private static String lastFailure;
  private static final Pattern UUID_PATTERN = Pattern.compile(
    '(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );
  private static Boolean canConfigure() {
    return canConfigureOverride == null
      ? FeatureManagement.checkPermission('AXF_CanConfigure')
      : canConfigureOverride;
  }

  public SaveResult save(SaveInput input) {
    if (!canConfigure())
      return result(
        Outcome.FORBIDDEN,
        'Você não tem autorização para configurar fontes financeiras.'
      );
    SaveResult invalid = validate(input);
    if (invalid != null)
      return invalid;
    try {
      // `with sharing` enforces record access; the explicit describe checks above
      // enforce CRUD/FLS without requiring access to relationship pseudo-fields.
      List<Account> holders = [
        SELECT Id, OwnerId, RecordType.DeveloperName
        FROM Account
        WHERE
          Id = :input.holderId
          AND RecordType.DeveloperName IN ('AXF_Person', 'AXF_Business')
        WITH USER_MODE
        LIMIT 1
      ];
      if (holders.isEmpty())
        return result(
          Outcome.FORBIDDEN,
          'O titular ou a fonte não foi encontrado ou não está acessível.'
        );
      Account holder = holders[0];
      if (!activeCurrency(input.currencyIsoCode))
        return invalid('currencyIsoCode', 'Selecione uma moeda ativa.');
      if (!hasSourceAccess(input))
        return result(
          Outcome.FORBIDDEN,
          'Você não possui acesso aos campos necessários da fonte financeira.'
        );
      return input.sourceId == null
        ? createSource(input, holder)
        : updateSource(input, holder);
    } catch (Exception e) {
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      return result(
        Outcome.FAILED,
        'Não foi possível salvar a fonte. Nada foi alterado.'
      );
    }
  }

  private SaveResult createSource(SaveInput i, Account holder) {
    Savepoint sp = Database.setSavepoint();
    try {
      SaveResult replay = findReplay(i);
      if (replay != null)
        return replay;
      SObject source;
      if (kind(i) == 'BANK') {
        source = new AXF_OBJ_BankAccount__c(
          OwnerId = holder.OwnerId,
          AXF_BA_LKP_Account__c = holder.Id,
          AXF_BA_EXI_ManualKey__c = i.manualKey.toLowerCase(),
          AXF_BA_TXT_CurrencyIsoCode__c = i.currencyIsoCode.toUpperCase(),
          AXF_BA_TXT_InstitutionName__c = i.institutionName.trim(),
          AXF_BA_TXT_NumberMasked__c = trim(i.maskedNumber),
          AXF_BA_TXT_Type__c = trim(i.sourceType),
          AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
          AXF_BA_NUM_Version__c = 1
        );
      } else {
        source = new AXF_OBJ_CreditCard__c(
          OwnerId = holder.OwnerId,
          AXF_CC_LKP_Account__c = holder.Id,
          AXF_CC_EXI_ManualKey__c = i.manualKey.toLowerCase(),
          AXF_CC_TXT_CurrencyIsoCode__c = i.currencyIsoCode.toUpperCase(),
          AXF_CC_TXT_InstitutionName__c = i.institutionName.trim(),
          AXF_CC_TXT_LastFourMasked__c = trim(i.maskedNumber),
          AXF_CC_TXT_Brand__c = trim(i.brand),
          AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
          AXF_CC_NUM_Version__c = 1
        );
      }
      Database.insert(source, AccessLevel.SYSTEM_MODE);
      String targetType = kind(i);
      String key = framed(
        holder.Id,
        targetType,
        (Id) source.get('Id'),
        'PRIMARY'
      );
      AXF_OBJ_AccountHolder__c ach = new AXF_OBJ_AccountHolder__c(
        OwnerId = holder.OwnerId,
        AXF_ACH_LKP_Account__c = holder.Id,
        AXF_ACH_PKL_Role__c = 'PRIMARY',
        AXF_ACH_PKL_State__c = 'CONFIRMED',
        AXF_ACH_DAT_ValidFrom__c = Date.today(),
        AXF_ACH_NUM_Version__c = 1,
        AXF_ACH_EXI_FramedKey__c = key,
        AXF_ACH_EXI_ManualOperationKey__c = i.manualKey.toLowerCase()
      );
      if (targetType == 'BANK')
        ach.AXF_ACH_LKP_BankAccount__c = (Id) source.get('Id');
      else
        ach.AXF_ACH_LKP_CreditCard__c = (Id) source.get('Id');
      Database.insert(ach, AccessLevel.SYSTEM_MODE);
      SaveResult r = result(Outcome.CREATED, 'Fonte financeira criada.');
      r.sourceId = (Id) source.get('Id');
      r.accountHolderId = ach.Id;
      r.version = 1;
      return r;
    } catch (Exception e) {
      Database.rollback(sp);
      lastFailure = e.getTypeName() + ': ' + e.getMessage();
      SaveResult replay = findReplay(i);
      return replay == null
        ? result(
            Outcome.FAILED,
            'Não foi possível salvar a fonte. Nada foi alterado.'
          )
        : replay;
    }
  }

  // CRUD/FLS is checked by hasSourceAccess before this lock query. USER_MODE is
  // intentionally not used here because Salesforce check-only executions cannot
  // resolve newly staged fields in a USER_MODE query; with sharing still enforces
  // record access and the update only writes the allowlisted descriptive fields.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private SaveResult updateSource(SaveInput i, Account holder) {
    if (i.expectedVersion == null)
      return invalid('expectedVersion', 'Informe a versão esperada.');
    if (kind(i) == 'BANK') {
      AXF_OBJ_BankAccount__c row = [
        SELECT
          Id,
          AXF_BA_LKP_Account__c,
          AXF_BA_EXI_ManualKey__c,
          AXF_BA_TXT_CurrencyIsoCode__c,
          AXF_BA_NUM_Version__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :i.sourceId
        LIMIT 1
        FOR UPDATE
      ];
      if (row.AXF_BA_EXI_ManualKey__c == null)
        return result(
          Outcome.INVALID,
          'Somente fontes manuais podem ser editadas aqui.'
        );
      if (
        row.AXF_BA_LKP_Account__c != holder.Id ||
        row.AXF_BA_TXT_CurrencyIsoCode__c != i.currencyIsoCode.toUpperCase()
      )
        return result(
          Outcome.INVALID,
          'Titular e moeda não podem ser alterados.'
        );
      if (integer(row.AXF_BA_NUM_Version__c) != i.expectedVersion)
        return result(
          Outcome.CONFLICT,
          'A fonte foi alterada em outra sessão.'
        );
      row.AXF_BA_TXT_InstitutionName__c = i.institutionName.trim();
      row.AXF_BA_TXT_NumberMasked__c = trim(i.maskedNumber);
      row.AXF_BA_TXT_Type__c = trim(i.sourceType);
      row.AXF_BA_NUM_Version__c = i.expectedVersion + 1;
      Database.update(row, AccessLevel.SYSTEM_MODE);
      return updated(row.Id, i.expectedVersion + 1);
    }
    AXF_OBJ_CreditCard__c row = [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_EXI_ManualKey__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_NUM_Version__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :i.sourceId
      LIMIT 1
      FOR UPDATE
    ];
    if (row.AXF_CC_EXI_ManualKey__c == null)
      return result(
        Outcome.INVALID,
        'Somente fontes manuais podem ser editadas aqui.'
      );
    if (
      row.AXF_CC_LKP_Account__c != holder.Id ||
      row.AXF_CC_TXT_CurrencyIsoCode__c != i.currencyIsoCode.toUpperCase()
    )
      return result(
        Outcome.INVALID,
        'Titular e moeda não podem ser alterados.'
      );
    if (integer(row.AXF_CC_NUM_Version__c) != i.expectedVersion)
      return result(Outcome.CONFLICT, 'A fonte foi alterada em outra sessão.');
    row.AXF_CC_TXT_InstitutionName__c = i.institutionName.trim();
    row.AXF_CC_TXT_LastFourMasked__c = trim(i.maskedNumber);
    row.AXF_CC_TXT_Brand__c = trim(i.brand);
    row.AXF_CC_NUM_Version__c = i.expectedVersion + 1;
    Database.update(row, AccessLevel.SYSTEM_MODE);
    return updated(row.Id, i.expectedVersion + 1);
  }

  // Read CRUD/FLS is checked by hasSourceAccess before this idempotency lookup.
  // See updateSource for the staged-field USER_MODE limitation.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private SaveResult findReplay(SaveInput i) {
    if (kind(i) == 'BANK') {
      List<AXF_OBJ_BankAccount__c> rows = [
        SELECT
          Id,
          AXF_BA_LKP_Account__c,
          AXF_BA_TXT_CurrencyIsoCode__c,
          AXF_BA_TXT_InstitutionName__c,
          AXF_BA_TXT_NumberMasked__c,
          AXF_BA_TXT_Type__c,
          AXF_BA_NUM_Version__c
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_EXI_ManualKey__c = :i.manualKey
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        List<AXF_OBJ_CreditCard__c> other = [
          SELECT Id
          FROM AXF_OBJ_CreditCard__c
          WHERE AXF_CC_EXI_ManualKey__c = :i.manualKey
          LIMIT 1
        ];
        return other.isEmpty() ? null : replayResult(other[0].Id, null, false);
      }
      AXF_OBJ_BankAccount__c r = rows[0];
      return replayResult(
        r.Id,
        integer(r.AXF_BA_NUM_Version__c),
        r.AXF_BA_LKP_Account__c == i.holderId &&
          r.AXF_BA_TXT_CurrencyIsoCode__c == i.currencyIsoCode.toUpperCase() &&
          r.AXF_BA_TXT_InstitutionName__c == i.institutionName.trim() &&
          r.AXF_BA_TXT_NumberMasked__c == trim(i.maskedNumber) &&
          r.AXF_BA_TXT_Type__c == trim(i.sourceType)
      );
    }
    List<AXF_OBJ_CreditCard__c> rows = [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_Brand__c,
        AXF_CC_NUM_Version__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_ManualKey__c = :i.manualKey
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      List<AXF_OBJ_BankAccount__c> other = [
        SELECT Id
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_EXI_ManualKey__c = :i.manualKey
        LIMIT 1
      ];
      return other.isEmpty() ? null : replayResult(other[0].Id, null, false);
    }
    AXF_OBJ_CreditCard__c r = rows[0];
    return replayResult(
      r.Id,
      integer(r.AXF_CC_NUM_Version__c),
      r.AXF_CC_LKP_Account__c == i.holderId &&
        r.AXF_CC_TXT_CurrencyIsoCode__c == i.currencyIsoCode.toUpperCase() &&
        r.AXF_CC_TXT_InstitutionName__c == i.institutionName.trim() &&
        r.AXF_CC_TXT_LastFourMasked__c == trim(i.maskedNumber) &&
        r.AXF_CC_TXT_Brand__c == trim(i.brand)
    );
  }

  private static SaveResult validate(SaveInput i) {
    if (i == null)
      return invalid('input', 'Informe os dados da fonte.');
    if (kind(i) == null)
      return invalid('kind', 'Selecione conta bancária ou cartão.');
    if (
      i.holderId == null ||
      i.holderId.getSObjectType() != Account.SObjectType
    )
      return invalid('holderId', 'Selecione um titular válido.');
    if (
      String.isBlank(i.currencyIsoCode) ||
      !Pattern.matches('^[A-Za-z]{3}$', i.currencyIsoCode)
    )
      return invalid('currencyIsoCode', 'Informe uma moeda ISO válida.');
    if (String.isBlank(i.institutionName))
      return invalid('institutionName', 'Informe a instituição.');
    if (
      !String.isBlank(i.maskedNumber) &&
      (i.maskedNumber.replaceAll('[^0-9]', '').length() > 4 ||
      Pattern.matches('^[0-9]+$', i.maskedNumber.trim()))
    )
      return invalid(
        'maskedNumber',
        'Informe somente um valor mascarado, com no máximo quatro dígitos visíveis.'
      );
    if (i.institutionName.trim().length() > 255)
      return invalid('institutionName', 'A instituição excede 255 caracteres.');
    if (
      trim(i.maskedNumber) != null &&
      trim(i.maskedNumber).length() > (kind(i) == 'BANK' ? 40 : 12)
    )
      return invalid(
        'maskedNumber',
        'O valor mascarado excede o limite permitido.'
      );
    if (trim(i.sourceType) != null && trim(i.sourceType).length() > 40)
      return invalid('sourceType', 'O tipo da conta excede 40 caracteres.');
    if (trim(i.brand) != null && trim(i.brand).length() > 40)
      return invalid('brand', 'A bandeira excede 40 caracteres.');
    if (
      i.sourceId == null &&
      (String.isBlank(i.manualKey) ||
      !UUID_PATTERN.matcher(i.manualKey).matches())
    )
      return invalid('manualKey', 'Informe uma chave UUID válida.');
    return null;
  }
  private static Boolean activeCurrency(String iso) {
    String wanted = iso == null ? null : iso.toUpperCase();
    Schema.SObjectType opportunityType = Schema.getGlobalDescribe()
      .get('Opportunity');
    Schema.SObjectField currencyField = opportunityType == null
      ? null
      : opportunityType.getDescribe().fields.getMap().get('CurrencyIsoCode');
    if (currencyField == null)
      return wanted == UserInfo.getDefaultCurrency();
    for (
      Schema.PicklistEntry entry : currencyField.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive() && entry.getValue() == wanted)
        return true;
    }
    return false;
  }
  @TestVisible
  private static Boolean hasSourceAccess(SaveInput i) {
    if (sourceAccessOverride != null)
      return sourceAccessOverride;
    Boolean createMode = i.sourceId == null;
    Boolean bank = kind(i) == 'BANK';
    Schema.SObjectType sourceType = bank
      ? AXF_OBJ_BankAccount__c.SObjectType
      : AXF_OBJ_CreditCard__c.SObjectType;
    Schema.DescribeSObjectResult sourceDescribe = sourceType.getDescribe(
      SObjectDescribeOptions.DEFERRED
    );
    Schema.DescribeSObjectResult holderDescribe = AXF_OBJ_AccountHolder__c.SObjectType.getDescribe(
      SObjectDescribeOptions.DEFERRED
    );
    if (!sourceDescribe.isAccessible())
      return false;
    if (
      createMode &&
      (!sourceDescribe.isCreateable() || !holderDescribe.isCreateable())
    )
      return false;
    if (!createMode && !sourceDescribe.isUpdateable())
      return false;

    List<Schema.SObjectField> readable = bank
      ? new List<Schema.SObjectField>{
          AXF_OBJ_BankAccount__c.AXF_BA_LKP_Account__c,
          AXF_OBJ_BankAccount__c.AXF_BA_EXI_ManualKey__c,
          AXF_OBJ_BankAccount__c.AXF_BA_TXT_CurrencyIsoCode__c,
          AXF_OBJ_BankAccount__c.AXF_BA_TXT_InstitutionName__c,
          AXF_OBJ_BankAccount__c.AXF_BA_TXT_NumberMasked__c,
          AXF_OBJ_BankAccount__c.AXF_BA_TXT_Type__c,
          AXF_OBJ_BankAccount__c.AXF_BA_NUM_Version__c
        }
      : new List<Schema.SObjectField>{
          AXF_OBJ_CreditCard__c.AXF_CC_LKP_Account__c,
          AXF_OBJ_CreditCard__c.AXF_CC_EXI_ManualKey__c,
          AXF_OBJ_CreditCard__c.AXF_CC_TXT_CurrencyIsoCode__c,
          AXF_OBJ_CreditCard__c.AXF_CC_TXT_InstitutionName__c,
          AXF_OBJ_CreditCard__c.AXF_CC_TXT_LastFourMasked__c,
          AXF_OBJ_CreditCard__c.AXF_CC_TXT_Brand__c,
          AXF_OBJ_CreditCard__c.AXF_CC_NUM_Version__c
        };
    List<Schema.SObjectField> writable;
    if (bank) {
      writable = new List<Schema.SObjectField>{
        AXF_OBJ_BankAccount__c.AXF_BA_TXT_InstitutionName__c,
        AXF_OBJ_BankAccount__c.AXF_BA_TXT_NumberMasked__c,
        AXF_OBJ_BankAccount__c.AXF_BA_TXT_Type__c,
        AXF_OBJ_BankAccount__c.AXF_BA_NUM_Version__c
      };
      if (createMode)
        writable.addAll(
          new List<Schema.SObjectField>{
            AXF_OBJ_BankAccount__c.OwnerId,
            AXF_OBJ_BankAccount__c.AXF_BA_LKP_Account__c,
            AXF_OBJ_BankAccount__c.AXF_BA_EXI_ManualKey__c,
            AXF_OBJ_BankAccount__c.AXF_BA_TXT_CurrencyIsoCode__c,
            AXF_OBJ_BankAccount__c.AXF_BA_PKL_AvailabilityState__c
          }
        );
    } else {
      writable = new List<Schema.SObjectField>{
        AXF_OBJ_CreditCard__c.AXF_CC_TXT_InstitutionName__c,
        AXF_OBJ_CreditCard__c.AXF_CC_TXT_LastFourMasked__c,
        AXF_OBJ_CreditCard__c.AXF_CC_TXT_Brand__c,
        AXF_OBJ_CreditCard__c.AXF_CC_NUM_Version__c
      };
      if (createMode)
        writable.addAll(
          new List<Schema.SObjectField>{
            AXF_OBJ_CreditCard__c.OwnerId,
            AXF_OBJ_CreditCard__c.AXF_CC_LKP_Account__c,
            AXF_OBJ_CreditCard__c.AXF_CC_EXI_ManualKey__c,
            AXF_OBJ_CreditCard__c.AXF_CC_TXT_CurrencyIsoCode__c,
            AXF_OBJ_CreditCard__c.AXF_CC_PKL_AvailabilityState__c
          }
        );
    }
    for (Schema.SObjectField field : readable) {
      if (!field.getDescribe().isAccessible())
        return false;
    }
    for (Schema.SObjectField field : writable) {
      Boolean allowed = createMode
        ? field.getDescribe().isCreateable()
        : field.getDescribe().isUpdateable();
      if (!allowed)
        return false;
    }
    if (createMode) {
      List<Schema.SObjectField> holderFields = new List<Schema.SObjectField>{
        AXF_OBJ_AccountHolder__c.OwnerId,
        AXF_OBJ_AccountHolder__c.AXF_ACH_LKP_Account__c,
        AXF_OBJ_AccountHolder__c.AXF_ACH_LKP_BankAccount__c,
        AXF_OBJ_AccountHolder__c.AXF_ACH_LKP_CreditCard__c,
        AXF_OBJ_AccountHolder__c.AXF_ACH_PKL_Role__c,
        AXF_OBJ_AccountHolder__c.AXF_ACH_PKL_State__c,
        AXF_OBJ_AccountHolder__c.AXF_ACH_DAT_ValidFrom__c,
        AXF_OBJ_AccountHolder__c.AXF_ACH_NUM_Version__c,
        AXF_OBJ_AccountHolder__c.AXF_ACH_EXI_FramedKey__c,
        AXF_OBJ_AccountHolder__c.AXF_ACH_EXI_ManualOperationKey__c
      };
      for (Schema.SObjectField field : holderFields)
        if (!field.getDescribe().isCreateable())
          return false;
    }
    return true;
  }
  private static String kind(SaveInput i) {
    if (i == null || String.isBlank(i.kind))
      return null;
    String k = i.kind.trim().toUpperCase();
    return k == 'BANK' || k == 'CARD' ? k : null;
  }
  private static String trim(String s) {
    return String.isBlank(s) ? null : s.trim();
  }
  private static Integer integer(Decimal d) {
    return d == null ? 0 : d.intValue();
  }
  private static String framed(Id h, String t, Id id, String role) {
    return frame(String.valueOf(h)) +
      frame(t) +
      frame(String.valueOf(id)) +
      frame(role);
  }
  private static String frame(String s) {
    return s.length() + ':' + s;
  }
  private static SaveResult replayResult(Id id, Integer v, Boolean same) {
    SaveResult r = result(
      same ? Outcome.ALREADY : Outcome.CONFLICT,
      same
        ? 'Esta operação já foi concluída.'
        : 'A chave já foi usada com dados diferentes.'
    );
    r.sourceId = id;
    r.version = v;
    return r;
  }
  private static SaveResult updated(Id id, Integer v) {
    SaveResult r = result(Outcome.UPDATED, 'Fonte financeira atualizada.');
    r.sourceId = id;
    r.version = v;
    return r;
  }
  private static SaveResult invalid(String field, String msg) {
    SaveResult r = result(Outcome.INVALID, msg);
    r.invalidFields.add(field);
    return r;
  }
  private static SaveResult result(Outcome o, String msg) {
    SaveResult r = new SaveResult();
    r.outcome = o.name();
    r.message = msg;
    return r;
  }
}
