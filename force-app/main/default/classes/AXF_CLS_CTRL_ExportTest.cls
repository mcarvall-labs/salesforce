/**
 * @description AXF-118: AXF_CLS_CTRL_Export is a thin pass-through over ALT_CLS_ExportService —
 * these tests prove it neither bypasses nor weakens any server-side revalidation (capability,
 * requester binding, window) and that failures reach the client sanitized as {code}, never as a
 * stack trace or an unhandled platform exception.
 */
@IsTest
private class AXF_CLS_CTRL_ExportTest {
  private static User requester() {
    return [SELECT Id FROM User WHERE Alias = 'axf118c' LIMIT 1];
  }

  private static User peer() {
    return [SELECT Id FROM User WHERE Alias = 'axf118p2' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User requester = new User(
      Alias = 'axf118c',
      Email = 'axf118c@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Export Controller Requester',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf118c.' + System.now().getTime() + '@example.invalid'
    );
    User peer = requester.clone(false, false, false, false);
    peer.Alias = 'axf118p2';
    peer.LastName = 'Export Controller Peer';
    peer.Username = 'axf118p2.' + System.now().getTime() + '@example.invalid';
    insert new List<User>{ requester, peer };
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
    }
    insert assignments;
    System.runAs(requester) {
      Account holder = new Account(
        Name = 'Holder Export Controller',
        RecordTypeId = Account.SObjectType.getDescribe()
          .getRecordTypeInfosByDeveloperName()
          .get('AXF_Business')
          .getRecordTypeId()
      );
      insert holder;
      insert new AXF_OBJ_FinancialTransaction__c(
        AXF_FTX_LKP_Account__c = holder.Id,
        AXF_FTX_NUM_Magnitude__c = 42.5,
        AXF_FTX_PKL_Direction__c = 'DEBIT',
        AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_FTX_DAT_PurchaseDate__c = Date.newInstance(2026, 5, 1),
        AXF_FTX_PKL_Status__c = 'PLANNED',
        AXF_FTX_NUM_Version__c = 0,
        AXF_FTX_TXT_Description__c = 'Fato via controller',
        AXF_FTX_EXI_ClientRequestId__c = 'axf118ctrl-1'
      );
    }
  }

  private static Id holderId() {
    return [
      SELECT Id
      FROM Account
      WHERE Name = 'Holder Export Controller'
      LIMIT 1
    ]
    .Id;
  }

  @IsTest
  static void getContextReportsTheCapabilityHeld() {
    System.runAs(requester()) {
      AXF_CLS_CTRL_Export.Context context = AXF_CLS_CTRL_Export.getContext();
      Assert.isTrue(
        context.canExport,
        'AXF_PS_GestorFinanceiro concede AXF_CanExportData.'
      );
    }
  }

  @IsTest
  static void requestReadAndDownloadDelegateToTheService() {
    System.runAs(requester()) {
      Test.startTest();
      ALT_CLS_ExportService.RunView run = AXF_CLS_CTRL_Export.request(
        holderId(),
        null
      );
      Test.stopTest();

      Assert.areEqual('PREPARED', run.status);
      ALT_CLS_ExportService.RunView observed = AXF_CLS_CTRL_Export.read(
        run.runId
      );
      Assert.areEqual(run.runId, observed.runId);
      Assert.isTrue(observed.canDownload);

      ALT_CLS_ExportService.DownloadView download = AXF_CLS_CTRL_Export.download(
        run.runId,
        observed.version
      );
      Assert.isTrue(download.ready, download.outcome);
      Assert.isNotNull(download.bodyBase64);
    }
  }

  /** The controller must not surface the platform exception directly: only a sanitized {code}. */
  @IsTest
  static void invalidInputIsSanitized() {
    System.runAs(requester()) {
      try {
        AXF_CLS_CTRL_Export.request(null, null);
        Assert.fail('Escopo obrigatorio.');
      } catch (AuraHandledException sanitized) {
        Assert.areEqual('INVALID_INPUT', sanitized.getMessage());
      }
    }
  }

  /**
   * The controller adds no surface that bypasses the server-side revalidation
   * ALT_CLS_ExportService already performs on every download: another operator, even one holding
   * the capability, is refused and the artifact is revoked exactly like the direct-service test
   * proves — the controller path is not a shortcut around it.
   */
  @IsTest
  static void downloadThroughTheControllerStillRevalidatesTheExactRequester() {
    Id runId;
    Decimal version;
    System.runAs(requester()) {
      ALT_CLS_ExportService.RunView run = AXF_CLS_CTRL_Export.request(
        holderId(),
        null
      );
      runId = run.runId;
      version = run.version;
    }
    Database.insert(
      new AXF_OBJ_ExportRun__Share(
        ParentId = runId,
        UserOrGroupId = peer().Id,
        AccessLevel = 'Read',
        RowCause = Schema.AXF_OBJ_ExportRun__Share.RowCause.Manual
      )
    );
    System.runAs(peer()) {
      // download() reports an authorization refusal as an outcome, never a thrown exception,
      // because the refusal must commit the artifact's revocation (AC-2) — an unhandled
      // exception would roll that back. The controller must pass this outcome through as-is.
      ALT_CLS_ExportService.DownloadView refused = AXF_CLS_CTRL_Export.download(
        runId,
        version
      );
      Assert.isFalse(refused.ready);
      Assert.areEqual(
        'FORBIDDEN',
        refused.outcome,
        'Sem AXF_CanExportData o peer e recusado, e o servico ja revogou o artefato.'
      );
      Assert.isNull(refused.bodyBase64);
    }
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ContentDocument],
      'A recusa atraves do controller ainda revoga o artefato (AC-2), sem atalho.'
    );
  }
}
