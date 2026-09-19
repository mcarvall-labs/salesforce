/**
 * @description AXF-30: fronteira Apex->LWC da workbench de conciliacao N:N. Acesso
 * positivo/negativo, capability, sanitizacao do retorno, bulk e estados.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class AXF_CLS_CTRL_ReconciliationWorkbenchTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf3cg', 'axf3cn' }) {
      users.add(
        new User(
          Alias = alias,
          Email = alias + '@example.invalid',
          EmailEncodingKey = 'UTF-8',
          LastName = 'User ' + alias,
          LanguageLocaleKey = 'pt_BR',
          LocaleSidKey = 'pt_BR',
          TimeZoneSidKey = 'America/Sao_Paulo',
          ProfileId = profileId,
          Username = alias + '.' + System.now().getTime() + '@example.invalid'
        )
      );
    }
    insert users;
    Map<String, Id> permissionSets = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (String name : permissionSets.keySet()) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = users[0].Id,
          PermissionSetId = permissionSets.get(name)
        )
      );
    }
    insert assignments;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  private class Fixture {
    Account holder;
    AXF_OBJ_BankAccount__c bank;
    AXF_OBJ_BankAccountTransaction__c fact;
    List<AXF_OBJ_FinancialTransaction__c> targets = new List<AXF_OBJ_FinancialTransaction__c>();
  }

  private static Fixture fixture(String key) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Holder CTRL ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    f.bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert f.bank;
    f.fact = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = f.bank.Id,
      AXF_BAT_NUM_Magnitude__c = 100,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Fact ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf3c-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert f.fact;
    Integer sequence = 0;
    for (Decimal amount : new List<Decimal>{ 60, 40 }) {
      sequence++;
      f.targets.add(
        new AXF_OBJ_FinancialTransaction__c(
          AXF_FTX_LKP_Account__c = f.holder.Id,
          AXF_FTX_NUM_Magnitude__c = amount,
          AXF_FTX_PKL_Direction__c = 'DEBIT',
          AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
          AXF_FTX_DAT_PurchaseDate__c = Date.today(),
          AXF_FTX_DAT_DueDate__c = Date.today().addDays(sequence),
          AXF_FTX_TXT_Description__c = 'Target ' + key + ' ' + sequence,
          AXF_FTX_PKL_PlanKind__c = 'PLANNED',
          AXF_FTX_PKL_Status__c = 'PLANNED',
          AXF_FTX_NUM_Version__c = 0,
          AXF_FTX_EXI_ClientRequestId__c = 'ftx-3c-' + key + '-' + sequence
        )
      );
    }
    insert f.targets;
    return f;
  }

  private static String uuid(String seed) {
    String hex = EncodingUtil.convertToHex(
        Crypto.generateDigest(
          'SHA-256',
          Blob.valueOf(seed + String.valueOf(Crypto.getRandomInteger()))
        )
      )
      .toLowerCase();
    return hex.substring(0, 8) +
      '-' +
      hex.substring(8, 12) +
      '-4' +
      hex.substring(13, 16) +
      '-8' +
      hex.substring(17, 20) +
      '-' +
      hex.substring(20, 32);
  }

  private static String confirmRequest(
    Fixture f,
    Decimal first,
    Decimal second,
    Decimal expectedVersion,
    String correlationId
  ) {
    return JSON.serialize(
      new Map<String, Object>{
        'lines' => new List<Object>{
          new Map<String, Object>{
            'factKind' => 'BANK',
            'factId' => f.fact.Id,
            'targetId' => f.targets[0].Id,
            'amount' => first
          },
          new Map<String, Object>{
            'factKind' => 'BANK',
            'factId' => f.fact.Id,
            'targetId' => f.targets[1].Id,
            'amount' => second
          }
        },
        'expectedVersion' => expectedVersion,
        'idempotencyKey' => 'axf3c-' + correlationId.left(8),
        'correlationId' => correlationId
      }
    );
  }

  /** The sanitized code of a failing controller call, read from its AuraHandledException. */
  private static String codeOf(String raw) {
    try {
      AXF_CLS_CTRL_ReconciliationWorkbench.confirm(raw);
    } catch (AuraHandledException expected) {
      return (String) ((Map<String, Object>) JSON.deserializeUntyped(
          expected.getMessage()
        ))
        .get('code');
    } catch (Exception unexpected) {
      return 'UNEXPECTED:' + unexpected.getTypeName();
    }
    return 'NO_EXCEPTION';
  }

  private static String codeOfPreview(String raw) {
    try {
      AXF_CLS_CTRL_ReconciliationWorkbench.preview(raw);
    } catch (AuraHandledException expected) {
      return code(expected);
    } catch (Exception unexpected) {
      return 'UNEXPECTED:' + unexpected.getTypeName();
    }
    return 'NO_EXCEPTION';
  }

  private static String codeOfResolve(String raw) {
    try {
      AXF_CLS_CTRL_ReconciliationWorkbench.resolveResult(raw);
    } catch (AuraHandledException expected) {
      return code(expected);
    } catch (Exception unexpected) {
      return 'UNEXPECTED:' + unexpected.getTypeName();
    }
    return 'NO_EXCEPTION';
  }

  private static String codeOfPark(String raw) {
    try {
      AXF_CLS_CTRL_ReconciliationWorkbench.parkResultUnknown(raw);
    } catch (AuraHandledException expected) {
      return code(expected);
    } catch (Exception unexpected) {
      return 'UNEXPECTED:' + unexpected.getTypeName();
    }
    return 'NO_EXCEPTION';
  }

  private static String code(AuraHandledException expected) {
    return (String) ((Map<String, Object>) JSON.deserializeUntyped(
        expected.getMessage()
      ))
      .get('code');
  }

  /** The same intention the confirmation sends: parking it must reuse exactly this set. */
  private static String attemptRequest(Fixture f, String correlationId) {
    return JSON.serialize(
      new Map<String, Object>{
        'correlationId' => correlationId,
        'lines' => new List<Object>{
          new Map<String, Object>{
            'factKind' => 'BANK',
            'factId' => f.fact.Id,
            'targetId' => f.targets[0].Id,
            'amount' => 60
          },
          new Map<String, Object>{
            'factKind' => 'BANK',
            'factId' => f.fact.Id,
            'targetId' => f.targets[1].Id,
            'amount' => 40
          }
        }
      }
    );
  }

  @IsTest
  static void everyBoundaryOfTheControllerStaysSanitized() {
    System.runAs(byAlias('axf3cg')) {
      Fixture f = fixture('bound');
      Assert.areEqual('INVALID_INPUT', codeOfPreview(' '));
      Assert.areEqual('INVALID_INPUT', codeOfPreview('{"accountId":'));
      Assert.areEqual('INVALID_INPUT', codeOfResolve(' '));
      Assert.areEqual('INVALID_INPUT', codeOfPark(' '));
      Assert.areEqual('INVALID_INPUT', codeOfPark('{"correlationId":'));
      Assert.areEqual('INVALID_INPUT', codeOf('{"lines":[]}'));
      // A nonexistent account answers like one the caller cannot reach.
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        codeOfPreview(
          JSON.serialize(
            new Map<String, Object>{
              'accountId' => Account.SObjectType.getDescribe().getKeyPrefix() +
              '000000000000'
            }
          )
        )
      );
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_Reconciliation__c]);
    }
  }

  @IsTest
  static void parkingAndResolvingAreIdempotentThroughTheController() {
    System.runAs(byAlias('axf3cg')) {
      Fixture f = fixture('park');
      String correlationId = uuid('ctrl-park');
      String request = attemptRequest(f, correlationId);
      ALT_CLS_ReconciliationService.WorkbenchView parked;
      ALT_CLS_ReconciliationService.WorkbenchView again;
      ALT_CLS_ReconciliationService.WorkbenchView resolved;
      ALT_CLS_ReconciliationService.ConfirmResult confirmed;
      Test.startTest();
      parked = AXF_CLS_CTRL_ReconciliationWorkbench.parkResultUnknown(request);
      again = AXF_CLS_CTRL_ReconciliationWorkbench.parkResultUnknown(request);
      // While unresolved, the same intention cannot be confirmed again.
      String blocked = codeOf(
        confirmRequest(f, 60, 40, parked.expectedVersion, correlationId)
      );
      resolved = AXF_CLS_CTRL_ReconciliationWorkbench.resolveResult(request);
      AXF_OBJ_Reconciliation__c persisted = [
        SELECT AXF_RCN_NUM_Version__c, AXF_RCN_PKL_State__c
        FROM AXF_OBJ_Reconciliation__c
        LIMIT 1
      ];
      Assert.areEqual(
        2.00,
        persisted.AXF_RCN_NUM_Version__c,
        'the authoritative query advances the parked aggregate once, to version 2'
      );
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_FAILED,
        persisted.AXF_RCN_PKL_State__c
      );
      Assert.areEqual(
        persisted.AXF_RCN_NUM_Version__c,
        resolved.expectedVersion,
        'the view reports the persisted version'
      );
      confirmed = AXF_CLS_CTRL_ReconciliationWorkbench.confirm(
        confirmRequest(f, 60, 40, resolved.expectedVersion, correlationId)
      );
      Test.stopTest();
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_BLOCKED,
        parked.state
      );
      Assert.isTrue(parked.unknownOutcome, 'the outcome starts unknown');
      Assert.areEqual(parked.reconciliationId, again.reconciliationId);
      Assert.isTrue(again.unknownOutcome, 'parking is idempotent');
      Assert.areEqual(
        'CONFLICT',
        blocked,
        'the retry is refused while unresolved'
      );
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_FAILED,
        resolved.state,
        'nothing was committed, so the scope may run again'
      );
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_CONFIRMED,
        confirmed.state
      );
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE AXF_RA_LKP_Reconciliation__c != NULL
        ],
        'exactly one line per target, written once'
      );
    }
  }

  @IsTest
  static void contextPreviewsAndConfirmsThroughTheController() {
    System.runAs(byAlias('axf3cg')) {
      Fixture f = fixture('ok');
      AXF_CLS_CTRL_ReconciliationWorkbench.Context context;
      ALT_CLS_ReconciliationService.WorkbenchView sources;
      ALT_CLS_ReconciliationService.ConfirmResult result;
      Test.startTest();
      context = AXF_CLS_CTRL_ReconciliationWorkbench.getContext();
      sources = AXF_CLS_CTRL_ReconciliationWorkbench.preview(
        JSON.serialize(new Map<String, Object>{ 'accountId' => f.holder.Id })
      );
      result = AXF_CLS_CTRL_ReconciliationWorkbench.confirm(
        confirmRequest(f, 60, 40, 0, uuid('ctrl-ok'))
      );
      Test.stopTest();
      Assert.isTrue(context.canConfirm, 'the capability is reported');
      Assert.areEqual(
        ALT_CLS_ReconciliationService.POLICY_VERSION,
        context.policyVersion
      );
      Assert.isFalse(
        context.holders.isEmpty(),
        'holders are listed for the capable user'
      );
      Assert.areEqual(
        1,
        sources.sources.size(),
        'the source with residual is listed'
      );
      Assert.areEqual(100.00, sources.sources[0].magnitude);
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_CONFIRMED,
        result.state
      );
      Assert.areEqual(2, result.lines.size());
      // The returned DTO exposes only the surface the workbench renders: no owner, no internal id
      // of the aggregate beyond its own identifier and no raw payload.
      Map<String, Object> serialized = (Map<String, Object>) JSON.deserializeUntyped(
        JSON.serialize(result)
      );
      Set<String> keys = serialized.keySet();
      Assert.isTrue(keys.contains('reconciliationId'));
      Assert.isTrue(keys.contains('residualMagnitude'));
      Assert.isFalse(keys.contains('OwnerId'));
      Assert.isFalse(keys.contains('AXF_RCN_EXI_ReconciliationKey__c'));
    }
  }

  @IsTest
  static void withoutTheCapabilityNothingIsListedAndNothingIsConfirmed() {
    System.runAs(byAlias('axf3cn')) {
      AXF_CLS_CTRL_ReconciliationWorkbench.Context context;
      Test.startTest();
      context = AXF_CLS_CTRL_ReconciliationWorkbench.getContext();
      Test.stopTest();
      Assert.isFalse(context.canConfirm, 'the capability is absent');
      Assert.isTrue(
        context.holders.isEmpty(),
        'no holder is listed without the capability'
      );
      String code = null;
      try {
        AXF_CLS_CTRL_ReconciliationWorkbench.preview(
          JSON.serialize(new Map<String, Object>{ 'accountId' => null })
        );
      } catch (AuraHandledException expected) {
        code = (String) ((Map<String, Object>) JSON.deserializeUntyped(
            expected.getMessage()
          ))
          .get('code');
      }
      Assert.areEqual('UNAVAILABLE', code);
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_Reconciliation__c]);
    }
  }

  @IsTest
  static void malformedAndRejectedRequestsStaySanitized() {
    System.runAs(byAlias('axf3cg')) {
      Fixture f = fixture('bad');
      String malformed = codeOf('{"lines":');
      String blank = codeOf(' ');
      String overAllocation = codeOf(
        confirmRequest(f, 60, 40.01, 0, uuid('ctrl-bad'))
      );
      Assert.areEqual('INVALID_INPUT', malformed);
      Assert.areEqual('INVALID_INPUT', blank);
      Assert.areEqual('VALUE_CONSERVATION', overAllocation);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_Reconciliation__c],
        'a rejected command writes nothing'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE AXF_RA_LKP_BankTransaction__c = :f.fact.Id
        ]
      );
    }
  }

  @IsTest
  static void anUnknownIntentionAnswersWithNoEffectInsteadOfInventingOne() {
    System.runAs(byAlias('axf3cg')) {
      Fixture f = fixture('deny');
      String correlationId = uuid('ctrl-deny');
      AXF_CLS_CTRL_ReconciliationWorkbench.confirm(
        confirmRequest(f, 60, 40, 0, correlationId)
      );
      ALT_CLS_ReconciliationService.WorkbenchView unknown;
      Test.startTest();
      unknown = AXF_CLS_CTRL_ReconciliationWorkbench.resolveResult(
        JSON.serialize(
          new Map<String, Object>{
            'correlationId' => uuid('ctrl-none'),
            'lines' => new List<Object>{
              new Map<String, Object>{
                'factKind' => 'BANK',
                'factId' => f.fact.Id,
                'targetId' => f.targets[0].Id,
                'amount' => 60
              }
            }
          }
        )
      );
      Test.stopTest();
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_FAILED,
        unknown.state,
        'an intention with no durable effect answers FAILED, never a fabricated outcome'
      );
      Assert.isNull(unknown.reconciliationId);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_Reconciliation__c],
        'the other intention is untouched'
      );
    }
  }
}
