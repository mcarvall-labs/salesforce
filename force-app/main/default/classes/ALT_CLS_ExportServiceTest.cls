/**
 * @description AXF-118: autorizacao revalidada na solicitacao e de novo no download privado de
 * curta duracao; **toda** recusa sobre um artefato vivo o revoga (expirado, capability retirada,
 * solicitante perdido, acesso ao titular perdido, artefato ausente ou divergente) e por isso e
 * devolvida como outcome, nunca lancada — uma excecao nao tratada desfaria a revogacao; nome de
 * arquivo, notificacao e logs sem PII; replay idempotente por escopo e autor com pre-condicao de
 * versao (NFR-18); acesso negado e erros sanitizados. Catches name the service exception on
 * purpose: Assert.fail raises AssertException, which a generic catch would swallow and turn into
 * a false pass.
 */
@IsTest
private class ALT_CLS_ExportServiceTest {
  private static final String HOLDER_NAME = 'Holder Axon Export';
  private static final String IN_SCOPE_TEXT = 'Padaria do Ze 55221';
  private static final String OUT_OF_SCOPE_TEXT = 'Farmacia Alheia 99887';
  private static final String QUOTED_HOLDER_NAME = 'Holder Citacoes Export';
  private static final String QUOTED_TEXT = 'Cafe "especial" 30';
  private static final String QUOTED_FORMULA_TEXT = '=SUM("1","2")';
  private static final String FOREIGN_HOLDER_NAME = 'Holder Fora do Escopo';
  private static final String SHARED_HOLDER_NAME = 'Holder Compartilhado Export';

  private static User requester() {
    return [SELECT Id FROM User WHERE Alias = 'axf118r' LIMIT 1];
  }

  private static User peer() {
    return [SELECT Id FROM User WHERE Alias = 'axf118p' LIMIT 1];
  }

