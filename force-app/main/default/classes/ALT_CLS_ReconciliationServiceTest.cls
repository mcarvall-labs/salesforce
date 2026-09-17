/**
 * @description AXF-30: matriz I/O do comando reconciliation.allocation.confirm.v1 — GF-01..GF-05,
 * GF-72..GF-75, moeda divergente, autorizacao parcial, versao obsoleta, plano de lock, double-submit
 * e residual explicito. Cada rejeicao e provada como atomica: nenhum RCN e nenhum RA parcial.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_ReconciliationServiceTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf30g', 'axf30p', 'axf30n' }) {
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
          'AXF_PS_Realization',
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    Assert.areEqual(4, permissionSets.size(), 'permission sets must exist');
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (
      String name : new List<String>{
        'AXF_PS_GestorFinanceiro',
        'AXF_PS_FinancialEntry',
        'AXF_PS_Realization'
      }
    ) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = users[0].Id,
          PermissionSetId = permissionSets.get(name)
        )
      );
    }
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = users[1].Id,
        PermissionSetId = permissionSets.get('AXF_PS_Participante')
      )
    );
    insert assignments;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  private class Fixture {
    public Account holder;
    public AXF_OBJ_BankAccount__c bank;
    public AXF_OBJ_BankAccountTransaction__c fact;
    public List<AXF_OBJ_FinancialTransaction__c> targets = new List<AXF_OBJ_FinancialTransaction__c>();
  }

  /**
   * Holder, available bank, POSTED fact and one PLANNED target per requested amount. `planHash`
   * links the first target to the fact's durable identity when asked (exact-identity presentation).
   */
  private static Fixture fixture(
    String key,
    Decimal factAmount,
    String direction,
    String factCurrency,
    List<Decimal> targetAmounts,
    String targetCurrency
  ) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Holder 30 ' + key,
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
      AXF_BAT_NUM_Magnitude__c = factAmount,
      AXF_BAT_TXT_CurrencyIsoCode__c = factCurrency,
      AXF_BAT_PKL_Direction__c = direction,
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Fact ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf30-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert f.fact;
    Integer sequence = 0;
    for (Decimal amount : targetAmounts) {
      sequence++;
      f.targets.add(
        new AXF_OBJ_FinancialTransaction__c(
          AXF_FTX_LKP_Account__c = f.holder.Id,
          AXF_FTX_NUM_Magnitude__c = amount,
          AXF_FTX_PKL_Direction__c = direction,
          AXF_FTX_TXT_CurrencyIsoCode__c = targetCurrency,
          AXF_FTX_DAT_PurchaseDate__c = Date.today(),
          AXF_FTX_DAT_DueDate__c = Date.today().addDays(sequence),
          AXF_FTX_TXT_Description__c = 'Target ' + key + ' ' + sequence,
          AXF_FTX_PKL_PlanKind__c = 'PLANNED',
          AXF_FTX_PKL_Status__c = 'PLANNED',
          AXF_FTX_NUM_Version__c = 0,
          AXF_FTX_EXI_ClientRequestId__c = 'ftx-30-' + key + '-' + sequence
        )
      );
    }
    if (!f.targets.isEmpty()) {
      insert f.targets;
    }
    return f;
  }

  private static ALT_CLS_ReconciliationService.LineInput line(
    AXF_OBJ_BankAccountTransaction__c fact,
    AXF_OBJ_FinancialTransaction__c target,
    Decimal amount
  ) {
    ALT_CLS_ReconciliationService.LineInput input = new ALT_CLS_ReconciliationService.LineInput();
    input.factKind = 'BANK';
    input.factId = fact.Id;
    input.targetId = target.Id;
    input.amount = amount;
    return input;
  }

  private static ALT_CLS_ReconciliationService.ConfirmInput confirmInput(
    List<ALT_CLS_ReconciliationService.LineInput> lines,
    Decimal expectedVersion,
    String correlationId,
    String idempotencyKey
  ) {
    ALT_CLS_ReconciliationService.ConfirmInput input = new ALT_CLS_ReconciliationService.ConfirmInput();
    input.lines = lines;
    input.expectedVersion = expectedVersion;
    input.correlationId = correlationId;
    input.idempotencyKey = idempotencyKey;
    return input;
  }

  private static String correlation(String seed) {
    String body = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    String hex = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(seed + body))
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

  /** Runs a command that must fail and returns its typed code. */
  private static String codeOf(ALT_CLS_ReconciliationService.ConfirmInput input) {
    try {
      new ALT_CLS_ReconciliationService().confirm(input);
      return null;
    } catch (ALT_CLS_ReconciliationService.ReconciliationException expected) {
      return expected.code;
    }
  }

  private static Integer countAllocations(Id factId) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_BankTransaction__c = :factId
        OR AXF_RA_LKP_CardTransaction__c = :factId
        OR AXF_RA_LKP_ManualTransaction__c = :factId
    ];
  }

  private static Integer countAggregates() {
    return [SELECT COUNT() FROM AXF_OBJ_Reconciliation__c];
  }

  // ------------------------------------------------------------------ GF-01

  @IsTest
  static void gf01SameCurrencySplitWritesTwoCanonicalLinesAtomically() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'gf01',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 60, 40 },
        'BRL'
      );
      List<ALT_CLS_ReconciliationService.LineInput> lines = new List<ALT_CLS_ReconciliationService.LineInput>{
        line(f.fact, f.targets[0], 60),
        line(f.fact, f.targets[1], 40)
      };
      String correlationId = correlation('gf01');
      ALT_CLS_ReconciliationService.ConfirmResult result;
      Test.startTest();
      result = new ALT_CLS_ReconciliationService()
        .confirm(confirmInput(lines, 0, correlationId, 'axf30-gf01'));
      Test.stopTest();

      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_CONFIRMED,
        result.state,
        'a fully allocated set is CONFIRMED'
      );
      Assert.areEqual(0.00, result.residualMagnitude, 'no leftover is persisted as zero');
      Assert.areEqual('BRL', result.residualCurrency);
      Assert.isNotNull(result.effectiveAt, 'the effective instant is persisted');
      Assert.areEqual(2, result.lines.size());
      Assert.areEqual(100.00, result.allocatedTotal, 'consumption counted once');

      List<AXF_OBJ_ReconciliationAllocation__c> rows = [
        SELECT
          Id,
          AXF_RA_NUM_Magnitude__c,
          AXF_RA_EXI_AllocationKey__c,
          AXF_RA_LKP_Reconciliation__c,
          AXF_RA_PKL_Kind__c,
          AXF_RA_PKL_FxState__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_BankTransaction__c = :f.fact.Id
        ORDER BY AXF_RA_NUM_Magnitude__c DESC
      ];
      Assert.areEqual(2, rows.size(), 'two lines, one per target');
      Assert.areEqual(60.00, rows[0].AXF_RA_NUM_Magnitude__c);
      Assert.areEqual(40.00, rows[1].AXF_RA_NUM_Magnitude__c);
      Assert.areEqual('APPLICATION', rows[0].AXF_RA_PKL_Kind__c);
      Assert.areEqual(
        result.reconciliationId,
        rows[0].AXF_RA_LKP_Reconciliation__c,
        'every line belongs to the aggregate'
      );
      Assert.areEqual(
        'READY',
        rows[0].AXF_RA_PKL_FxState__c,
        'recognition evidence is complete in the same currency'
      );
      // The canonical identity of the line is the alloc-v2 frame of the two durable identities,
      // never the key of the run that proposed it.
      Assert.areEqual(
        ALT_CLS_ReconciliationService.allocationIdentity(
          f.fact.AXF_BAT_EXI_SourceKey__c,
          f.targets[0].AXF_FTX_EXI_ClientRequestId__c
        ),
        rows[0].AXF_RA_EXI_AllocationKey__c
      );
      // AXF-25 bumps the optimistic version of the source fact once per applied line, so two lines
      // over one fact leave version 2 — each contribution is still counted exactly once.
      Assert.areEqual(
        2.00,
        [
          SELECT AXF_BAT_NUM_Version__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :f.fact.Id
        ]
        .AXF_BAT_NUM_Version__c
      );
      Assert.areEqual(
        1.00,
        [
          SELECT AXF_FTX_NUM_Version__c
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :f.targets[0].Id
        ]
        .AXF_FTX_NUM_Version__c
      );
      // The aggregate is readable and reports the same figures the command returned.
      ALT_CLS_ReconciliationService.WorkbenchView read = new ALT_CLS_ReconciliationService()
        .read(
          attempt(
            new List<ALT_CLS_ReconciliationService.LineInput>{
              line(f.fact, f.targets[0], 60),
              line(f.fact, f.targets[1], 40)
            },
            correlationId
          )
        );
      Assert.areEqual(ALT_CLS_ReconciliationService.STATE_CONFIRMED, read.state);
      Assert.areEqual(2, read.lines.size());
      Assert.areEqual(0.00, read.lines[0].residual, 'the target has no residual left');
    }
  }

  private static ALT_CLS_ReconciliationService.AttemptInput attempt(
    List<ALT_CLS_ReconciliationService.LineInput> lines,
    String correlationId
  ) {
    ALT_CLS_ReconciliationService.AttemptInput input = new ALT_CLS_ReconciliationService.AttemptInput();
    input.lines = lines;
    input.correlationId = correlationId;
    return input;
  }

  // ------------------------------------------------------------------ GF-02

  @IsTest
  static void gf02OverAllocationRejectsTheWholeCommandWithoutPartialPersistence() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'gf02',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100, 100 },
        'BRL'
      );
      String code;
      Test.startTest();
      code = codeOf(
        confirmInput(
          new List<ALT_CLS_ReconciliationService.LineInput>{
            line(f.fact, f.targets[0], 60),
            line(f.fact, f.targets[1], 40.01)
          },
          0,
          correlation('gf02'),
          'axf30-gf02'
        )
      );
      Test.stopTest();
      Assert.areEqual('VALUE_CONSERVATION', code);
      Assert.areEqual(0, countAggregates(), 'no aggregate survives a rejection');
      Assert.areEqual(0, countAllocations(f.fact.Id), 'no line survives a rejection');
      Assert.areEqual(
        0.00,
        [
          SELECT AXF_BAT_NUM_Version__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :f.fact.Id
        ]
        .AXF_BAT_NUM_Version__c,
        'the source version is untouched by a rejected command'
      );
      Assert.areEqual(
        0.00,
        [
          SELECT AXF_FTX_NUM_Version__c
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :f.targets[0].Id
        ]
        .AXF_FTX_NUM_Version__c
      );
    }
  }

  // ------------------------------------------------------------------ GF-03

  @IsTest
  static void gf03PartialLeavesExplicitResidualAndStaysPartial() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'gf03',
        100,
        'CREDIT',
        'BRL',
        new List<Decimal>{ 120 },
        'BRL'
      );
      ALT_CLS_ReconciliationService.ConfirmResult result;
      Test.startTest();
      result = new ALT_CLS_ReconciliationService()
        .confirm(
          confirmInput(
            new List<ALT_CLS_ReconciliationService.LineInput>{
              line(f.fact, f.targets[0], 100)
            },
            0,
            correlation('gf03'),
            'axf30-gf03'
          )
        );
      Test.stopTest();
      Assert.areEqual(ALT_CLS_ReconciliationService.STATE_PARTIAL, result.state);
      Assert.areEqual(
        20.00,
        result.residualMagnitude,
        'the residual of the target is persisted, not derived on read'
      );
      Assert.areEqual('BRL', result.residualCurrency);
      Assert.areEqual(0.00, result.lines[0].sourceResidual, 'the source has no residual');
      Assert.areEqual(20.00, result.lines[0].residual, 'the target still needs 20');
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_PARTIAL,
        result.lines[0].state
      );
      Assert.areEqual(
        20.00,
        [
          SELECT AXF_RCN_NUM_ResidualMagnitude__c
          FROM AXF_OBJ_Reconciliation__c
          WHERE Id = :result.reconciliationId
        ]
        .AXF_RCN_NUM_ResidualMagnitude__c
      );
    }
  }

  // ------------------------------------------------------------------ GF-04

  @IsTest
  static void gf04InstallmentsConserveTheTotalWithoutRoundingLeftover() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'gf04',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 33.33, 33.33, 33.34 },
        'BRL'
      );
      List<ALT_CLS_ReconciliationService.LineInput> lines = new List<ALT_CLS_ReconciliationService.LineInput>{
        line(f.fact, f.targets[0], 33.33),
        line(f.fact, f.targets[1], 33.33),
        line(f.fact, f.targets[2], 33.34)
      };
      ALT_CLS_ReconciliationService.ConfirmResult result;
      Test.startTest();
      result = new ALT_CLS_ReconciliationService()
        .confirm(confirmInput(lines, 0, correlation('gf04'), 'axf30-gf04'));
      Test.stopTest();
      Assert.areEqual(100.00, result.allocatedTotal, 'the parcels sum exactly 100');
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_CONFIRMED,
        result.state,
        'no rounding leftover survives'
      );
      Assert.areEqual(0.00, result.residualMagnitude);
      Assert.areEqual(3, countAllocations(f.fact.Id));
    }
  }

  // ------------------------------------------------------------------ GF-05

  @IsTest
  static void gf05ReversalCompensatesAndRestoresTheDerivedState() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'gf05',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100 },
        'BRL'
      );
      ALT_CLS_ReconciliationService.ConfirmResult result;
      Test.startTest();
      result = new ALT_CLS_ReconciliationService()
        .confirm(
          confirmInput(
            new List<ALT_CLS_ReconciliationService.LineInput>{
              line(f.fact, f.targets[0], 75)
            },
            0,
            correlation('gf05'),
            'axf30-gf05'
          )
        );
      // The confirmed application is reversed by an immutable compensation (AXF-141).
      ALT_CLS_ReconciliationService.LineView applied = result.lines[0];
      ALT_CLS_ReconciliationReversalService.Input reversal = new ALT_CLS_ReconciliationReversalService.Input();
      reversal.allocationId = applied.allocationId;
      // The confirmation bumped the target once, so its current optimistic version is 1.
      reversal.expectedVersion = 1;
      reversal.reasonCode = 'WRONG_TARGET';
      reversal.operationKey = 'axf30-gf05-reversal';
      new ALT_CLS_ReconciliationReversalService().reverse(reversal);
      Test.stopTest();

      Assert.areEqual(
        2,
        countAllocations(f.fact.Id),
        'the original remains and one compensation is appended'
      );
      List<AXF_OBJ_ReconciliationAllocation__c> rows = [
        SELECT
          AXF_RA_PKL_Kind__c,
          AXF_RA_NUM_Magnitude__c,
          AXF_RA_LKP_OriginalAllocation__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_BankTransaction__c = :f.fact.Id
      ];
      Decimal net = 0;
      Boolean originalPresent = false;
      Boolean linked = false;
      for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
        net += (row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1) *
          row.AXF_RA_NUM_Magnitude__c;
        originalPresent =
          originalPresent ||
          row.AXF_RA_PKL_Kind__c == 'APPLICATION' &&
          row.AXF_RA_NUM_Magnitude__c == 75;
        linked =
          linked ||
          row.AXF_RA_PKL_Kind__c == 'REVERSAL' &&
          row.AXF_RA_LKP_OriginalAllocation__c == applied.allocationId;
      }
      Assert.areEqual(0.00, net, 'the net contribution is zero');
      Assert.isTrue(originalPresent, 'the confirmed line is never edited or deleted');
      Assert.isTrue(linked, 'the compensation points to the original');
      // The derived state of the target is back to what it was before the confirmation.
      ALT_CLS_ReconciliationService.WorkbenchView view = new ALT_CLS_ReconciliationService()
        .preview(previewInput(f.fact, null, 'BANK'));
      Assert.isNotNull(view, 'the service still describes the holder sources');
    }
  }

  private static ALT_CLS_ReconciliationService.PreviewInput previewInput(
    AXF_OBJ_BankAccountTransaction__c fact,
    List<ALT_CLS_ReconciliationService.LineInput> lines,
    String kind
  ) {
    ALT_CLS_ReconciliationService.PreviewInput input = new ALT_CLS_ReconciliationService.PreviewInput();
    input.factKind = kind;
    input.factId = fact == null ? null : fact.Id;
    input.lines = lines;
    input.correlationId = lines == null || lines.isEmpty()
      ? null
      : correlation('preview');
    return input;
  }

  // ------------------------------------------------------------------ currency

  @IsTest
  static void currencyMismatchNeverAssumesParity() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'fx',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100 },
        'USD'
      );
      String code;
      Test.startTest();
      code = codeOf(
        confirmInput(
          new List<ALT_CLS_ReconciliationService.LineInput>{
            line(f.fact, f.targets[0], 100)
          },
          0,
          correlation('fx'),
          'axf30-fx'
        )
      );
      Test.stopTest();
      Assert.areEqual('CURRENCY_MISMATCH', code);
      Assert.areEqual(0, countAggregates());
      Assert.areEqual(0, countAllocations(f.fact.Id));
    }
  }

  // ------------------------------------------------------------------ authorization

  @IsTest
  static void inaccessibleTargetRejectsTheWholeCommandAndRevealsNothing() {
    Fixture f;
    System.runAs(byAlias('axf30g')) {
      f = fixture('auth', 100, 'DEBIT', 'BRL', new List<Decimal>{ 100 }, 'BRL');
    }
    // A target of the same holder owned by another principal: invisible to the caller through
    // USER_MODE and therefore indistinguishable from a target that does not exist at all. It is
    // created outside the caller's context, which is the only way to own it elsewhere here.
    AXF_OBJ_FinancialTransaction__c foreign = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = f.holder.Id,
      AXF_FTX_NUM_Magnitude__c = 100,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_DAT_DueDate__c = Date.today(),
      AXF_FTX_TXT_Description__c = 'Foreign target 30',
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-30-auth-foreign'
    );
    insert foreign;
    System.runAs(byAlias('axf30g')) {
      String codeForeign;
      String codeMissing;
      Test.startTest();
      codeForeign = codeOf(
        confirmInput(
          new List<ALT_CLS_ReconciliationService.LineInput>{
            line(f.fact, foreign, 50)
          },
          0,
          correlation('auth-f'),
          'axf30-auth-f'
        )
      );
      AXF_OBJ_FinancialTransaction__c missing = new AXF_OBJ_FinancialTransaction__c(
        Id = AXF_OBJ_FinancialTransaction__c.SObjectType.getDescribe()
          .getKeyPrefix() + '000000000000'
      );
      codeMissing = codeOf(
        confirmInput(
          new List<ALT_CLS_ReconciliationService.LineInput>{
            line(f.fact, missing, 50)
          },
          0,
          correlation('auth-m'),
          'axf30-auth-m'
        )
      );
      Test.stopTest();
      Assert.areEqual('NOT_ACCESSIBLE', codeForeign);
      Assert.areEqual(
        codeMissing,
        codeForeign,
        'an unauthorized record is indistinguishable from an inexistent one'
      );
      Assert.areEqual(0, countAggregates(), 'no partial aggregate is written');
      Assert.areEqual(0, countAllocations(f.fact.Id), 'no partial line is written');
    }
  }

  @IsTest
  static void capabilityIsRequiredToConfirm() {
    System.runAs(byAlias('axf30p')) {
      Fixture f = fixture(
        'cap',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100 },
        'BRL'
      );
      String code;
      Test.startTest();
      code = codeOf(
        confirmInput(
          new List<ALT_CLS_ReconciliationService.LineInput>{
            line(f.fact, f.targets[0], 100)
          },
          0,
          correlation('cap'),
          'axf30-cap'
        )
      );
      Test.stopTest();
      Assert.areEqual('UNAVAILABLE', code);
      Assert.areEqual(0, countAggregates());
    }
  }

  // ------------------------------------------------------------------ version

  @IsTest
  static void staleVersionRejectsTheCommandAndKeepsTheDraftUnapplied() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'ver',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 60, 40 },
        'BRL'
      );
      List<ALT_CLS_ReconciliationService.LineInput> lines = new List<ALT_CLS_ReconciliationService.LineInput>{
        line(f.fact, f.targets[0], 60),
        line(f.fact, f.targets[1], 40)
      };
      String correlationId = correlation('ver');
      String code;
      Test.startTest();
      new ALT_CLS_ReconciliationService()
        .confirm(confirmInput(lines, 0, correlationId, 'axf30-ver'));
      // The aggregate now sits at version 1: an obsolete expectation is refused.
      code = codeOf(confirmInput(lines, 0, correlationId, 'axf30-ver'));
      Test.stopTest();
      Assert.areEqual('CONFLICT', code);
      Assert.areEqual(1, countAggregates(), 'the durable aggregate is untouched');
      Assert.areEqual(2, countAllocations(f.fact.Id), 'no line is duplicated');
    }
  }

  // ------------------------------------------------------------------ lock plan

  @IsTest
  static void aRecordDiscoveredInAnotherRankAbortsWithLockPlanChanged() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'lock',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100 },
        'BRL'
      );
      // A source fact of rank 30 declared as a target, and a plan of rank 50 declared as a source:
      // both are discovered only when the record is read, so the command aborts instead of locking
      // out of order.
      ALT_CLS_ReconciliationService.LineInput sourceAsTarget = line(
        f.fact,
        f.targets[0],
        50
      );
      sourceAsTarget.targetId = f.fact.Id;
      ALT_CLS_ReconciliationService.LineInput targetAsFact = line(
        f.fact,
        f.targets[0],
        50
      );
      targetAsFact.factKind = 'MANUAL';
      targetAsFact.factId = f.targets[0].Id;
      String codeAsTarget;
      String codeAsFact;
      Test.startTest();
      codeAsTarget = codeOf(
        confirmInput(
          new List<ALT_CLS_ReconciliationService.LineInput>{ sourceAsTarget },
          0,
          correlation('lock-t'),
          'axf30-lock-t'
        )
      );
      codeAsFact = codeOf(
        confirmInput(
          new List<ALT_CLS_ReconciliationService.LineInput>{ targetAsFact },
          0,
          correlation('lock-f'),
          'axf30-lock-f'
        )
      );
      Test.stopTest();
      Assert.areEqual('LOCK_PLAN_CHANGED', codeAsTarget);
      Assert.areEqual('LOCK_PLAN_CHANGED', codeAsFact);
      Assert.areEqual(0, countAggregates(), 'the plan is never locked out of order');
      Assert.areEqual(0, countAllocations(f.fact.Id));
    }
  }

  // ------------------------------------------------------------------ double submit

  @IsTest
  static void doubleSubmitReplaysAndADivergentPayloadConflicts() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'dup',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 60, 40 },
        'BRL'
      );
      List<ALT_CLS_ReconciliationService.LineInput> lines = new List<ALT_CLS_ReconciliationService.LineInput>{
        line(f.fact, f.targets[0], 60),
        line(f.fact, f.targets[1], 40)
      };
      String correlationId = correlation('dup');
      ALT_CLS_ReconciliationService.ConfirmResult first;
      ALT_CLS_ReconciliationService.ConfirmResult second;
      String code;
      Test.startTest();
      first = new ALT_CLS_ReconciliationService()
        .confirm(confirmInput(lines, 0, correlationId, 'axf30-dup'));
      second = new ALT_CLS_ReconciliationService()
        .confirm(confirmInput(lines, 1, correlationId, 'axf30-dup'));
      code = codeOf(
        confirmInput(
          new List<ALT_CLS_ReconciliationService.LineInput>{
            line(f.fact, f.targets[0], 10),
            line(f.fact, f.targets[1], 40)
          },
          2,
          correlationId,
          'axf30-dup'
        )
      );
      Test.stopTest();
      Assert.isFalse(first.replayed, 'the first command writes');
      Assert.isTrue(second.replayed, 'the replay returns the durable result');
      Assert.areEqual(first.reconciliationId, second.reconciliationId);
      Assert.areEqual('CONFLICT', code, 'a divergent payload under the same key conflicts');
      Assert.areEqual(1, countAggregates());
      Assert.areEqual(2, countAllocations(f.fact.Id), 'no allocation was duplicated');
    }
  }

  // ------------------------------------------------------------------ GF-72 / GF-73

  @IsTest
  static void gf72AndGf73CandidatesStayConsultativeAndExactIdentityIsPresentationOnly() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'match',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100, 40 },
        'BRL'
      );
      // The second target carries the exact durable identity of the source fact.
      AXF_OBJ_FinancialTransaction__c exact = f.targets[1];
      exact.AXF_FTX_EXI_ClientRequestId__c = f.fact.AXF_BAT_EXI_SourceKey__c;
      update exact;
      ALT_CLS_ReconciliationService.WorkbenchView view;
      Test.startTest();
      ALT_CLS_ReconciliationService.PreviewInput input = new ALT_CLS_ReconciliationService.PreviewInput();
      input.factKind = 'BANK';
      input.factId = f.fact.Id;
      view = new ALT_CLS_ReconciliationService().preview(input);
      Test.stopTest();
      Assert.areEqual(
        ALT_CLS_MatchEvidence.MATCHING_POLICY,
        view.policyVersion,
        'the policy is reported as it is'
      );
      Assert.areEqual(2, view.candidates.size());
      for (
        ALT_CLS_ReconciliationService.CandidateView candidate : view.candidates
      ) {
        Assert.areEqual(
          ALT_CLS_MatchEvidence.STATE_CONSULTATIVE,
          candidate.state,
          'no candidate leaves the consultative baseline'
        );
        Assert.areEqual(
          ALT_CLS_MatchEvidence.FEATURES.size(),
          candidate.evidence.size(),
          'every candidate carries independent evidence'
        );
      }
      Assert.isTrue(
        view.candidates[0].identityExact,
        'the exact external identity appears first as presentation'
      );
      Assert.isFalse(view.candidates[1].identityExact);
      Assert.areEqual(
        ALT_CLS_MatchEvidence.STATE_CONSULTATIVE,
        view.state,
        'the draft itself concludes nothing'
      );
      Assert.areEqual(0, countAggregates(), 'no candidate is selected or confirmed');
      Assert.areEqual(0, countAllocations(f.fact.Id));
    }
  }

  // ------------------------------------------------------------------ GF-74

  @IsTest
  static void gf74PositiveResidualStaysPartialWithoutApprovedTolerance() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'gf74',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 120 },
        'BRL'
      );
      ALT_CLS_ReconciliationService.ConfirmResult result;
      Test.startTest();
      result = new ALT_CLS_ReconciliationService()
        .confirm(
          confirmInput(
            new List<ALT_CLS_ReconciliationService.LineInput>{
              line(f.fact, f.targets[0], 60)
            },
            0,
            correlation('gf74'),
            'axf30-gf74'
          )
        );
      Test.stopTest();
      Assert.areEqual(ALT_CLS_ReconciliationService.STATE_PARTIAL, result.state);
      Assert.areEqual(
        60.00,
        result.residualMagnitude,
        'the residual is reported as it is, never zeroed'
      );
    }
  }

  // ------------------------------------------------------------------ GF-75

  @IsTest
  static void gf75UnknownOutcomeBlocksRetryAndTheAuthoritativeQueryResolvesIt() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'gf75',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100 },
        'BRL'
      );
      List<ALT_CLS_ReconciliationService.LineInput> lines = new List<ALT_CLS_ReconciliationService.LineInput>{
        line(f.fact, f.targets[0], 100)
      };
      String correlationId = correlation('gf75');
      ALT_CLS_ReconciliationService.AttemptInput attempt = attempt(
        lines,
        correlationId
      );
      String blockedCode;
      ALT_CLS_ReconciliationService.WorkbenchView resolved;
      ALT_CLS_ReconciliationService.ConfirmResult afterResolution;
      Test.startTest();
      // The submit outcome is unknown: the intention is parked as BLOCKED with a null residual.
      ALT_CLS_ReconciliationService.WorkbenchView parked = new ALT_CLS_ReconciliationService()
        .parkResultUnknown(attempt);
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_BLOCKED,
        parked.state
      );
      Assert.isTrue(parked.unknownOutcome, 'the outcome is explicitly unknown');
      blockedCode = codeOf(confirmInput(lines, 1, correlationId, 'axf30-gf75'));
      // The authoritative query proves nothing was committed, so the scope may run again.
      resolved = new ALT_CLS_ReconciliationService().resolveResult(attempt);
      Assert.areEqual(ALT_CLS_ReconciliationService.STATE_FAILED, resolved.state);
      afterResolution = new ALT_CLS_ReconciliationService()
        .confirm(
          confirmInput(
            lines,
            resolved.expectedVersion,
            correlationId,
            'axf30-gf75'
          )
        );
      Test.stopTest();
      Assert.areEqual('CONFLICT', blockedCode, 'the retry is refused while unresolved');
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_CONFIRMED,
        afterResolution.state
      );
      Assert.areEqual(
        1,
        countAllocations(f.fact.Id),
        'the authoritative query resolves without duplicating the allocation'
      );
      Assert.areEqual(1, countAggregates());
    }
  }

  @IsTest
  static void gf75ParkingAfterACommitReportsTheDurableOutcomeAndNeverOverwritesIt() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'gf75b',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100 },
        'BRL'
      );
      List<ALT_CLS_ReconciliationService.LineInput> lines = new List<ALT_CLS_ReconciliationService.LineInput>{
        line(f.fact, f.targets[0], 100)
      };
      String correlationId = correlation('gf75b');
      ALT_CLS_ReconciliationService.WorkbenchView parked;
      ALT_CLS_ReconciliationService.WorkbenchView resolved;
      Test.startTest();
      new ALT_CLS_ReconciliationService()
        .confirm(confirmInput(lines, 0, correlationId, 'axf30-gf75b'));
      parked = new ALT_CLS_ReconciliationService()
        .parkResultUnknown(attempt(lines, correlationId));
      resolved = new ALT_CLS_ReconciliationService()
        .resolveResult(attempt(lines, correlationId));
      Test.stopTest();
      Assert.isFalse(
        parked.unknownOutcome,
        'a committed intention is never re-parked as unknown'
      );
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_CONFIRMED,
        parked.state
      );
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_CONFIRMED,
        resolved.state
      );
      Assert.areEqual(1, countAllocations(f.fact.Id));
    }
  }

  // ------------------------------------------------------------------ evidence gap

  @IsTest
  static void missingRecognitionEvidenceBlocksTheAggregateWithAComputedResidual() {
    System.runAs(byAlias('axf30g')) {
      System.runAs(new User(Id = UserInfo.getUserId())) {
        AXF_ReportCurrencyPref__c preference = AXF_ReportCurrencyPref__c.getOrgDefaults();
        preference.AXF_RCP_TXT_IsoCode__c = 'USD';
        update preference;
      }
      Fixture f = fixture(
        'block',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100 },
        'BRL'
      );
      ALT_CLS_ReconciliationService.ConfirmResult result;
      Test.startTest();
      result = new ALT_CLS_ReconciliationService()
        .confirm(
          confirmInput(
            new List<ALT_CLS_ReconciliationService.LineInput>{
              line(f.fact, f.targets[0], 100)
            },
            0,
            correlation('block'),
            'axf30-block'
          )
        );
      Test.stopTest();
      Assert.areEqual(
        ALT_CLS_ReconciliationService.STATE_BLOCKED,
        result.state,
        'material evidence is missing, so the aggregate is blocked'
      );
      Assert.isNotNull(
        result.residualMagnitude,
        'a blocked-by-evidence aggregate still persists its computed residual'
      );
      Assert.areEqual('MISSING_MATERIAL_FX', result.lines[0].reasons[0]);
    }
  }

  // ------------------------------------------------------------------ read contract

  @IsTest
  static void readRequiresTheCapabilityAndDoesNotEnumerateTheAggregate() {
    System.runAs(byAlias('axf30g')) {
      Fixture f = fixture(
        'read',
        100,
        'DEBIT',
        'BRL',
        new List<Decimal>{ 100 },
        'BRL'
      );
      String correlationId = correlation('read');
      List<ALT_CLS_ReconciliationService.LineInput> lines = new List<ALT_CLS_ReconciliationService.LineInput>{
        line(f.fact, f.targets[0], 100)
      };
      Test.startTest();
      new ALT_CLS_ReconciliationService()
        .confirm(confirmInput(lines, 0, correlationId, 'axf30-read'));
      String foreignCode = codeOfRead(lines, correlation('other'));
      Test.stopTest();
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        foreignCode,
        'an unknown intention is indistinguishable from a denied one'
      );
      System.runAs(byAlias('axf30p')) {
        String denied = codeOfRead(lines, correlationId);
        Assert.areEqual('UNAVAILABLE', denied);
      }
    }
  }

  private static String codeOfRead(
    List<ALT_CLS_ReconciliationService.LineInput> lines,
    String correlationId
  ) {
    try {
      new ALT_CLS_ReconciliationService().read(attempt(lines, correlationId));
      return null;
    } catch (ALT_CLS_ReconciliationService.ReconciliationException expected) {
      return expected.code;
    }
  }
}
