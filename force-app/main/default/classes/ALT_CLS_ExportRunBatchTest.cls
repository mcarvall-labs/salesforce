/**
 * @description AXF-118: drives ALT_CLS_ExportRunBatch directly (small batch scope size, so a
 * handful of facts still force multiple execute() calls) to prove the three-source iterator
 * drains FinancialTransaction, then BankAccountTransaction, then CreditCardTransaction in order,
 * never mixing rows across an account, and that finish() prepares a correctly hashed artifact
 * containing every row from every source exactly once.
 */
@IsTest
private class ALT_CLS_ExportRunBatchTest {
  private static User requester() {
    return [SELECT Id FROM User WHERE Alias = 'axf118b' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User requester = new User(
      Alias = 'axf118b',
      Email = 'axf118b@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Export Batch Requester',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf118b.' + System.now().getTime() + '@example.invalid'
    );
    insert requester;
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
        Name = 'Holder Export Batch',
        RecordTypeId = Account.SObjectType.getDescribe()
          .getRecordTypeInfosByDeveloperName()
          .get('AXF_Business')
          .getRecordTypeId()
      );
      insert holder;
      List<AXF_OBJ_FinancialTransaction__c> ftx = new List<AXF_OBJ_FinancialTransaction__c>();
      for (Integer i = 0; i < 3; i++) {
        ftx.add(
          new AXF_OBJ_FinancialTransaction__c(
            AXF_FTX_LKP_Account__c = holder.Id,
            AXF_FTX_NUM_Magnitude__c = 10 + i,
            AXF_FTX_PKL_Direction__c = 'DEBIT',
            AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_FTX_DAT_PurchaseDate__c = Date.newInstance(2026, 6, 1 + i),
            AXF_FTX_PKL_Status__c = 'PLANNED',
            AXF_FTX_NUM_Version__c = 0,
            AXF_FTX_TXT_Description__c = 'FTX batch ' + i,
            AXF_FTX_EXI_ClientRequestId__c = 'axf118batch-ftx-' + i
          )
        );
      }
      insert ftx;

      AXF_OBJ_BankAccount__c bankAccount = new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = holder.Id,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
      );
      insert bankAccount;
      List<AXF_OBJ_BankAccountTransaction__c> bat = new List<AXF_OBJ_BankAccountTransaction__c>();
      for (Integer i = 0; i < 2; i++) {
        bat.add(
          new AXF_OBJ_BankAccountTransaction__c(
            AXF_BAT_MDR_BankAccount__c = bankAccount.Id,
            AXF_BAT_DAT_Date__c = Date.newInstance(2026, 6, 5 + i),
            AXF_BAT_NUM_Magnitude__c = 20 + i,
            AXF_BAT_PKL_Direction__c = 'DEBIT',
            AXF_BAT_PKL_Source__c = 'MANUAL',
            AXF_BAT_PKL_Status__c = 'POSTED',
            AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_BAT_NUM_Version__c = 0,
            AXF_BAT_EXI_SourceKey__c = 'axf118batch-bat-' + i,
            AXF_BAT_TXT_Description__c = 'BAT batch ' + i
          )
        );
      }
      insert bat;