  private static User nobody() {
    return [SELECT Id FROM User WHERE Alias = 'axf118n' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User requester = new User(
      Alias = 'axf118r',
      Email = 'axf118r@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Export Requester',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf118r.' + System.now().getTime() + '@example.invalid'
    );
    User peer = requester.clone(false, false, false, false);
    peer.Alias = 'axf118p';
    peer.LastName = 'Export Peer';
    peer.Username = 'axf118p.' + System.now().getTime() + '@example.invalid';
    User nobody = requester.clone(false, false, false, false);
    nobody.Alias = 'axf118n';
    nobody.LastName = 'Export No Capability';
    nobody.Username = 'axf118n.' + System.now().getTime() + '@example.invalid';
    insert new List<User>{ requester, peer, nobody };
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN ('AXF_PS_GestorFinanceiro', 'AXF_PS_FinancialEntry')
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = requester.Id,
          PermissionSetId = permission.Id
        )
      );
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = peer.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    insert assignments;
    // The requester's own scope, with one in-scope fact carrying a spreadsheet formula prefix,
    // and a second scope whose descriptions carry quote characters.
    System.runAs(requester) {
      Account holder = holder(HOLDER_NAME);
      fact(holder.Id, 'axf118-a', IN_SCOPE_TEXT, Date.newInstance(2026, 3, 10));
      fact(
        holder.Id,
        'axf118-b',
        '=SUM(1,2) formula livre',
        Date.newInstance(2026, 3, 11)
      );
      Account quoted = holder(QUOTED_HOLDER_NAME);
      fact(quoted.Id, 'axf118-q1', QUOTED_TEXT, Date.newInstance(2026, 3, 14));
      fact(
        quoted.Id,
        'axf118-q2',
        QUOTED_FORMULA_TEXT,
        Date.newInstance(2026, 3, 15)
      );
    }
    // A scope the requester is not authorized for: owned by the peer, Private OWD, no role rule.
    // A second scope the peer owns, shared read-only with the requester by the test that needs it:
    // there the requester is not the holder's owner, so the run follows the peer (G2) and the share
    // the service writes is what keeps the run reachable. That `AccountShare` insert happens in the
    // test method, because share DML cannot share a transaction with the permission-set DML above
    // (MIXED_DML_OPERATION).
    System.runAs(peer) {
      Account foreign = holder(FOREIGN_HOLDER_NAME);
      fact(
        foreign.Id,
        'axf118-c',
        OUT_OF_SCOPE_TEXT,
        Date.newInstance(2026, 3, 12)
      );
      Account shared = holder(SHARED_HOLDER_NAME);
      fact(
        shared.Id,
        'axf118-d',
        'Padaria compartilhada 55221',
        Date.newInstance(2026, 3, 13)
      );
    }
  }

  private static Account holder(String name) {
    Account holder = new Account(
      Name = name,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert holder;
    return holder;
  }

  private static void fact(
    Id accountId,
    String key,
    String description,
    Date bookedOn
  ) {
    insert new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = accountId,
      AXF_FTX_NUM_Magnitude__c = 120.55,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = bookedOn,
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_TXT_Description__c = description,
      AXF_FTX_EXI_ClientRequestId__c = key
    );
  }

  private static Id holderId(String name) {
    return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
  }

  private static Id authorizedHolderId() {
    return holderId(HOLDER_NAME);
  }

  private static Id quotedHolderId() {
    return holderId(QUOTED_HOLDER_NAME);
  }

  private static Id foreignHolderId() {
    return holderId(FOREIGN_HOLDER_NAME);
  }

  private static Id sharedHolderId() {
    return holderId(SHARED_HOLDER_NAME);
  }

  /**
   * Re-points the run at another scope, which is what a withdrawn scope looks like. Runs in
   * system mode because the point of the fixture is a scope the requester cannot reference.
   */
  private static void moveScopeTo(Id runId, Id accountId) {
    Database.update(
      new AXF_OBJ_ExportRun__c(Id = runId, AXF_EPR_LKP_Account__c = accountId),
      AccessLevel.SYSTEM_MODE
    );
  }

  private static void expire(Id runId) {
    Database.update(
      new AXF_OBJ_ExportRun__c(
        Id = runId,
        AXF_EPR_DT_ExpiresAt__c = Datetime.now().addMinutes(-1)
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  private static AXF_OBJ_ExportRun__c storedRun(Id runId) {
    return [
      SELECT
        Name,
        OwnerId,
        AXF_EPR_PKL_Status__c,
        AXF_EPR_TXT_Reason__c,
        AXF_EPR_TXT_ContentDocument__c,
        AXF_EPR_TXT_FileName__c,
        AXF_EPR_TXT_ContentHash__c,
        AXF_EPR_DT_ExpiresAt__c,
        AXF_EPR_NUM_Version__c
      FROM AXF_OBJ_ExportRun__c
      WHERE Id = :runId
    ];
  }

  private static Id findRun(Id requesterId) {
    return [
      SELECT Id
      FROM AXF_OBJ_ExportRun__c
      WHERE AXF_EPR_LKP_Requester__c = :requesterId
      LIMIT 1
    ]
    .Id;
  }

  /** The version a caller observes before it mutates, which is what the precondition expects. */
  private static Decimal observedVersion(
    ALT_CLS_ExportService service,
    Id runId
  ) {
    return service.read(runId).version;
  }

  /**
   * Stages a prepared run with its artifact. Only the withdrawn-capability test needs it: that
   * state is a run whose requester holds no capability, and reaching it by assigning and then
   * withdrawing the permission set inside one test is impossible, because the withdrawal is DML on
   * a setup object and cannot share a transaction with the record DML the service performs
   * (MIXED_DML_OPERATION). The state is therefore staged and the test starts from it.
   */
  private static Id stagedRun(Id accountId, Id requesterId, String csv) {
    insert new ContentVersion(
      Title = 'axon-export-staged.csv',
      PathOnClient = 'axon-export-staged.csv',
      VersionData = Blob.valueOf(csv)
    );
    AXF_OBJ_ExportRun__c run = new AXF_OBJ_ExportRun__c(
      AXF_EPR_LKP_Account__c = accountId,
      AXF_EPR_LKP_Requester__c = requesterId,
      AXF_EPR_EXI_ScopeKey__c = 'axf118-staged-capability',
      AXF_EPR_PKL_Status__c = 'PREPARED',
      AXF_EPR_NUM_Version__c = 1,
      AXF_EPR_TXT_FileName__c = 'axon-export-staged.csv',
      AXF_EPR_TXT_ContentHash__c = sha256(csv),
      AXF_EPR_TXT_ContentDocument__c = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Title = 'axon-export-staged.csv'
        LIMIT 1
      ]
      .ContentDocumentId,
      AXF_EPR_DT_ExpiresAt__c = Datetime.now().addMinutes(15)
    );
    insert run;
    return run.Id;
  }

  private static String sha256(String value) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(value))
    );
  }

  // ---------------------------------------------------------------- AC-1

  @IsTest
  static void authorizedRequestPreparesAndDownloadRevalidates() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      Test.startTest();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      Test.stopTest();

      Assert.areEqual('PREPARED', run.status);
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_ExportRun__c]);
      Assert.isNotNull(run.fileName, 'Nome preparado.');
      Assert.isNotNull(run.contentHash);
      Assert.isNotNull(run.evidenceRef, 'Artefato legivel como evidencia.');
      Assert.isNotNull(run.expiresAt, 'Janela curta declarada.');
      Assert.isTrue(run.canDownload);
      Assert.areEqual('DOWNLOAD', run.nextAction);
      // The service creates no ContentDocumentLink, and the artifact has no public
      // distribution. The single remaining link is the platform's own ownership marker
      // (ShareType I) for the user who prepared it, which is what Files always adds: the
      // artifact is therefore reachable outside the service only by that same authorized
      // requester, and that residual is declared in docs/implementation/AXF-118.md — the
      // service does not claim to defeat it.
      List<ContentDocumentLink> links = [
        SELECT LinkedEntityId, ShareType
        FROM ContentDocumentLink
        WHERE ContentDocumentId = :run.evidenceRef
      ];
      Assert.isFalse(links.isEmpty(), 'O artefato existe como documento.');
      for (ContentDocumentLink link : links) {
        Assert.areEqual(
          'I',
          link.ShareType,
          'Somente o vinculo de posse criado pela plataforma.'
        );
        Assert.areEqual(
          UserInfo.getUserId(),
          link.LinkedEntityId,
          'O artefato pertence a quem o preparou.'
        );
      }
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM ContentDistribution
          WHERE ContentDocumentId = :run.evidenceRef
        ],
        'Nenhum link publico de distribuicao.'
      );

      ALT_CLS_ExportService.DownloadView download = service.download(
        run.runId,
        run.version
      );
      Assert.isTrue(download.ready, download.outcome);
      Assert.areEqual('READY', download.outcome);
      Assert.areEqual(run.fileName, download.fileName);
      Assert.areEqual(run.contentHash, download.contentHash);
      String csv = EncodingUtil.base64Decode(download.bodyBase64).toString();
      Assert.isTrue(
        csv.startsWith('date,direction,amount,currency,status,description'),
        'Cabecalho estavel.'
      );
      Assert.isTrue(csv.contains(IN_SCOPE_TEXT), 'Somente o escopo pedido.');
      Assert.isFalse(
        csv.contains(OUT_OF_SCOPE_TEXT),
        'Nenhum dado fora do escopo solicitado.'
      );
      Assert.areEqual(
        3,
        csv.split('\n').size(),
        'Cabecalho mais uma linha por fato do titular.'
      );
      Assert.areEqual('DOWNLOADED', service.read(run.runId).status);

      // A second download inside the window revalidates again and serves the same artifact.
      ALT_CLS_ExportService.DownloadView again = service.download(
        run.runId,
        observedVersion(service, run.runId)
      );
      Assert.isTrue(again.ready, again.outcome);
      Assert.areEqual(download.contentHash, again.contentHash);
    }
  }

  @IsTest
  static void exportedCellsAreQuotedAndFormulaPrefixedValuesAreInert() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      String csv = EncodingUtil.base64Decode(
          service.download(run.runId, run.version).bodyBase64
        )
        .toString();
      Assert.isTrue(
        csv.contains('"\'=SUM(1,2) formula livre"'),
        'AD-25: o mesmo neutralizador da importacao desarma o prefixo de formula.'
      );
      Assert.isFalse(csv.contains('\n"='), 'Nenhuma celula comeca ativa.');
      Assert.isTrue(
        csv.contains('"2026-03-10","DEBIT","120.55","BRL","PLANNED"'),
        'Toda celula e citada, na ordem declarada.'
      );
    }
  }

  /**
   * CSV quote escaping: no older fixture carried an embedded quote, so dropping the doubling
   * would have left the suite green. The value is doubled inside an already-quoted cell, which is
   * the only thing that keeps a description containing `"` from breaking the row.
   */
  @IsTest
  static void cellsCarryingQuotesAreEscapedSoTheCsvStaysParsable() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        quotedHolderId(),
        null
      );
      String csv = EncodingUtil.base64Decode(
          service.download(run.runId, run.version).bodyBase64
        )
        .toString();
      Assert.isTrue(csv.contains('"Cafe ""especial"" 30"'), csv);
      Assert.isFalse(
        csv.contains('"Cafe "especial" 30"'),
        'Aspas internas soltas quebrariam a linha.'
      );
      Assert.isTrue(
        csv.contains('"\'=SUM(""1"",""2"")"'),
        'Neutralizacao de formula e escape de aspas valem na mesma celula.'
      );
      Assert.areEqual(3, csv.split('\n').size(), 'Cabecalho mais dois fatos.');
    }
  }

  @IsTest
  static void replayWithinTheWindowReusesTheSameRunAndArtifact() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView first = service.request(
        authorizedHolderId(),
        null
      );
      ALT_CLS_ExportService.RunView second = service.request(
        authorizedHolderId(),
        first.version
      );
      Assert.areEqual(
        first.runId,
        second.runId,
        'Mesmo escopo e autor = mesmo run.'
      );
      Assert.areEqual(first.evidenceRef, second.evidenceRef);
      Assert.areEqual(first.contentHash, second.contentHash);
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_ExportRun__c]);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM ContentDocument],
        'O replay nao cria um segundo artefato.'
      );
    }
  }

  @IsTest
  static void anotherAuthorizedOperatorCannotDownloadAndTheAttemptRevokesTheArtifact() {
    Id runId;
    Decimal version;
    System.runAs(requester()) {
      ALT_CLS_ExportService.RunView run = new ALT_CLS_ExportService()
        .request(authorizedHolderId(), null);
      runId = run.runId;
      version = run.version;
    }
    // The peer holds the same capability and can see the run through a share, but is not the
    // requester the artifact is bound to.
    Database.insert(
      new AXF_OBJ_ExportRun__Share(
        ParentId = runId,
        UserOrGroupId = peer().Id,
        AccessLevel = 'Read',
        RowCause = Schema.AXF_OBJ_ExportRun__Share.RowCause.Manual
      )
    );
    System.runAs(peer()) {
      Assert.areEqual(runId, findRun(requester().Id), 'O peer ve o run.');
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      Test.startTest();
      ALT_CLS_ExportService.DownloadView refused = service.download(
        runId,
        version
      );
      Test.stopTest();
      // Returned, not thrown: the refusal must record its revocation and commit it (AC-2).
      Assert.isFalse(refused.ready);
      Assert.areEqual('FORBIDDEN', refused.outcome);
      Assert.isNull(
        refused.bodyBase64,
        'Outro operador nao recebe o artefato.'
      );
      Assert.isFalse(service.read(runId).canDownload, 'Nao e o solicitante.');
    }
    AXF_OBJ_ExportRun__c stored = storedRun(runId);
    Assert.areEqual(
      'REVOKED',
      stored.AXF_EPR_PKL_Status__c,
      'O acesso nao autorizado revoga o artefato (AC-2).'
    );
    Assert.areEqual('ACCESS_REVOKED', stored.AXF_EPR_TXT_Reason__c);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ContentDocument],
      'O artefato privado nao sobrevive a recusa.'
    );
    // The artifact is gone for the requester too: a fresh request is what mints another one.
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      Assert.areEqual(
        'REVOKED',
        service.download(runId, observedVersion(service, runId)).outcome
      );
      ALT_CLS_ExportService.RunView again = service.request(
        authorizedHolderId(),
        observedVersion(service, runId)
      );
      Assert.areEqual(runId, again.runId, 'O mesmo escopo reusa o run.');
      Assert.areEqual('PREPARED', again.status);
      Assert.isTrue(service.download(runId, again.version).ready);
    }
  }

  /**
   * The capability is withdrawn while the artifact is live. The refusal used to throw before
   * touching the run, so the artifact survived indefinitely; now the refusal has to reach the row
   * — which the caller can no longer even read — and revoke before refusing. The requester binding
   * is intact, so the capability is provably the gate that refused.
   */
  @IsTest
  static void aWithdrawnCapabilityRevokesTheArtifactBeforeItRefuses() {
    Id runId = stagedRun(
      authorizedHolderId(),
      nobody().Id,
      'date,direction\n2026-03-10,DEBIT'
    );
    System.runAs(nobody()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      Test.startTest();
      ALT_CLS_ExportService.DownloadView refused = service.download(runId, 1);
      Test.stopTest();
      Assert.isFalse(refused.ready);
      Assert.areEqual(
        'FORBIDDEN',
        refused.outcome,
        'Sem AXF_CanExportData o download e recusado.'
      );
      Assert.isNull(refused.bodyBase64, 'Nada e servido sem a capability.');
    }
    AXF_OBJ_ExportRun__c stored = storedRun(runId);
    Assert.areEqual(
      'REVOKED',
      stored.AXF_EPR_PKL_Status__c,
      'A capability retirada revoga o artefato (AC-2).'
    );
    Assert.areEqual('ACCESS_REVOKED', stored.AXF_EPR_TXT_Reason__c);
    Assert.isNull(stored.AXF_EPR_TXT_ContentDocument__c);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ContentDocument],
      'O artefato privado nao sobrevive a recusa.'
    );
  }

  @IsTest
  static void requestWithoutTheCapabilityIsForbidden() {
    // Resolved outside runAs: the user under test cannot see the scope at all, and the
    // capability check must be what refuses the request.
    Id accountId = authorizedHolderId();
    System.runAs(nobody()) {
      try {
        new ALT_CLS_ExportService().request(accountId, null);
        Assert.fail('Sem AXF_CanExportData nao ha exportacao.');
      } catch (ALT_CLS_ExportService.ExportException denied) {
        Assert.areEqual('FORBIDDEN', denied.code);
      }
    }
  }

  @IsTest
  static void requestOnAScopeTheRequesterCannotReachIsNotAccessible() {
    // Resolved outside runAs: the requester cannot see this scope, which is the point.
    Id foreignId = foreignHolderId();
    System.runAs(requester()) {
      try {
        new ALT_CLS_ExportService().request(foreignId, null);
        Assert.fail(
          'Escopo fora da autorizacao nao existe para o solicitante.'
        );
      } catch (ALT_CLS_ExportService.ExportException denied) {
        Assert.areEqual('NOT_ACCESSIBLE', denied.code);
      }
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ExportRun__c]);
    }
  }

  @IsTest
  static void invalidInputIsRejected() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      try {
        service.request(null, null);
        Assert.fail('Escopo obrigatorio.');
      } catch (ALT_CLS_ExportService.ExportException invalid) {
        Assert.areEqual('INVALID_INPUT', invalid.code);
      }
      try {
        service.download(null, null);
        Assert.fail('Run obrigatorio.');
      } catch (ALT_CLS_ExportService.ExportException invalid) {
        Assert.areEqual('INVALID_INPUT', invalid.code);
      }
      try {
        service.read(null);
        Assert.fail('Run obrigatorio.');
      } catch (ALT_CLS_ExportService.ExportException invalid) {
        Assert.areEqual('INVALID_INPUT', invalid.code);
      }
    }
  }

  @IsTest
  static void exportBeyondTheDeclaredRowLimitBlocksInsteadOfTruncating() {
    System.runAs(requester()) {
      Id accountId = authorizedHolderId();
      Integer missing =
        ALT_CLS_ExportService.EXPORT_ROW_LIMIT -
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE AXF_FTX_LKP_Account__c = :accountId
        ] +
        1;
      List<AXF_OBJ_FinancialTransaction__c> facts = new List<AXF_OBJ_FinancialTransaction__c>();
      for (Integer i = 0; i < missing; i++) {
        facts.add(
          new AXF_OBJ_FinancialTransaction__c(
            AXF_FTX_LKP_Account__c = accountId,
            AXF_FTX_NUM_Magnitude__c = 1,
            AXF_FTX_PKL_Direction__c = 'DEBIT',
            AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_FTX_DAT_PurchaseDate__c = Date.newInstance(2026, 1, 1),
            AXF_FTX_PKL_Status__c = 'PLANNED',
            AXF_FTX_NUM_Version__c = 0,
            AXF_FTX_EXI_ClientRequestId__c = 'axf118-limit-' + i
          )
        );
      }
      insert facts;
      Test.startTest();
      try {
        new ALT_CLS_ExportService().request(accountId, null);
        Assert.fail(
          'Acima do limite o pedido bloqueia em vez de descartar linhas.'
        );
      } catch (ALT_CLS_ExportService.ExportException blocked) {
        Assert.areEqual('EXPORT_TOO_LARGE', blocked.code);
      }
      Test.stopTest();
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM ContentDocument],
        'Nada e gravado quando o pedido bloqueia.'
      );
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ExportRun__c]);
    }
  }

  /**
   * Boundary equality on the declared limit: exactly `EXPORT_ROW_LIMIT` rows still prepare, so the
   * block is a limit and not an off-by-one that refuses a full export. Bound to the constant, not
   * to a literal, so raising the limit moves the test with it.
   */
  @IsTest
  static void exportAtTheDeclaredRowLimitStillPrepares() {
    System.runAs(requester()) {
      Id accountId = authorizedHolderId();
      List<AXF_OBJ_FinancialTransaction__c> toTheLimit = bulkFacts(
        accountId,
        'axf118-at-limit-',
        ALT_CLS_ExportService.EXPORT_ROW_LIMIT - factCount(accountId)
      );
      insert toTheLimit;

      Test.startTest();
      ALT_CLS_ExportService.RunView run = new ALT_CLS_ExportService()
        .request(accountId, null);
      Test.stopTest();

      Assert.areEqual(
        ALT_CLS_ExportService.EXPORT_ROW_LIMIT,
        factCount(accountId),
        'O fixture alcanca o limite exato.'
      );
      Assert.areEqual('PREPARED', run.status);
      Assert.isTrue(run.canDownload, 'No limite exato a exportacao ainda e preparada.');
      Assert.isNotNull(run.contentHash);
      Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument]);
    }
  }

  /**
   * A refusal that cannot build the replacement must not roll the revocation back with it: the
   * expired artifact stays deleted and the run stays REVOKED, which is what AC-2 asks for. The
   * savepoint mint() takes sits after the revocation for exactly this case.
   */
  @IsTest
  static void anExpiredRunStaysRevokedWhenTheReplacementIsTooLarge() {
    System.runAs(requester()) {
      Id accountId = authorizedHolderId();
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(accountId, null);
      expire(run.runId);
      List<AXF_OBJ_FinancialTransaction__c> overTheLimit = bulkFacts(
        accountId,
        'axf118-over-limit-',
        ALT_CLS_ExportService.EXPORT_ROW_LIMIT + 1 - factCount(accountId)
      );
      insert overTheLimit;

      Test.startTest();
      try {
        service.request(accountId, observedVersion(service, run.runId));
        Assert.fail('Acima do limite o pedido bloqueia.');
      } catch (ALT_CLS_ExportService.ExportException blocked) {
        Assert.areEqual('EXPORT_TOO_LARGE', blocked.code);
      }
      Test.stopTest();

      AXF_OBJ_ExportRun__c stored = storedRun(run.runId);
      Assert.areEqual(
        'REVOKED',
        stored.AXF_EPR_PKL_Status__c,
        'A recusa do substituto nao pode desfazer a revogacao do artefato vencido.'
      );
      Assert.areEqual('EXPIRED', stored.AXF_EPR_TXT_Reason__c);
      Assert.isNull(stored.AXF_EPR_TXT_ContentDocument__c);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM ContentDocument],
        'O artefato vencido continua excluido depois da recusa.'
      );
    }
  }

  /**
   * The read-only control plane the story claims is pinned here instead of only re-read by hand
   * after a deploy: the house grant carries no write, no create and no delete, every control field
   * is read-only, and the very operator the capability authorizes cannot rewrite the state that
   * decides its own authorization.
   */
  @IsTest
  static void theControlPlaneIsReadOnlyForTheAuthorizedOperator() {
    Id runId;
    System.runAs(requester()) {
      runId = new ALT_CLS_ExportService().request(authorizedHolderId(), null).runId;
    }

    List<ObjectPermissions> grants = [
      SELECT
        PermissionsRead,
        PermissionsCreate,
        PermissionsEdit,
        PermissionsDelete
      FROM ObjectPermissions
      WHERE
        Parent.Name = 'AXF_PS_GestorFinanceiro'
        AND SobjectType = 'AXF_OBJ_ExportRun__c'
    ];
    Assert.areEqual(1, grants.size(), 'A permissao da casa governa o objeto.');
    Assert.isTrue(grants[0].PermissionsRead);
    Assert.isFalse(
      grants[0].PermissionsCreate,
      'Criar run e do servico, que grava em system mode.'
    );
    Assert.isFalse(
      grants[0].PermissionsEdit,
      'O titular nao edita o controle que o autoriza.'
    );
    Assert.isFalse(grants[0].PermissionsDelete);

    List<FieldPermissions> fields = [
      SELECT Field, PermissionsRead, PermissionsEdit
      FROM FieldPermissions
      WHERE
        Parent.Name = 'AXF_PS_GestorFinanceiro'
        AND SobjectType = 'AXF_OBJ_ExportRun__c'
    ];
    Assert.areEqual(
      7,
      fields.size(),
      'Os sete campos de controle estao no permission set.'
    );
    for (FieldPermissions field : fields) {
      Assert.isTrue(field.PermissionsRead, field.Field);
      Assert.isFalse(field.PermissionsEdit, field.Field);
    }

    // Behavioural half: the declarative grant is not the only thing standing between the operator
    // and the control row, so the refusal is proved by DML rather than inferred from the metadata.
    System.runAs(requester()) {
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_ExportRun__c(
              Id = runId,
              AXF_EPR_TXT_Reason__c = 'FORGED'
            ),
            false
          )
          .isSuccess(),
        'Um operador autorizado nao reescreve o controle.'
      );
    }
    Assert.isNull(
      storedRun(runId).AXF_EPR_TXT_Reason__c,
      'Nenhuma transicao forjada foi aceita.'
    );
  }

  private static Integer factCount(Id accountId) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Account__c = :accountId
    ];
  }

  private static List<AXF_OBJ_FinancialTransaction__c> bulkFacts(
    Id accountId,
    String prefix,
    Integer count
  ) {
    List<AXF_OBJ_FinancialTransaction__c> facts = new List<AXF_OBJ_FinancialTransaction__c>();
    for (Integer i = 0; i < count; i++) {
      facts.add(
        new AXF_OBJ_FinancialTransaction__c(
          AXF_FTX_LKP_Account__c = accountId,
          AXF_FTX_NUM_Magnitude__c = 1,
          AXF_FTX_PKL_Direction__c = 'DEBIT',
          AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
          AXF_FTX_DAT_PurchaseDate__c = Date.newInstance(2026, 1, 1),
          AXF_FTX_PKL_Status__c = 'PLANNED',
          AXF_FTX_NUM_Version__c = 0,
          AXF_FTX_EXI_ClientRequestId__c = prefix + i
        )
      );
    }
    return facts;
  }

  /**
   * NFR-18 following the merged closure orchestrator: the version is a precondition, not a
   * decoration. A caller acting on a version it did not observe is refused with a safe code and
   * nothing is touched.
   */
  @IsTest
  static void aStaleOrUnstatedExpectedVersionIsRefusedWithASafeCode() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      Assert.areEqual(
        run.version,
        observedVersion(service, run.runId),
        'A versao devolvida e a versao gravada.'
      );

      try {
        service.download(run.runId, run.version - 1);
        Assert.fail('Versao obsoleta deve conflitar.');
      } catch (ALT_CLS_ExportService.ExportException stale) {
        Assert.areEqual('CONFLICT', stale.code);
      }
      try {
        service.download(run.runId, null);
        Assert.fail('A versao observada e obrigatoria no download.');
      } catch (ALT_CLS_ExportService.ExportException missing) {
        Assert.areEqual('INVALID_INPUT', missing.code);
      }
      // A stale expectation must not damage the live artifact.
      Assert.areEqual('PREPARED', storedRun(run.runId).AXF_EPR_PKL_Status__c);
      Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument]);

      // The current version still downloads, and the transition advances the version.
      Assert.isTrue(service.download(run.runId, run.version).ready);
      Assert.areEqual(run.version + 1, observedVersion(service, run.runId));

      try {
        service.request(authorizedHolderId(), run.version);
        Assert.fail('Versao obsoleta deve conflitar no pedido.');
      } catch (ALT_CLS_ExportService.ExportException stale) {
        Assert.areEqual('CONFLICT', stale.code);
      }
      try {
        service.request(authorizedHolderId(), null);
        Assert.fail('Um run existente exige a versao observada.');
      } catch (ALT_CLS_ExportService.ExportException missing) {
        Assert.areEqual('INVALID_INPUT', missing.code);
      }
      // A version stated for a scope that has no run is an impossible expectation.
      try {
        service.request(quotedHolderId(), 7);
        Assert.fail('Nao ha run para essa versao.');
      } catch (ALT_CLS_ExportService.ExportException conflict) {
        Assert.areEqual('CONFLICT', conflict.code);
      }
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_ExportRun__c]);
    }
  }

  // ---------------------------------------------------------------- AC-2

  @IsTest
  static void expiredDownloadIsRevokedAndTheArtifactIsDeleted() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      expire(run.runId);

      Test.startTest();
      ALT_CLS_ExportService.DownloadView refused = service.download(
        run.runId,
        run.version
      );
      Test.stopTest();

      Assert.isFalse(refused.ready);
      Assert.areEqual('EXPIRED', refused.outcome);
      Assert.isNull(refused.bodyBase64, 'Conteudo vencido nunca e servido.');
      AXF_OBJ_ExportRun__c stored = storedRun(run.runId);
      Assert.areEqual('REVOKED', stored.AXF_EPR_PKL_Status__c);
      Assert.areEqual('EXPIRED', stored.AXF_EPR_TXT_Reason__c);
      Assert.isNull(stored.AXF_EPR_TXT_ContentDocument__c);
      Assert.isNull(stored.AXF_EPR_TXT_FileName__c);
      Assert.isNull(stored.AXF_EPR_TXT_ContentHash__c);
      Assert.isNull(stored.AXF_EPR_DT_ExpiresAt__c);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM ContentDocument],
        'A revogacao exclui o artefato que a aplicacao controla.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :run.runId
        ],
        'Nenhum vinculo sobrevive a revogacao.'
      );
      ALT_CLS_ExportService.RunView observed = service.read(run.runId);
      Assert.isFalse(observed.canDownload);
      Assert.isNull(observed.evidenceRef);
      Assert.areEqual('REQUEST_AGAIN', observed.nextAction);
    }
  }

  /**
   * The concrete failure the audit proved: the run's removal cannot be undone by a rollback, so
   * a REVOKED state always exists — with the failure recorded as its reason, and the pointer kept
   * so a later attempt can still remove the copy that survived.
   */
  @IsTest
  static void revokedIsRecordedEvenWhenTheArtifactCannotBeRemoved() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      expire(run.runId);
      ALT_CLS_ExportService.artifactRemovalFails = true;
      Test.startTest();
      ALT_CLS_ExportService.DownloadView refused = service.download(
        run.runId,
        run.version
      );
      Test.stopTest();
      ALT_CLS_ExportService.artifactRemovalFails = false;

      Assert.isFalse(refused.ready);
      Assert.areEqual('ARTIFACT_NOT_REMOVED', refused.outcome);
      Assert.isNull(refused.bodyBase64);
      AXF_OBJ_ExportRun__c stored = storedRun(run.runId);
      Assert.areEqual(
        'REVOKED',
        stored.AXF_EPR_PKL_Status__c,
        'A transacao nao pode desfazer o estado: REVOKED sempre existe.'
      );
      Assert.areEqual('ARTIFACT_NOT_REMOVED', stored.AXF_EPR_TXT_Reason__c);
      Assert.isNotNull(
        stored.AXF_EPR_TXT_ContentDocument__c,
        'O ponteiro sobrevive para uma nova tentativa.'
      );
      Assert.isNull(stored.AXF_EPR_TXT_FileName__c);
      Assert.isNull(stored.AXF_EPR_TXT_ContentHash__c);
      Assert.isNull(stored.AXF_EPR_DT_ExpiresAt__c);
      Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument]);
      ALT_CLS_ExportService.RunView observed = service.read(run.runId);
      Assert.isFalse(
        observed.canDownload,
        'Um estado revogado nunca e baixavel.'
      );
      Assert.isNull(
        observed.evidenceRef,
        'Nada revogado e oferecido como evidencia.'
      );

      // The next attempt retries the removal instead of leaving the copy alive forever, and the run
      // stops claiming a survivor the moment that retry actually removed it: an outcome string
      // alone would also be satisfied by a retry that did nothing at all.
      ALT_CLS_ExportService.DownloadView retried = service.download(
        run.runId,
        observedVersion(service, run.runId)
      );
      Assert.isFalse(retried.ready);
      Assert.areEqual(
        'REVOKED',
        retried.outcome,
        'A copia saiu: o run nao pode continuar afirmando que sobreviveu.'
      );
      AXF_OBJ_ExportRun__c afterRetry = storedRun(run.runId);
      Assert.isNull(
        afterRetry.AXF_EPR_TXT_ContentDocument__c,
        'O ponteiro sumiu junto com a copia.'
      );
      Assert.areNotEqual(
        'ARTIFACT_NOT_REMOVED',
        afterRetry.AXF_EPR_TXT_Reason__c,
        'O motivo registrado segue a tentativa que de fato ocorreu.'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM ContentDocument],
        'A nova tentativa concluiu a remocao.'
      );
    }
  }

  /**
   * The request path retries the removal too, and must not resolve that retry by overwriting the
   * pointer: a second failure would then leave a surviving copy with no reference at all, which is
   * the state the recorded ARTIFACT_NOT_REMOVED exists to make visible to an operator.
   */
  @IsTest
  static void aSurvivingCopyKeepsItsPointerInsteadOfBeingOverwritten() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      expire(run.runId);
      ALT_CLS_ExportService.artifactRemovalFails = true;
      ALT_CLS_ExportService.DownloadView refused = service.download(
        run.runId,
        run.version
      );
      Assert.areEqual('ARTIFACT_NOT_REMOVED', refused.outcome);
      String survivingCopy = storedRun(run.runId)
        .AXF_EPR_TXT_ContentDocument__c;
      Assert.isNotNull(survivingCopy);
      Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument]);

      // A new request retries the removal and it fails again: the recorded reason, the pointer and
      // the surviving copy must all still be there, and no artifact may be minted over them.
      Test.startTest();
      ALT_CLS_ExportService.RunView again = service.request(
        authorizedHolderId(),
        observedVersion(service, run.runId)
      );
      Test.stopTest();
      ALT_CLS_ExportService.artifactRemovalFails = false;

      Assert.areEqual('REVOKED', again.status);
      Assert.areEqual('ARTIFACT_NOT_REMOVED', again.reason);
      Assert.isFalse(again.canDownload);
      Assert.areEqual('REQUEST_AGAIN', again.nextAction);
      Assert.isNull(
        again.evidenceRef,
        'Nada revogado e oferecido como evidencia.'
      );
      AXF_OBJ_ExportRun__c stored = storedRun(run.runId);
      Assert.areEqual('ARTIFACT_NOT_REMOVED', stored.AXF_EPR_TXT_Reason__c);
      Assert.areEqual(
        survivingCopy,
        stored.AXF_EPR_TXT_ContentDocument__c,
        'O ponteiro da copia sobrevivente nao pode ser sobrescrito.'
      );
      Assert.isNull(stored.AXF_EPR_TXT_FileName__c);
      Assert.isNull(stored.AXF_EPR_TXT_ContentHash__c);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM ContentDocument],
        'Nenhum segundo artefato foi criado sobre a copia que sobreviveu.'
      );
    }
  }

  @IsTest
  static void readNeverRevokesButDownloadEnforcesTheWindow() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      expire(run.runId);

      ALT_CLS_ExportService.RunView observed = service.read(run.runId);
      Assert.isFalse(observed.canDownload, 'Disponibilidade real e reportada.');
      Assert.areEqual(
        'PREPARED',
        observed.status,
        'Observar nao revoga: o acesso ao download e que revoga.'
      );

      Assert.areEqual(
        'EXPIRED',
        service.download(run.runId, observed.version).outcome
      );
      Assert.areEqual('REVOKED', service.read(run.runId).status);
    }
  }

  /**
   * Availability is not advertised for a scope whose authorization was withdrawn: the observed
   * run must not say DOWNLOAD when the download that follows would revoke instead of serving.
   */
  @IsTest
  static void withdrawnScopeAuthorizationIsNotAdvertisedAndRevokesTheDownload() {
    Id foreignId = foreignHolderId();
    Id runId;
    System.runAs(requester()) {
      runId = new ALT_CLS_ExportService()
        .request(authorizedHolderId(), null)
        .runId;
    }
    // The artifact now points at a scope the requester is not authorized for, which is what a
    // withdrawn share looks like from the service's point of view.
    moveScopeTo(runId, foreignId);

    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView observed = service.read(runId);
      Assert.isFalse(
        observed.canDownload,
        'Escopo sem autorizacao nunca e anunciado como baixavel.'
      );
      Assert.areEqual('REQUEST_AGAIN', observed.nextAction);
      Assert.areEqual(
        'PREPARED',
        observed.status,
        'Observar nao revoga: o acesso ao download e que revoga.'
      );

      Test.startTest();
      ALT_CLS_ExportService.DownloadView refused = service.download(
        runId,
        observed.version
      );
      Test.stopTest();

      Assert.isFalse(refused.ready);
      Assert.areEqual('ACCESS_REVOKED', refused.outcome);
      Assert.isNull(refused.bodyBase64);
      AXF_OBJ_ExportRun__c stored = storedRun(runId);
      Assert.areEqual('REVOKED', stored.AXF_EPR_PKL_Status__c);
      Assert.areEqual('ACCESS_REVOKED', stored.AXF_EPR_TXT_Reason__c);
      Assert.isNull(stored.AXF_EPR_TXT_ContentDocument__c);
    }
    Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument]);
  }

  @IsTest
  static void revokedRunRefusesDownloadAndANewRequestMintsAFreshArtifact() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      String deadArtifact = run.evidenceRef;
      expire(run.runId);
      Assert.areEqual(
        'EXPIRED',
        service.download(run.runId, run.version).outcome
      );
      Decimal afterRevoke = observedVersion(service, run.runId);
      Assert.areEqual(
        'REVOKED',
        service.download(run.runId, afterRevoke).outcome
      );

      ALT_CLS_ExportService.RunView again = service.request(
        authorizedHolderId(),
        afterRevoke
      );
      Assert.areEqual(run.runId, again.runId, 'O mesmo escopo reusa o run.');
      Assert.areEqual('PREPARED', again.status);
      Assert.isNull(
        again.reason,
        'O motivo antigo nao sobrevive ao novo artefato.'
      );
      Assert.isNotNull(again.evidenceRef);
      Assert.areNotEqual(deadArtifact, again.evidenceRef);
      Assert.isTrue(again.canDownload);
      Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument]);
      Assert.isTrue(service.download(run.runId, again.version).ready);
    }
  }

  @IsTest
  static void artifactThatDoesNotMatchItsEvidenceIsRevokedInsteadOfServed() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      Id documentId = [SELECT Id FROM ContentDocument LIMIT 1].Id;
      // A later version of the same document replaces the content that was hashed.
      insert new ContentVersion(
        ContentDocumentId = documentId,
        Title = run.fileName,
        PathOnClient = run.fileName,
        VersionData = Blob.valueOf('date,direction\n2019-01-01,CREDIT')
      );

      ALT_CLS_ExportService.DownloadView refused = service.download(
        run.runId,
        run.version
      );
      Assert.isFalse(refused.ready);
      Assert.areEqual('ARTIFACT_MISMATCH', refused.outcome);
      Assert.isNull(refused.bodyBase64);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM ContentDocument],
        'Um artefato nao conferido e descartado, nunca servido.'
      );
    }
  }

  @IsTest
  static void aMissingArtifactIsReportedInsteadOfServed() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      delete new ContentDocument(Id = run.evidenceRef);

      ALT_CLS_ExportService.DownloadView refused = service.download(
        run.runId,
        run.version
      );
      Assert.isFalse(refused.ready);
      Assert.areEqual('ARTIFACT_MISSING', refused.outcome);
      Assert.areEqual('REVOKED', storedRun(run.runId).AXF_EPR_PKL_Status__c);
    }
  }

  /**
   * Availability is a promise the service must be able to keep: a prepared run whose artifact is
   * gone reports REQUEST_AGAIN instead of DOWNLOAD, and the request that follows actually rebuilds
   * the artifact on the same run — otherwise the advertised next action would be a dead end.
   */
  @IsTest
  static void aRunWhoseArtifactVanishedIsRepreparedByTheNextRequest() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      String deadArtifact = run.evidenceRef;
      delete new ContentDocument(Id = deadArtifact);
      Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument]);

      ALT_CLS_ExportService.RunView observed = service.read(run.runId);
      Assert.isFalse(
        observed.canDownload,
        'Um run sem artefato nao pode ser anunciado como baixavel.'
      );
      Assert.areEqual('REQUEST_AGAIN', observed.nextAction);
      Assert.areEqual(
        'PREPARED',
        observed.status,
        'Observar nao revoga: o acesso ao download e que revoga.'
      );

      ALT_CLS_ExportService.RunView again = service.request(
        authorizedHolderId(),
        observed.version
      );
      Assert.areEqual('PREPARED', again.status);
      Assert.isTrue(
        again.canDownload,
        'O pedido repara o run em vez de devolver um beco sem saida.'
      );
      Assert.areEqual('DOWNLOAD', again.nextAction);
      Assert.isNotNull(again.evidenceRef);
      Assert.areNotEqual(
        deadArtifact,
        again.evidenceRef,
        'O artefato foi refeito, nao reaproveitado.'
      );
      Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument]);
      Assert.isTrue(
        service.download(run.runId, again.version).ready,
        'O artefato novo e o que o download entrega.'
      );
    }
  }

  /**
   * `read()` keeps respecting the caller's access even though the class elevates for its own state
   * machine: a capability holder the run was never shared with gets a safe refusal instead of the
   * scope, state, reason, hash and version of somebody else's export.
   */
  @IsTest
  static void aCapabilityHolderWithoutAShareCannotObserveTheRun() {
    Id runId;
    System.runAs(requester()) {
      runId = new ALT_CLS_ExportService()
        .request(authorizedHolderId(), null)
        .runId;
    }
    System.runAs(peer()) {
      try {
        new ALT_CLS_ExportService().read(runId);
        Assert.fail('Sem acesso ao run, a observacao nao entrega nada.');
      } catch (ALT_CLS_ExportService.ExportException refused) {
        Assert.areEqual('NOT_ACCESSIBLE', refused.code);
      }
    }
  }

  /**
   * The requester binding is revalidated on the download, and a nulled one — the requester user was
   * deleted, which is why the lookup is `SetNull` — is a refusal that revokes, never a wildcard
   * that serves the artifact to whoever asks next.
   */
  @IsTest
  static void aNulledRequesterBindingRevokesInsteadOfServing() {
    Id runId;
    Decimal version;
    System.runAs(requester()) {
      ALT_CLS_ExportService.RunView run = new ALT_CLS_ExportService()
        .request(authorizedHolderId(), null);
      runId = run.runId;
      version = run.version;
    }
    // Only the platform nulls a binding a user may not write.
    Database.update(
      new AXF_OBJ_ExportRun__c(Id = runId, AXF_EPR_LKP_Requester__c = null),
      AccessLevel.SYSTEM_MODE
    );

    System.runAs(requester()) {
      ALT_CLS_ExportService.DownloadView refused = new ALT_CLS_ExportService()
        .download(runId, version);
      Assert.isFalse(refused.ready);
      Assert.areEqual('FORBIDDEN', refused.outcome);
      Assert.isNull(refused.bodyBase64);
      AXF_OBJ_ExportRun__c stored = storedRun(runId);
      Assert.areEqual('REVOKED', stored.AXF_EPR_PKL_Status__c);
      Assert.areEqual('ACCESS_REVOKED', stored.AXF_EPR_TXT_Reason__c);
      Assert.isNull(stored.AXF_EPR_TXT_ContentDocument__c);
    }
    Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument]);
  }

  // ---------------------------------------------------------------- share and notification seams
  /**
   * Requester ≠ holder owner. Every other fixture creates the holder inside `runAs(requester)`,
   * so `grantRequesterAccess` returned early and the share insert — whose result was discarded —
   * never ran. Here the run follows the peer (G2) and the requester keeps only the share the
   * service writes.
   */
  @IsTest
  static void aRequesterWhoDoesNotOwnTheHolderKeepsAccessThroughTheGrantedShare() {
    Id sharedId = sharedHolderId();
    // The holder belongs to the peer; the requester reaches it through an explicit read share,
    // which is what makes this requester a non-owner of the run the service is about to write.
    insert new AccountShare(
      AccountId = sharedId,
      UserOrGroupId = requester().Id,
      AccountAccessLevel = 'Read',
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None',
      RowCause = Schema.AccountShare.RowCause.Manual
    );
    Id runId;
    Decimal version;
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(sharedId, null);
      runId = run.runId;
      version = run.version;
      Assert.areEqual('PREPARED', run.status);
      Assert.isTrue(
        service.read(runId).canDownload,
        'Quem pediu le o proprio run pelo compartilhamento.'
      );
    }
    List<AXF_OBJ_ExportRun__Share> shares = [
      SELECT UserOrGroupId, AccessLevel, RowCause
      FROM AXF_OBJ_ExportRun__Share
      WHERE ParentId = :runId AND RowCause = 'Manual'
    ];
    Assert.areEqual(1, shares.size(), 'O compartilhamento foi gravado.');
    Assert.areEqual(requester().Id, shares[0].UserOrGroupId);
    Assert.areEqual(
      'Read',
      shares[0].AccessLevel,
      'Somente leitura: a maquina de estados e do Apex.'
    );
    Assert.areEqual(
      peer().Id,
      storedRun(runId).OwnerId,
      'O run segue o dono do titular (G2), nao quem pediu.'
    );

    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.DownloadView download = service.download(
        runId,
        version
      );
      Assert.isTrue(download.ready, download.outcome);
      Assert.areEqual('DOWNLOADED', service.read(runId).status);
    }
  }

  /**
   * The notice path. `notifyRequester` swallows every failure and exits silently when the
   * CustomNotificationType does not resolve, so asserting the text builder alone left a wrong
   * DeveloperName passing green: the seam is set only after the platform accepted the send.
   */
  @IsTest
  static void theReadyNoticeResolvesItsTypeAndIsActuallySent() {
    System.runAs(requester()) {
      ALT_CLS_ExportService.notificationSent = false;
      ALT_CLS_ExportService.lastNotificationTypeId = null;
      ALT_CLS_ExportService.RunView run = new ALT_CLS_ExportService()
        .request(authorizedHolderId(), null);
      Assert.isNotNull(run.runId);
      Assert.isTrue(
        ALT_CLS_ExportService.notificationSent,
        'A notificacao de exportacao pronta foi aceita pela plataforma.'
      );
      Assert.areEqual(
        [
          SELECT Id
          FROM CustomNotificationType
          WHERE DeveloperName = 'AXF_ExportReady'
          LIMIT 1
        ]
        .Id,
        ALT_CLS_ExportService.lastNotificationTypeId,
        'O tipo AXF_ExportReady resolve pelo DeveloperName.'
      );
    }
  }

  // ---------------------------------------------------------------- PII discipline

  @IsTest
  static void fileNameNotificationAndLogsCarryNoPii() {
    System.runAs(requester()) {
      ALT_CLS_ExportService.RunView run = new ALT_CLS_ExportService()
        .request(authorizedHolderId(), null);
      String opaqueName = storedRun(run.runId).Name;

      Assert.areEqual(
        'axon-export-' + opaqueName + '.csv',
        run.fileName,
        'O nome do arquivo deriva apenas do identificador opaco.'
      );
      Assert.isFalse(run.fileName.contains(IN_SCOPE_TEXT));
      Assert.isFalse(run.fileName.contains(HOLDER_NAME));
      Assert.isFalse(
        run.fileName.contains('2026'),
        'Sem data no nome do arquivo.'
      );

      // The text asserted here is the exact text the service sends.
      Map<String, String> sent = ALT_CLS_ExportService.notificationText(
        opaqueName
      );
      for (String part : sent.values()) {
        Assert.isFalse(
          part.contains(IN_SCOPE_TEXT),
          'Sem descricao na notificacao.'
        );
        Assert.isFalse(
          part.contains(HOLDER_NAME),
          'Sem titular na notificacao.'
        );
        Assert.isFalse(
          part.contains('55221'),
          'Sem identificador na notificacao.'
        );
        Assert.isFalse(part.contains('@'), 'Sem e-mail na notificacao.');
        Assert.isFalse(
          part.contains('2026'),
          'Sem data na notificacao: ' + part
        );
      }
      // The body names the artifact by its opaque number only; the title names nothing.
      Assert.isTrue(
        sent.get('body').contains(opaqueName),
        'A notificacao identifica apenas o run opaco.'
      );
      Assert.isFalse(
        sent.get('title').contains(opaqueName) ||
        sent.get('title').contains('EPR-'),
        'O titulo nao identifica registro algum.'
      );

      // Every code the service logs, through its single log-line builder.
      for (
        String code : new List<String>{
          'PREPARED',
          'DOWNLOADED',
          'NOTIFY_FAILED',
          'REVOKED_EXPIRED',
          'REVOKED_ACCESS_REVOKED',
          'REVOKED_ARTIFACT_MISSING',
          'REVOKED_ARTIFACT_MISMATCH',
          'REVOKED_ARTIFACT_NOT_REMOVED'
        }
      ) {
        String line = ALT_CLS_ExportService.logLine(code, opaqueName);
        Assert.isTrue(line.startsWith('AXF-118 '), line);
        Assert.isFalse(line.contains(IN_SCOPE_TEXT), line);
        Assert.isFalse(line.contains(HOLDER_NAME), line);
        Assert.isFalse(line.contains('55221'), line);
        Assert.isFalse(line.contains('@'), 'Nenhum e-mail em log: ' + line);
        Assert.isTrue(line.endsWith(opaqueName), line);
      }
    }
  }

  @IsTest
  static void revokedExportLeavesTheScopeUntouchedAndObservable() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(
        authorizedHolderId(),
        null
      );
      expire(run.runId);
      Assert.areEqual(
        'EXPIRED',
        service.download(run.runId, run.version).outcome
      );

      // Only the artifact was destroyed: the holder's facts are untouched by the export.
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE AXF_FTX_LKP_Account__c = :authorizedHolderId()
        ]
      );
      ALT_CLS_ExportService.RunView observed = service.read(run.runId);
      Assert.areEqual('REVOKED', observed.status);
      Assert.areEqual('EXPIRED', observed.reason);
      Assert.isNull(observed.fileName);
      Assert.isTrue(
        observed.version > run.version,
        'A revogacao avanca a versao (NFR-18).'
      );
    }
  }
}
