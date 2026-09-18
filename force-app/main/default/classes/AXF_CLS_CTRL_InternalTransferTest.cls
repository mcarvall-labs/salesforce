/**
 * @description AXF-32: the LWC controller surface (getContext/listPending/confirm/reverse) parses
 * strictly, sanitizes every failure to a {code}, and never leaks a stack trace or PII.
 */
@IsTest(isParallel=false)
private class AXF_CLS_CTRL_InternalTransferTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf32ctg', 'axf32ctn' }) {
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
          'AXF_PS_ReviewQueue',
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = users[0].Id,
        PermissionSetId = permissionSets.get('AXF_PS_GestorFinanceiro')
      ),
      new PermissionSetAssignment(
        AssigneeId = users[0].Id,
        PermissionSetId = permissionSets.get('AXF_PS_ReviewQueue')
      ),
      new PermissionSetAssignment(
        AssigneeId = users[1].Id,
        PermissionSetId = permissionSets.get('AXF_PS_Participante')
      )
    };
  }

  private class Fixture {
    public Account holder;
    public Id debitId;
    public Id creditId;
  }

  private static Fixture fixture(String key, Decimal amount) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Holder 32 ctrl ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    AXF_OBJ_BankAccount__c bankA = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
    );
    AXF_OBJ_BankAccount__c bankB = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert new List<AXF_OBJ_BankAccount__c>{ bankA, bankB };
    AXF_OBJ_BankAccountTransaction__c debit = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankA.Id,
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Transfer out ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf32ctrl-debit-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    AXF_OBJ_BankAccountTransaction__c credit = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankB.Id,
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'CREDIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Transfer in ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf32ctrl-credit-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert new List<AXF_OBJ_BankAccountTransaction__c>{ debit, credit };
    f.debitId = debit.Id;
    f.creditId = credit.Id;
    return f;
  }

  @IsTest
  static void surfaceCoversTheFullConfirmLifecycleAndSanitizesFailures() {
    Fixture f;
    System.runAs(byAlias('axf32ctg')) {
      f = fixture('ctrl', 175);
      ALT_CLS_InternalTransferService.SuggestInput suggestInput = new ALT_CLS_InternalTransferService.SuggestInput();
      suggestInput.debitTransactionId = f.debitId;
      suggestInput.creditTransactionId = f.creditId;
      Id transferId = new ALT_CLS_InternalTransferService()
        .suggest(suggestInput);

      Test.startTest();
      AXF_CLS_CTRL_InternalTransfer.Context context = AXF_CLS_CTRL_InternalTransfer.getContext();
      Assert.isTrue(context.canConfirm);
      Assert.areEqual(ALT_CLS_InternalTransferService.REASONS, context.reasons);

      List<ALT_CLS_InternalTransferService.TransferView> pending = AXF_CLS_CTRL_InternalTransfer.listPending();
      Boolean found = false;
      for (ALT_CLS_InternalTransferService.TransferView v : pending) {
        if (v.internalTransferId == transferId) {
          found = true;
          Assert.isNotNull(v.reviewItemId);
        }
      }
      Assert.isTrue(
        found,
        'the pending suggestion feeds the confirmation screen'
      );

      try {
        AXF_CLS_CTRL_InternalTransfer.confirm('{"nope":1}');
        Assert.fail('strict shape');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }

      ALT_CLS_InternalTransferService.ConfirmInput confirmInput = new ALT_CLS_InternalTransferService.ConfirmInput();
      confirmInput.internalTransferId = transferId;
      confirmInput.expectedVersion = 0;
      confirmInput.operationKey = 'axf32ctrl-confirm';
      ALT_CLS_InternalTransferService.TransferView confirmed = AXF_CLS_CTRL_InternalTransfer.confirm(
        JSON.serialize(confirmInput)
      );
      Assert.areEqual('CONFIRMED', confirmed.state);

      ALT_CLS_InternalTransferService.ReverseInput reverseInput = new ALT_CLS_InternalTransferService.ReverseInput();
      reverseInput.internalTransferId = transferId;
      reverseInput.expectedVersion = 1;
      reverseInput.reasonCode = 'OTHER';
      reverseInput.operationKey = 'axf32ctrl-reverse';
      ALT_CLS_InternalTransferService.TransferView reversed = AXF_CLS_CTRL_InternalTransfer.reverse(
        JSON.serialize(reverseInput)
      );
      Assert.areEqual('REVERSED', reversed.state);
      Test.stopTest();
    }
  }

  @IsTest
  static void missingCapabilityIsSanitizedAndReportsNothing() {
    System.runAs(byAlias('axf32ctn')) {
      Test.startTest();
      AXF_CLS_CTRL_InternalTransfer.Context context = AXF_CLS_CTRL_InternalTransfer.getContext();
      Assert.isFalse(context.canConfirm);
      try {
        AXF_CLS_CTRL_InternalTransfer.listPending();
        Assert.fail('capability missing');
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      Test.stopTest();
    }
  }
}
