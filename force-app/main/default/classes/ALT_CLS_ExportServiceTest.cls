/**
 * @description AXF-118: autorizacao revalidada na solicitacao e de novo no download privado de
 * curta duracao; download expirado ou sem autorizacao e revogado (artefato excluido); nome de
 * arquivo, notificacao e logs sem PII; replay idempotente por escopo e autor; acesso negado e
 * erros sanitizados. Catches name the service exception on purpose: Assert.fail raises
 * AssertException, which a generic catch would swallow and turn into a false pass.
 */
@IsTest
private class ALT_CLS_ExportServiceTest {
  private static final String HOLDER_NAME = 'Holder Axon Export';
  private static final String IN_SCOPE_TEXT = 'Padaria do Ze 55221';
  private static final String OUT_OF_SCOPE_TEXT = 'Farmacia Alheia 99887';

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
    // The requester's own scope, with one in-scope fact carrying a spreadsheet formula prefix.
    System.runAs(requester) {
      Account holder = holder(HOLDER_NAME);
      fact(holder.Id, 'axf118-a', IN_SCOPE_TEXT, Date.newInstance(2026, 3, 10));
      fact(
        holder.Id,
        'axf118-b',
        '=SUM(1,2) formula livre',
        Date.newInstance(2026, 3, 11)
      );
    }
    // A scope the requester is not authorized for: owned by the peer, Private OWD, no role rule.
    System.runAs(peer) {
      Account foreign = holder('Holder Fora do Escopo');
      fact(
        foreign.Id,
        'axf118-c',
        OUT_OF_SCOPE_TEXT,
        Date.newInstance(2026, 3, 12)
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

  private static Id authorizedHolderId() {
    return [SELECT Id FROM Account WHERE Name = :HOLDER_NAME LIMIT 1].Id;
  }

  private static Id foreignHolderId() {
    return [SELECT Id FROM Account WHERE Name = 'Holder Fora do Escopo' LIMIT 1]
    .Id;
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

  // ---------------------------------------------------------------- AC-1

  @IsTest
  static void authorizedRequestPreparesAndDownloadRevalidates() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      Test.startTest();
      ALT_CLS_ExportService.RunView run = service.request(authorizedHolderId());
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
      // requester, and that residual is declared in docs/implementation/AXF-118.md.
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

      ALT_CLS_ExportService.DownloadView download = service.download(run.runId);
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
      ALT_CLS_ExportService.DownloadView again = service.download(run.runId);
      Assert.isTrue(again.ready, again.outcome);
      Assert.areEqual(download.contentHash, again.contentHash);
    }
  }

  @IsTest
  static void exportedCellsAreQuotedAndFormulaPrefixedValuesAreInert() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(authorizedHolderId());
      String csv = EncodingUtil.base64Decode(
          service.download(run.runId).bodyBase64
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

  @IsTest
  static void replayWithinTheWindowReusesTheSameRunAndArtifact() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView first = service.request(
        authorizedHolderId()
      );
      ALT_CLS_ExportService.RunView second = service.request(
        authorizedHolderId()
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
  static void anotherAuthorizedOperatorCannotDownloadSomeoneElsesArtifact() {
    Id runId;
    System.runAs(requester()) {
      runId = new ALT_CLS_ExportService().request(authorizedHolderId()).runId;
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
      try {
        new ALT_CLS_ExportService().download(runId);
        Assert.fail('Artefato vinculado ao solicitante exato.');
      } catch (ALT_CLS_ExportService.ExportException denied) {
        Assert.areEqual('FORBIDDEN', denied.code);
      }
      Assert.isFalse(
        new ALT_CLS_ExportService().read(runId).canDownload,
        'Nao e o solicitante.'
      );
    }
    System.runAs(requester()) {
      Assert.isTrue(new ALT_CLS_ExportService().download(runId).ready);
    }
  }

  @IsTest
  static void requestWithoutTheCapabilityIsForbidden() {
    // Resolved outside runAs: the user under test cannot see the scope at all, and the
    // capability check must be what refuses the request.
    Id accountId = authorizedHolderId();
    System.runAs(nobody()) {
      try {
        new ALT_CLS_ExportService().request(accountId);
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
        new ALT_CLS_ExportService().request(foreignId);
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
        service.request(null);
        Assert.fail('Escopo obrigatorio.');
      } catch (ALT_CLS_ExportService.ExportException invalid) {
        Assert.areEqual('INVALID_INPUT', invalid.code);
      }
      try {
        service.download(null);
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
        new ALT_CLS_ExportService().request(accountId);
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

  // ---------------------------------------------------------------- AC-2

  @IsTest
  static void expiredDownloadIsRevokedAndTheArtifactIsDeleted() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(authorizedHolderId());
      expire(run.runId);

      Test.startTest();
      ALT_CLS_ExportService.DownloadView refused = service.download(run.runId);
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

  @IsTest
  static void readNeverRevokesButDownloadEnforcesTheWindow() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(authorizedHolderId());
      expire(run.runId);

      ALT_CLS_ExportService.RunView observed = service.read(run.runId);
      Assert.isFalse(observed.canDownload, 'Disponibilidade real e reportada.');
      Assert.areEqual(
        'PREPARED',
        observed.status,
        'Observar nao revoga: o acesso ao download e que revoga.'
      );

      Assert.areEqual('EXPIRED', service.download(run.runId).outcome);
      Assert.areEqual('REVOKED', service.read(run.runId).status);
    }
  }

  @IsTest
  static void withdrawnScopeAuthorizationRevokesTheDownload() {
    Id foreignId = foreignHolderId();
    Id runId;
    System.runAs(requester()) {
      runId = new ALT_CLS_ExportService().request(authorizedHolderId()).runId;
    }
    // The artifact now points at a scope the requester is not authorized for, which is what a
    // withdrawn share looks like from the service's point of view.
    moveScopeTo(runId, foreignId);

    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      Test.startTest();
      ALT_CLS_ExportService.DownloadView refused = service.download(runId);
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
      ALT_CLS_ExportService.RunView run = service.request(authorizedHolderId());
      String deadArtifact = run.evidenceRef;
      expire(run.runId);
      Assert.areEqual('EXPIRED', service.download(run.runId).outcome);
      Assert.areEqual('REVOKED', service.download(run.runId).outcome);

      ALT_CLS_ExportService.RunView again = service.request(
        authorizedHolderId()
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
      Assert.isTrue(service.download(run.runId).ready);
    }
  }

  @IsTest
  static void artifactThatDoesNotMatchItsEvidenceIsRevokedInsteadOfServed() {
    System.runAs(requester()) {
      ALT_CLS_ExportService service = new ALT_CLS_ExportService();
      ALT_CLS_ExportService.RunView run = service.request(authorizedHolderId());
      Id documentId = [SELECT Id FROM ContentDocument LIMIT 1].Id;
      // A later version of the same document replaces the content that was hashed.
      insert new ContentVersion(
        ContentDocumentId = documentId,
        Title = run.fileName,
        PathOnClient = run.fileName,
        VersionData = Blob.valueOf('date,direction\n2019-01-01,CREDIT')
      );

      ALT_CLS_ExportService.DownloadView refused = service.download(run.runId);
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
      ALT_CLS_ExportService.RunView run = service.request(authorizedHolderId());
      delete new ContentDocument(Id = run.evidenceRef);

      ALT_CLS_ExportService.DownloadView refused = service.download(run.runId);
      Assert.isFalse(refused.ready);
      Assert.areEqual('ARTIFACT_MISSING', refused.outcome);
      Assert.areEqual('REVOKED', storedRun(run.runId).AXF_EPR_PKL_Status__c);
    }
  }

  // ---------------------------------------------------------------- PII discipline

  @IsTest
  static void fileNameNotificationAndLogsCarryNoPii() {
    System.runAs(requester()) {
      ALT_CLS_ExportService.RunView run = new ALT_CLS_ExportService()
        .request(authorizedHolderId());
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
          'REVOKED_ARTIFACT_MISMATCH'
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
      ALT_CLS_ExportService.RunView run = service.request(authorizedHolderId());
      expire(run.runId);
      Assert.areEqual('EXPIRED', service.download(run.runId).outcome);

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
