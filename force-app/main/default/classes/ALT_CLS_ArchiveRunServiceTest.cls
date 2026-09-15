/**
 * @description AXF-95: archive runs are idempotent, resumable and verified; the hot copy is
 * never removed; the archive is read only through a bounded, authorized, keyset-paginated
 * service that never rehydrates; policy changes move the hot window without code changes.
 * The Big Object store is replaced by ALT_CLS_ArchiveTestStore (immediate DML is not rolled
 * back in tests); real index/upsert/pagination behaviour is evidenced by the AXF-102 spike.
 */
@IsTest
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_ArchiveRunServiceTest {
  private static final Date TODAY = Date.newInstance(2026, 9, 15);
  private static final Date HOT_START = Date.newInstance(2024, 9, 1);

  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf95g', 'axf95p', 'axf95n' }) {
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
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    Assert.areEqual(3, permissionSets.size(), 'permission sets must exist');
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = users[0].Id,
        PermissionSetId = permissionSets.get('AXF_PS_GestorFinanceiro')
      ),
      new PermissionSetAssignment(
        AssigneeId = users[0].Id,
        PermissionSetId = permissionSets.get('AXF_PS_FinancialEntry')
      ),
      new PermissionSetAssignment(
        AssigneeId = users[1].Id,
        PermissionSetId = permissionSets.get('AXF_PS_GestorFinanceiro')
      ),
      new PermissionSetAssignment(
        AssigneeId = users[1].Id,
        PermissionSetId = permissionSets.get('AXF_PS_FinancialEntry')
      ),
      new PermissionSetAssignment(
        AssigneeId = users[2].Id,
        PermissionSetId = permissionSets.get('AXF_PS_Participante')
      )
    };
  }

  private static void policy(
    Integer months,
    Integer batchSize,
    Boolean enabled
  ) {
    ALT_CLS_ArchivePolicy.policyOverride = new AXF_CMT_ArchivePolicy__mdt(
      DeveloperName = 'Default',
      AXF_APL_TXT_PolicyVersion__c = 'archive-policy@test',
      AXF_APL_NUM_HotWindowMonths__c = months,
      AXF_APL_NUM_BatchSize__c = batchSize,
      AXF_APL_BOL_Enabled__c = enabled,
      AXF_APL_BOL_AllowHotRemoval__c = false
    );
    ALT_CLS_ArchivePolicy.todayOverride = TODAY;
  }

  private static ALT_CLS_ArchiveTestStore fakeStore() {
    ALT_CLS_ArchiveTestStore store = new ALT_CLS_ArchiveTestStore();
    ALT_CLS_ArchiveStore.storeOverride = store;
    // Batches run only at Test.stopTest() and only once per test: tests drive them directly.
    ALT_CLS_ArchiveRunService.enqueueBatches = false;
    return store;
  }

  private class Fixture {
    Account holder;
    AXF_OBJ_BankAccount__c bank;
    AXF_OBJ_CreditCard__c card;
    Integer oldBank = 0;
    Integer oldCard = 0;
    Integer oldManual = 0;
  }

  private static Fixture fixture(String key) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Titular ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    f.bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_EXI_ManualKey__c = 'manual-' + key + '-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0
    );
    insert f.bank;
    f.card = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = f.holder.Id,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'USD',
      AXF_CC_TXT_InstitutionName__c = 'Cartao ' + key,
      AXF_CC_TXT_LastFourMasked__c = '0' + key,
      AXF_CC_EXI_ManualKey__c = 'card-' + key + '-' + System.now().getTime(),
      AXF_CC_NUM_Version__c = 0
    );
    insert f.card;
    List<AXF_OBJ_BankAccountTransaction__c> bats = new List<AXF_OBJ_BankAccountTransaction__c>();
    // Five old debits on one day, one old credit on another, one recent (kept hot).
    for (Integer i = 0; i < 5; i++) {
      bats.add(
        bat(
          f.bank.Id,
          key + '-old-' + i,
          10 + i,
          'DEBIT',
          Date.newInstance(2023, 3, 15)
        )
      );
    }
    bats.add(
      bat(
        f.bank.Id,
        key + '-credit',
        1000,
        'CREDIT',
        Date.newInstance(2022, 12, 31)
      )
    );
    bats.add(
      bat(f.bank.Id, key + '-hot', 77, 'DEBIT', Date.newInstance(2025, 1, 10))
    );
    insert bats;
    f.oldBank = 6;
    insert new List<AXF_OBJ_CreditCardTransaction__c>{
      cct(f.card.Id, key + '-c-old', 55.5, Date.newInstance(2024, 8, 31)),
      cct(f.card.Id, key + '-c-hot', 5, HOT_START)
    };
    f.oldCard = 1;
    insert new List<AXF_OBJ_FinancialTransaction__c>{
      ftx(f.holder.Id, key + '-f-old', 300, Date.newInstance(2021, 6, 1)),
      ftx(f.holder.Id, key + '-f-hot', 3, Date.newInstance(2026, 1, 1))
    };
    f.oldManual = 1;
    return f;
  }

  private static AXF_OBJ_BankAccountTransaction__c bat(
    Id bankId,
    String key,
    Decimal magnitude,
    String direction,
    Date day
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_EXI_SourceKey__c = 'bat-' + key,
      AXF_BAT_PKL_Source__c = 'MANUAL',
      AXF_BAT_DAT_Date__c = day,
      AXF_BAT_NUM_Magnitude__c = magnitude,
      AXF_BAT_PKL_Direction__c = direction,
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = 'Fato ' + key,
      AXF_BAT_NUM_Version__c = 0
    );
  }

  private static AXF_OBJ_CreditCardTransaction__c cct(
    Id cardId,
    String key,
    Decimal magnitude,
    Date day
  ) {
    return new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = cardId,
      AXF_CCT_EXI_SourceKey__c = 'cct-' + key,
      AXF_CCT_PKL_Source__c = 'MANUAL',
      AXF_CCT_DAT_Date__c = day,
      AXF_CCT_NUM_Magnitude__c = magnitude,
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_PKL_Status__c = 'POSTED',
      AXF_CCT_TXT_CurrencyIsoCode__c = 'USD',
      AXF_CCT_TXT_Description__c = 'Cartao ' + key,
      AXF_CCT_NUM_Version__c = 0
    );
  }

  private static AXF_OBJ_FinancialTransaction__c ftx(
    Id accountId,
    String key,
    Decimal magnitude,
    Date day
  ) {
    return new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = accountId,
      AXF_FTX_NUM_Magnitude__c = magnitude,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = day,
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-' + key
    );
  }

  /** Drives a run's batch synchronously (chunks of two), outside Test.startTest(). */
  private static void drive(Id runId) {
    AXF_CLS_ArchiveRunBatch batch = new AXF_CLS_ArchiveRunBatch(runId);
    Database.QueryLocatorIterator rows = batch.start(null).iterator();
    List<SObject> chunk = new List<SObject>();
    while (rows.hasNext()) {
      chunk.add(rows.next());
      if (chunk.size() == 2) {
        batch.execute(null, chunk);
        chunk = new List<SObject>();
      }
    }
    if (!chunk.isEmpty()) {
      batch.execute(null, chunk);
    }
    batch.finish(null);
  }

  private static Decimal num(Object value) {
    return Decimal.valueOf(String.valueOf(value));
  }

  private static ALT_CLS_ArchiveRunService.RunView runOf(
    Id accountId,
    String family
  ) {
    for (
      ALT_CLS_ArchiveRunService.RunView view : new ALT_CLS_ArchiveRunService()
        .listRuns(accountId)
    ) {
      if (view.family == family) {
        return view;
      }
    }
    return null;
  }

  private static ALT_CLS_ArchiveReadService.ReadInput readInput(
    Id accountId,
    Date fromDate,
    Date toDate,
    Integer pageSize
  ) {
    ALT_CLS_ArchiveReadService.ReadInput input = new ALT_CLS_ArchiveReadService.ReadInput();
    input.accountId = accountId;
    input.fromDate = fromDate;
    input.toDate = toDate;
    input.pageSize = pageSize;
    return input;
  }

  @IsTest
  static void archivesEveryFamilyIdempotentlyVerifiesParityAndKeepsTheHotCopy() {
    ALT_CLS_ArchiveTestStore store = fakeStore();
    policy(24, 2, true);
    System.runAs(byAlias('axf95g')) {
      Fixture f = fixture('a');
      Integer hotBefore = [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccountTransaction__c
      ];
      ALT_CLS_ArchiveRunService service = new ALT_CLS_ArchiveRunService();
      Test.startTest();
      ALT_CLS_ArchiveRunService.RunView bank = service.start(
        f.holder.Id,
        'BAT'
      );
      drive(bank.runId);
      drive(service.start(f.holder.Id, 'CCT').runId);
      drive(service.start(f.holder.Id, 'FTX').runId);
      Test.stopTest();
      Assert.isFalse(bank.resumed);
      Assert.areEqual(HOT_START, bank.hotWindowStart, 'janela = 24 meses');
      ALT_CLS_ArchiveRunService.RunView done = runOf(f.holder.Id, 'BAT');
      Assert.areEqual('HOT_RETAINED', done.phase, 'motivo: ' + done.reason);
      Assert.areEqual(
        f.oldBank,
        done.archived,
        'so o que esta antes da janela'
      );
      Assert.areEqual(f.oldBank, done.verified);
      Assert.areEqual(Date.newInstance(2023, 3, 15), done.watermark);
      Assert.isTrue(
        done.hotRemoval.startsWith('BLOCKED:'),
        'remocao: ' + done.hotRemoval
      );
      Map<String, Object> amounts = (Map<String, Object>) JSON.deserializeUntyped(
        done.amountsByCurrency
      );
      Map<String, Object> brl = (Map<String, Object>) amounts.get('BRL');
      Assert.areEqual(6, num(brl.get('count')));
      Assert.areEqual(1000, num(brl.get('credit')));
      Assert.areEqual(60, num(brl.get('debit')), '10+11+12+13+14');
      Assert.areEqual(
        f.oldCard,
        runOf(f.holder.Id, 'CCT').archived,
        'cartao no ultimo dia antes da janela'
      );
      Assert.areEqual(f.oldManual, runOf(f.holder.Id, 'FTX').archived);
      Assert.areEqual(
        f.oldBank + f.oldCard + f.oldManual,
        store.rows.size(),
        'uma linha por fato antigo'
      );
      Assert.areEqual(
        hotBefore,
        [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c],
        'copia quente preservada'
      );
      // Archive row content: deterministic identity, UTC-midnight date, hash, snapshot.
      String expectedKey = ALT_CLS_ArchiveRunService.archiveKey(
        'BAT',
        'bat-a-credit'
      );
      AXF_OBJ_TransactionArchive__b credit;
      for (AXF_OBJ_TransactionArchive__b row : store.rows.values()) {
        if (row.AXF_ARC_TXT_ArchiveKey__c == expectedKey) {
          credit = row;
        }
      }
      Assert.isNotNull(credit);
      Assert.areEqual(
        String.valueOf(f.holder.Id),
        credit.AXF_ARC_TXT_AccountKey__c
      );
      Assert.areEqual(
        Datetime.newInstanceGmt(2022, 12, 31, 0, 0, 0),
        credit.AXF_ARC_DT_BookingDate__c
      );
      Assert.areEqual('CREDIT', credit.AXF_ARC_TXT_Direction__c);
      Assert.areEqual('Banco a', credit.AXF_ARC_TXT_InstitutionLabel__c);
      Assert.areEqual(
        ALT_CLS_ArchiveRunService.contentHash(credit),
        credit.AXF_ARC_TXT_ContentHash__c
      );
      Assert.isTrue(credit.AXF_ARC_LTX_Snapshot__c.contains('bat-a-credit'));
      Assert.areEqual(
        'archive-policy@test',
        credit.AXF_ARC_TXT_PolicyVersion__c
      );
    }
  }

  @IsTest
  static void replayAndResumeNeverDuplicateAndRecoverFromTheWatermark() {
    ALT_CLS_ArchiveTestStore store = fakeStore();
    policy(24, 2, true);
    System.runAs(byAlias('axf95g')) {
      Fixture f = fixture('b');
      ALT_CLS_ArchiveRunService service = new ALT_CLS_ArchiveRunService();
      // Second chunk fails after the first one is checkpointed.
      store.failAtWrite = 2;
      Test.startTest();
      drive(service.start(f.holder.Id, 'BAT').runId);
      Test.stopTest();
      ALT_CLS_ArchiveRunService.RunView failed = runOf(f.holder.Id, 'BAT');
      Assert.areEqual('FAILED', failed.phase);
      Assert.isTrue(failed.reason.startsWith('CHUNK_FAILED'), failed.reason);
      Assert.areEqual(2, store.rows.size(), 'primeiro chunk gravado');
      Assert.areEqual(
        Date.newInstance(2023, 3, 15),
        failed.watermark,
        'ultimo dia gravado: credito de 2022 + primeiro debito de 2023'
      );
      Assert.isNull(failed.hotRemoval);

      // Resume: reads from the watermark day on, upserts by key, verifies against the hot copy.
      ALT_CLS_ArchiveRunService.RunView resumed = service.start(
        f.holder.Id,
        'BAT'
      );
      Assert.isTrue(resumed.resumed);
      Assert.areEqual('SCANNING', resumed.phase);
      drive(resumed.runId);
      ALT_CLS_ArchiveRunService.RunView done = runOf(f.holder.Id, 'BAT');
      Assert.areEqual('HOT_RETAINED', done.phase, 'motivo: ' + done.reason);
      Assert.areEqual(f.oldBank, store.rows.size(), 'sem duplicatas');
      Assert.areEqual(f.oldBank, done.verified);
      Assert.areEqual(
        f.oldBank,
        done.archived,
        'contagem autoritativa da verificacao'
      );

      // Replay of a finished run: full re-scan, still one row per fact, same content hash.
      Integer writesBefore = store.writes;
      drive(service.start(f.holder.Id, 'BAT').runId);
      Assert.isTrue(store.writes > writesBefore);
      Assert.areEqual(f.oldBank, store.rows.size());
      Assert.areEqual('HOT_RETAINED', runOf(f.holder.Id, 'BAT').phase);

      // A hot change after archiving is caught by the parity check, not silently absorbed.
      AXF_OBJ_BankAccountTransaction__c drifted = [
        SELECT Id, AXF_BAT_NUM_Magnitude__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_EXI_SourceKey__c = 'bat-b-old-0'
      ];
      Map<String, ALT_CLS_ArchiveRunService.CurrencyTotal> hot = ALT_CLS_ArchiveRunService.hotTotals(
        ALT_CLS_ArchiveRunService.read(done.runId)
      );
      Map<String, ALT_CLS_ArchiveRunService.CurrencyTotal> archive = new Map<String, ALT_CLS_ArchiveRunService.CurrencyTotal>(
        hot
      );
      ALT_CLS_ArchiveRunService.CurrencyTotal tampered = new ALT_CLS_ArchiveRunService.CurrencyTotal();
      tampered.count = hot.get('BRL').count;
      tampered.credit = hot.get('BRL').credit;
      tampered.debit = hot.get('BRL').debit + 1;
      archive.put('BRL', tampered);
      Assert.isNotNull(ALT_CLS_ArchiveRunService.mismatch(hot, archive));
      Assert.isNull(ALT_CLS_ArchiveRunService.mismatch(hot, hot));
      Assert.isNotNull(drifted);
    }
  }

  @IsTest
  static void readIsAuthorizedBoundedPaginatedAndNeverRehydrates() {
    ALT_CLS_ArchiveTestStore store = fakeStore();
    policy(24, 200, true);
    Account holder;
    Account other;
    System.runAs(byAlias('axf95g')) {
      holder = fixture('c').holder;
    }
    System.runAs(byAlias('axf95p')) {
      other = fixture('d').holder;
    }
    // Seven rows for the holder (five on one day) plus rows of another holder.
    AXF_OBJ_ArchiveRun__c pseudo = new AXF_OBJ_ArchiveRun__c(
      AXF_ARR_LKP_Account__c = holder.Id,
      AXF_ARR_EXI_RunKey__c = 'seed',
      AXF_ARR_TXT_PolicyVersion__c = 'seed'
    );
    List<AXF_OBJ_TransactionArchive__b> seed = new List<AXF_OBJ_TransactionArchive__b>();
    for (Integer i = 0; i < 5; i++) {
      seed.add(
        ALT_CLS_ArchiveRunService.toArchiveRow(
          'BAT',
          bat(
            null,
            'seed-' + i,
            10 + i,
            'DEBIT',
            Date.newInstance(2023, 3, 15)
          ),
          pseudo
        )
      );
    }
    seed.add(
      ALT_CLS_ArchiveRunService.toArchiveRow(
        'BAT',
        bat(null, 'seed-older', 1, 'DEBIT', Date.newInstance(2023, 3, 14)),
        pseudo
      )
    );
    seed.add(
      ALT_CLS_ArchiveRunService.toArchiveRow(
        'BAT',
        bat(null, 'seed-oldest', 2, 'DEBIT', Date.newInstance(2020, 1, 1)),
        pseudo
      )
    );
    store.write(seed);
    pseudo.AXF_ARR_LKP_Account__c = other.Id;
    store.write(
      new List<AXF_OBJ_TransactionArchive__b>{
        ALT_CLS_ArchiveRunService.toArchiveRow(
          'BAT',
          bat(null, 'foreign', 9, 'DEBIT', Date.newInstance(2023, 3, 15)),
          pseudo
        )
      }
    );
    Integer hotBefore = [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c];
    System.runAs(byAlias('axf95g')) {
      ALT_CLS_ArchiveReadService service = new ALT_CLS_ArchiveReadService();
      Test.startTest();
      Set<String> seen = new Set<String>();
      Integer pages = 0;
      ALT_CLS_ArchiveReadService.ReadInput input = readInput(
        holder.Id,
        null,
        null,
        3
      );
      ALT_CLS_ArchiveReadService.ReadResult page;
      do {
        page = service.read(input);
        pages++;
        for (ALT_CLS_ArchiveReadService.ArchivedRow row : page.rows) {
          Assert.isTrue(seen.add(row.archiveKey), 'sem repeticao');
          Assert.isTrue(row.archived);
        }
        input.cursorDate = page.nextCursorDate;
        input.cursorKey = page.nextCursorKey;
      } while (page.hasMore);
      Assert.areEqual(7, seen.size(), 'cinco no mesmo dia + dois mais antigos');
      Assert.areEqual(3, pages);
      Assert.areEqual(HOT_START, page.hotWindowStart);
      Assert.areEqual(
        HOT_START.addDays(-1),
        page.toDate,
        'limite superior = vespera da janela'
      );
      // Newest first, per the index.
      ALT_CLS_ArchiveReadService.ReadResult first = service.read(
        readInput(holder.Id, null, null, 50)
      );
      Assert.areEqual(Date.newInstance(2023, 3, 15), first.rows[0].bookingDate);
      Assert.areEqual(Date.newInstance(2020, 1, 1), first.rows[6].bookingDate);
      Assert.isFalse(first.hasMore);
      // A period inside the hot window has nothing archived; a bounded period filters.
      Assert.isTrue(
        service.read(readInput(holder.Id, HOT_START, TODAY, 50)).rows.isEmpty()
      );
      Assert.areEqual(
        1,
        service.read(
            readInput(
              holder.Id,
              Date.newInstance(2019, 1, 1),
              Date.newInstance(2021, 1, 1),
              50
            )
          )
          .rows.size()
      );
      // Another holder's archive is never returned, whatever the request says.
      try {
        service.read(readInput(other.Id, null, null, 50));
        Assert.fail('titular alheio');
      } catch (ALT_CLS_ArchiveReadService.ArchiveReadException expected) {
        Assert.areEqual('NOT_ACCESSIBLE', expected.code);
      }
      for (
        ALT_CLS_ArchiveReadService.ReadInput bad : new List<ALT_CLS_ArchiveReadService.ReadInput>{
          null,
          readInput(null, null, null, 50),
          readInput(
            holder.Id,
            Date.newInstance(2023, 2, 1),
            Date.newInstance(2023, 1, 1),
            50
          )
        }
      ) {
        try {
          service.read(bad);
          Assert.fail('INVALID_INPUT');
        } catch (ALT_CLS_ArchiveReadService.ArchiveReadException expected) {
          Assert.areEqual('INVALID_INPUT', expected.code);
        }
      }
      Test.stopTest();
    }
    System.runAs(byAlias('axf95n')) {
      try {
        new ALT_CLS_ArchiveReadService()
          .read(readInput(holder.Id, null, null, 50));
        Assert.fail('sem capacidade');
      } catch (ALT_CLS_ArchiveReadService.ArchiveReadException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
    Assert.areEqual(
      hotBefore,
      [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c],
      'leitura nunca reidrata'
    );
  }

  @IsTest
  static void policyGuardsAccessAndDirectWritesAreRefused() {
    fakeStore();
    Account holder;
    System.runAs(byAlias('axf95g')) {
      holder = fixture('e').holder;
      ALT_CLS_ArchiveRunService service = new ALT_CLS_ArchiveRunService();
      policy(24, 2, false);
      try {
        service.start(holder.Id, 'BAT');
        Assert.fail('politica desabilitada');
      } catch (ALT_CLS_ArchiveRunService.ArchiveRunException expected) {
        Assert.areEqual('POLICY_DISABLED', expected.code);
      }
      policy(0, 2, true);
      try {
        service.start(holder.Id, 'BAT');
        Assert.fail('politica invalida');
      } catch (ALT_CLS_ArchiveRunService.ArchiveRunException expected) {
        Assert.areEqual('POLICY_INVALID', expected.code);
      }
      ALT_CLS_ArchivePolicy.policyOverride = null;
      ALT_CLS_ArchivePolicy.todayOverride = TODAY;
      // The shipped Default record resolves without code changes (24 months in DEV).
      ALT_CLS_ArchivePolicy.Resolved shipped = ALT_CLS_ArchivePolicy.resolve();
      Assert.isTrue(shipped.hotWindowMonths > 0);
      Assert.areEqual(
        TODAY.toStartOfMonth().addMonths(-shipped.hotWindowMonths),
        shipped.hotWindowStart
      );
      // Changing the configured window moves the boundary with no code change.
      policy(12, 2, true);
      Assert.areEqual(
        Date.newInstance(2025, 9, 1),
        ALT_CLS_ArchivePolicy.resolve().hotWindowStart
      );
      try {
        service.start(holder.Id, 'XYZ');
        Assert.fail('familia invalida');
      } catch (ALT_CLS_ArchiveRunService.ArchiveRunException expected) {
        Assert.areEqual('INVALID_INPUT', expected.code);
      }
      Assert.isFalse(
        Database.insert(
            new AXF_OBJ_ArchiveRun__c(
              AXF_ARR_EXI_RunKey__c = 'forged',
              AXF_ARR_PKL_SourceFamily__c = 'BAT',
              AXF_ARR_LKP_Account__c = holder.Id,
              AXF_ARR_TXT_PolicyVersion__c = 'x',
              AXF_ARR_DAT_HotWindowStart__c = HOT_START
            ),
            false
          )
          .isSuccess(),
        'checkpoint so nasce pelo servico'
      );
      ALT_CLS_ArchiveRunService.RunView run = service.start(holder.Id, 'FTX');
      drive(run.runId);
      AXF_OBJ_ArchiveRun__c row = ALT_CLS_ArchiveRunService.read(run.runId);
      row.AXF_ARR_PKL_Phase__c = 'COMPLETED';
      Assert.isFalse(
        Database.update(row, false).isSuccess(),
        'fase so pelo servico'
      );
      Assert.isFalse(Database.delete(row, false).isSuccess(), 'sem delete');
    }
    // Shared (partial) access is not enough to archive a holder's history.
    insert new AccountShare(
      AccountId = holder.Id,
      UserOrGroupId = byAlias('axf95p').Id,
      AccountAccessLevel = 'Edit',
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None'
    );
    System.runAs(byAlias('axf95p')) {
      policy(24, 2, true);
      try {
        new ALT_CLS_ArchiveRunService().start(holder.Id, 'BAT');
        Assert.fail('acesso parcial');
      } catch (ALT_CLS_ArchiveRunService.ArchiveRunException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
    System.runAs(byAlias('axf95n')) {
      policy(24, 2, true);
      try {
        new ALT_CLS_ArchiveRunService().start(holder.Id, 'BAT');
        Assert.fail('sem capacidade');
      } catch (ALT_CLS_ArchiveRunService.ArchiveRunException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
      try {
        new ALT_CLS_ArchiveRunService().listRuns(holder.Id);
        Assert.fail('sem capacidade');
      } catch (ALT_CLS_ArchiveRunService.ArchiveRunException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
  }

  @IsTest
  static void controllerSanitizesAndDelegates() {
    ALT_CLS_ArchiveTestStore store = fakeStore();
    // The single real Batch Apex execution of the suite (one executeBatch per test method).
    ALT_CLS_ArchiveRunService.enqueueBatches = true;
    policy(24, 200, true);
    System.runAs(byAlias('axf95g')) {
      Fixture f = fixture('g');
      AXF_CLS_CTRL_ArchiveExplorer.Context context = AXF_CLS_CTRL_ArchiveExplorer.getContext(
        ''
      );
      Assert.isTrue(context.canRead);
      Assert.isTrue(context.canArchive);
      Assert.areEqual(HOT_START, context.hotWindowStart);
      Assert.isFalse(context.holders.isEmpty());
      try {
        AXF_CLS_CTRL_ArchiveExplorer.read('{"nope":1}');
        Assert.fail('JSON invalido');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_ArchiveExplorer.startArchive(f.holder.Id, 'NOPE');
        Assert.fail('familia invalida');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      Test.startTest();
      ALT_CLS_ArchiveRunService.RunView run = AXF_CLS_CTRL_ArchiveExplorer.startArchive(
        f.holder.Id,
        'CCT'
      );
      Test.stopTest();
      Assert.isNotNull(run.runId);
      Assert.areEqual(
        'HOT_RETAINED',
        AXF_CLS_CTRL_ArchiveExplorer.listRuns(f.holder.Id)[0].phase
      );
      ALT_CLS_ArchiveReadService.ReadResult page = AXF_CLS_CTRL_ArchiveExplorer.read(
        JSON.serialize(readInput(f.holder.Id, null, null, 10))
      );
      Assert.areEqual(1, page.rows.size());
      Assert.areEqual('CCT', page.rows[0].family);
      Assert.areEqual(1, store.rows.size());
    }
    System.runAs(byAlias('axf95n')) {
      AXF_CLS_CTRL_ArchiveExplorer.Context context = AXF_CLS_CTRL_ArchiveExplorer.getContext(
        ''
      );
      Assert.isFalse(context.canRead);
      Assert.isTrue(context.holders.isEmpty(), 'sem capacidade nada e listado');
      try {
        AXF_CLS_CTRL_ArchiveExplorer.read(
          JSON.serialize(readInput(byAlias('axf95n').Id, null, null, 10))
        );
        Assert.fail('sanitizado');
      } catch (AuraHandledException expected) {
        Assert.areEqual('FORBIDDEN', expected.getMessage());
      }
    }
  }

  @IsTest
  static void liveStoreQueriesAreIndexBoundedAndEmptyWritesAreNoOps() {
    // The real store against the Big Object: every read is filtered by the index and capped;
    // an empty write issues no immediate DML (a non-empty one would persist past the test).
    ALT_CLS_ArchiveStore.storeOverride = null;
    ALT_CLS_ArchiveStore.Store live = ALT_CLS_ArchiveStore.instance();
    String key = '001TEST0000000AXF';
    Datetime day = ALT_CLS_ArchiveStore.bookingKey(
      Date.newInstance(2023, 3, 15)
    );
    Assert.areEqual(
      Date.newInstance(2023, 3, 15),
      ALT_CLS_ArchiveStore.bookingDay(day)
    );
    Assert.areEqual(0, day.hourGmt(), 'meia-noite UTC, sem deslocamento');
    live.write(new List<AXF_OBJ_TransactionArchive__b>());
    Assert.isTrue(live.sameDay(key, day, '', 5000).isEmpty());
    Assert.isTrue(live.before(key, day, day.addDays(-30), 0).isEmpty());
    Assert.isTrue(live.range(key, day.addDays(-30), day, null).isEmpty());
    Assert.areEqual(
      ALT_CLS_ArchiveStore.sha256('a'),
      ALT_CLS_ArchiveStore.sha256('a'),
      'hash deterministico'
    );
    Assert.areNotEqual(
      ALT_CLS_ArchiveRunService.archiveKey('BAT', 'x'),
      ALT_CLS_ArchiveRunService.archiveKey('CCT', 'x'),
      'familia faz parte da identidade'
    );
  }
}