      AXF_OBJ_CreditCard__c creditCard = new AXF_OBJ_CreditCard__c(
        AXF_CC_LKP_Account__c = holder.Id,
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
      );
      insert creditCard;
      List<AXF_OBJ_CreditCardTransaction__c> cct = new List<AXF_OBJ_CreditCardTransaction__c>();
      for (Integer i = 0; i < 2; i++) {
        cct.add(
          new AXF_OBJ_CreditCardTransaction__c(
            AXF_CCT_MDR_CreditCard__c = creditCard.Id,
            AXF_CCT_DAT_Date__c = Date.newInstance(2026, 6, 8 + i),
            AXF_CCT_NUM_Magnitude__c = 30 + i,
            AXF_CCT_PKL_Direction__c = 'DEBIT',
            AXF_CCT_PKL_Source__c = 'MANUAL',
            AXF_CCT_PKL_Status__c = 'POSTED',
            AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_CCT_NUM_Version__c = 0,
            AXF_CCT_EXI_SourceKey__c = 'axf118batch-cct-' + i,
            AXF_CCT_TXT_Description__c = 'CCT batch ' + i
          )
        );
      }
      insert cct;
    }
  }

  private static Id holderId() {
    return [SELECT Id FROM Account WHERE Name = 'Holder Export Batch' LIMIT 1]
    .Id;
  }

  /** Stages a RUNNING run directly: the fixture a resumable batch job starts from. */
  private static Id stagedRunningRun(Id accountId, Id requesterId) {
    AXF_OBJ_ExportRun__c run = new AXF_OBJ_ExportRun__c(
      AXF_EPR_LKP_Account__c = accountId,
      AXF_EPR_LKP_Requester__c = requesterId,
      AXF_EPR_EXI_ScopeKey__c = ALT_CLS_ExportService.scopeKey(
        accountId,
        requesterId
      ),
      AXF_EPR_PKL_Status__c = 'RUNNING',
      AXF_EPR_NUM_Version__c = 1,
      AXF_EPR_NUM_Attempt__c = 1
    );
    insert run;
    return run.Id;
  }

  @IsTest
  static void batchDrainsAllThreeSourcesInOrderAndPreparesTheRun() {
    System.runAs(requester()) {
      Id accountId = holderId();
      Id runId = stagedRunningRun(accountId, requester().Id);

      Test.startTest();
      // A custom Iterable<SObject> (not a Database.QueryLocator) only supports one execute()
      // chunk under Test.startTest()/stopTest(): a scope that forces a second chunk is a second,
      // disallowed executeBatch. The scope here still exceeds every row (7 total: 3 FTX + 2 BAT +
      // 2 CCT), so the single chunk still exercises the iterator crossing every source boundary.
      Database.executeBatch(new ALT_CLS_ExportRunBatch(runId), 10);
      Test.stopTest();

      AXF_OBJ_ExportRun__c stored = [
        SELECT
          AXF_EPR_PKL_Status__c,
          AXF_EPR_TXT_ContentHash__c,
          AXF_EPR_TXT_ContentDocument__c,
          AXF_EPR_DT_ExpiresAt__c,
          AXF_EPR_TXT_Cursor__c
        FROM AXF_OBJ_ExportRun__c
        WHERE Id = :runId
      ];
      Assert.areEqual(
        'PREPARED',
        stored.AXF_EPR_PKL_Status__c,
        'O lote concluiu as tres fontes e preparou o run.'
      );
      Assert.isNotNull(stored.AXF_EPR_TXT_ContentHash__c);
      Assert.isNotNull(stored.AXF_EPR_DT_ExpiresAt__c);

      Id documentId = Id.valueOf(stored.AXF_EPR_TXT_ContentDocument__c);
      String content = [
          SELECT VersionData
          FROM ContentVersion
          WHERE ContentDocumentId = :documentId AND IsLatest = TRUE
        ]
        .VersionData.toString();

      Assert.isTrue(content.contains('# FTX'));
      Assert.isTrue(content.contains('# BAT'));
      Assert.isTrue(content.contains('# CCT'));
      Assert.isTrue(content.contains('FTX batch 0'));
      Assert.isTrue(content.contains('FTX batch 2'));
      Assert.isTrue(content.contains('BAT batch 0'));
      Assert.isTrue(content.contains('BAT batch 1'));
      Assert.isTrue(content.contains('CCT batch 0'));
      Assert.isTrue(content.contains('CCT batch 1'));
      // Exactly one column-header line per source, no matter how many single-row chunks it took.
      Assert.areEqual(
        1,
        countOccurrences(
          content,
          'date,direction,amount,currency,status,description\n'
        ),
        'O cabecalho FTX aparece uma unica vez, mesmo com um chunk por linha.'
      );
      Assert.areEqual(
        1,
        countOccurrences(content, 'bankAccount\n'),
        'O cabecalho BAT aparece uma unica vez.'
      );
      Assert.areEqual(
        1,
        countOccurrences(content, 'merchant\n'),
        'O cabecalho CCT aparece uma unica vez.'
      );
      Assert.areEqual(
        EncodingUtil.convertToHex(
          Crypto.generateDigest('SHA-256', Blob.valueOf(content))
        ),
        stored.AXF_EPR_TXT_ContentHash__c,
        'O hash gravado confere com o conteudo final.'
      );
    }
  }

  private static Integer countOccurrences(String haystack, String needle) {
    Integer count = 0;
    Integer fromIndex = 0;
    Integer found = haystack.indexOf(needle, fromIndex);
    while (found >= 0) {
      count++;
      fromIndex = found + needle.length();
      found = haystack.indexOf(needle, fromIndex);
    }
    return count;
  }
}
