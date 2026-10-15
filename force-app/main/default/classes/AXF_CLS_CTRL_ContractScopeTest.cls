@IsTest
private class AXF_CLS_CTRL_ContractScopeTest {
  private static Account holder;

  private static AXF_OBJ_Contract__c contract(Integer count) {
    return contract('AXF_Installment', count);
  }

  private static AXF_OBJ_Contract__c contract(
    String recordType,
    Integer count
  ) {
    holder = new Account(Name = 'Titular');
    insert holder;
    AXF_OBJ_Contract__c c = new AXF_OBJ_Contract__c(
      Name = 'Carta',
      AXF_CTR_MD_Holder__c = holder.Id,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get(recordType)
        .getRecordTypeId(),
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = 'Active',
      AXF_CTR_DAT_FirstDueDate__c = Date.today().addDays(5),
      AXF_CTR_CUR_Amount__c = 100,
      AXF_CTR_NUM_InstallmentCount__c = count
    );
    insert c;
    new ALT_CLS_ContractGeneration().generate(new Set<Id>{ c.Id }, false);
    return c;
  }

  private static List<AXF_OBJ_Entry__c> entries(Id contractId) {
    return [
      SELECT
        Id,
        Name,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_PKL_Status__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :contractId
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
  }

  private static Map<String, Object> scope(String name) {
    return new Map<String, Object>{ 'scope' => name };
  }

  private static String errorOf(Id contractId, Map<String, Object> values) {
    return errorOf(contractId, values, null);
  }

  private static String errorOf(
    Id contractId,
    Map<String, Object> values,
    Map<String, Object> scopes
  ) {
    try {
      AXF_CLS_CTRL_ContractScope.save(contractId, values, scopes);
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
    return null;
  }

  @IsTest
  static void previewDoesNotWriteAnything() {
    AXF_OBJ_Contract__c c = contract(3);
    Integer dmlBefore = Limits.getDmlStatements();
    AXF_CLS_CTRL_ContractScope.Preview preview = AXF_CLS_CTRL_ContractScope.preview(
      c.Id,
      new Map<String, Object>{ 'AXF_CTR_CUR_Amount__c' => 150 },
      new Map<String, Object>{ 'AMOUNT' => scope('ALL') }
    );
    System.assertEquals(dmlBefore, Limits.getDmlStatements());
    System.assertEquals(3, preview.updated);
    System.assertEquals(3, preview.rows.size());
    System.assertEquals(100, preview.rows[0].amount);
    System.assertEquals(150, preview.rows[0].newAmount);
    System.assertEquals(100, entries(c.Id)[0].AXF_ENT_CUR_Amount__c);
    System.assertEquals(
      100,
      [SELECT AXF_CTR_CUR_Amount__c FROM AXF_OBJ_Contract__c WHERE Id = :c.Id]
      .AXF_CTR_CUR_Amount__c
    );
  }

  @IsTest
  static void savePreviewMatchesAndOnlyTheChosenScopeChanges() {
    AXF_OBJ_Contract__c c = contract(3);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    rows[0].AXF_ENT_PKL_Status__c = 'Realized';
    rows[0].AXF_ENT_DAT_PaymentDate__c = Date.today();
    update rows[0];
    Map<String, Object> values = new Map<String, Object>{
      'Name' => 'Nova',
      'AXF_CTR_CUR_Amount__c' => '150'
    };
    Map<String, Object> scopes = new Map<String, Object>{
      'NAME' => scope('ALL'),
      'AMOUNT' => scope('NONE')
    };
    AXF_CLS_CTRL_ContractScope.Preview preview = AXF_CLS_CTRL_ContractScope.preview(
      c.Id,
      values,
      scopes
    );
    AXF_CLS_CTRL_ContractScope.Summary summary = AXF_CLS_CTRL_ContractScope.save(
      c.Id,
      values,
      scopes
    );
    System.assertEquals(preview.updated, summary.updated);
    System.assertEquals(2, summary.updated);
    System.assertEquals(false, AXF_CLS_ContractHandler.bypass);
    AXF_OBJ_Contract__c saved = [
      SELECT Name, AXF_CTR_CUR_Amount__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :c.Id
    ];
    System.assertEquals('Nova', saved.Name);
    System.assertEquals(150, saved.AXF_CTR_CUR_Amount__c);
    List<AXF_OBJ_Entry__c> after = entries(c.Id);
    System.assertEquals(rows[0].Name, after[0].Name, 'Realized is preserved');
    System.assertEquals('Nova 2/3', after[1].Name);
    System.assertEquals('Nova 3/3', after[2].Name);
    for (AXF_OBJ_Entry__c e : after) {
      System.assertEquals(
        100,
        e.AXF_ENT_CUR_Amount__c,
        'The trigger must not propagate the amount'
      );
    }
  }

  @IsTest
  static void aNewInstallmentCountCreatesTheMissingEntriesWithoutDuplicating() {
    AXF_OBJ_Contract__c c = contract(3);
    AXF_CLS_CTRL_ContractScope.Summary summary = AXF_CLS_CTRL_ContractScope.save(
      c.Id,
      new Map<String, Object>{ 'AXF_CTR_NUM_InstallmentCount__c' => 5 },
      null
    );
    System.assertEquals(2, summary.created);
    System.assertEquals(5, entries(c.Id).size());
  }

  @IsTest
  static void aValidationFailureLeavesTheContractAndTheEntriesUntouched() {
    AXF_OBJ_Contract__c c = contract(3);
    Account other = new Account(Name = 'Outro titular');
    insert other;
    AXF_OBJ_BankAccount__c foreign = new AXF_OBJ_BankAccount__c(
      Name = 'Conta de outro',
      AXF_BA_MD_Holder__c = other.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert foreign;
    String message = errorOf(
      c.Id,
      new Map<String, Object>{
        'Name' => 'Nova',
        'AXF_CTR_LKP_BankAccount__c' => foreign.Id
      }
    );
    System.assertNotEquals(null, message);
    System.assertNotEquals('Script-thrown exception', message);
    System.assertEquals(
      'Carta',
      [SELECT Name FROM AXF_OBJ_Contract__c WHERE Id = :c.Id].Name
    );
    for (AXF_OBJ_Entry__c e : entries(c.Id)) {
      System.assertEquals(
        null,
        [
          SELECT AXF_ENT_LKP_BankAccount__c
          FROM AXF_OBJ_Entry__c
          WHERE Id = :e.Id
        ]
        .AXF_ENT_LKP_BankAccount__c
      );
    }
    System.assertEquals(false, AXF_CLS_ContractHandler.bypass);
  }

  @IsTest
  static void aFailureAfterTheEntriesWereUpdatedUndoesBoth() {
    AXF_OBJ_Contract__c c = contract(3);
    List<AXF_OBJ_Entry__c> before = entries(c.Id);
    AXF_CLS_CTRL_ContractScope.failAfterEntryUpdate = true;
    String message = errorOf(
      c.Id,
      new Map<String, Object>{
        'Name' => 'Nova',
        'AXF_CTR_CUR_Amount__c' => 150
      },
      new Map<String, Object>{
        'NAME' => scope('ALL'),
        'AMOUNT' => scope('ALL')
      }
    );
    System.assert(message.contains('Falha simulada'), message);
    AXF_OBJ_Contract__c saved = [
      SELECT Name, AXF_CTR_CUR_Amount__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :c.Id
    ];
    System.assertEquals('Carta', saved.Name);
    System.assertEquals(100, saved.AXF_CTR_CUR_Amount__c);
    List<AXF_OBJ_Entry__c> after = entries(c.Id);
    System.assertEquals(before.size(), after.size());
    for (Integer i = 0; i < after.size(); i++) {
      System.assertEquals(before[i].Name, after[i].Name);
      System.assertEquals(
        before[i].AXF_ENT_CUR_Amount__c,
        after[i].AXF_ENT_CUR_Amount__c
      );
    }
    System.assertEquals(false, AXF_CLS_ContractHandler.bypass);
  }

  @IsTest
  static void aCaseOnlyRenameChangesTheContractAndTheEntries() {
    AXF_OBJ_Contract__c c = contract(3);
    AXF_CLS_CTRL_ContractScope.Summary summary = AXF_CLS_CTRL_ContractScope.save(
      c.Id,
      new Map<String, Object>{ 'Name' => 'carta' },
      new Map<String, Object>{ 'NAME' => scope('ALL') }
    );
    System.assertEquals(3, summary.updated);
    String savedName = [SELECT Name FROM AXF_OBJ_Contract__c WHERE Id = :c.Id]
    .Name;
    System.assert('carta'.equals(savedName), savedName);
    for (AXF_OBJ_Entry__c e : entries(c.Id)) {
      System.assert(e.Name.startsWith('carta '), e.Name);
    }
  }

  @IsTest
  static void anInvalidStartingInstallmentIsRejected() {
    AXF_OBJ_Contract__c c = contract(2);
    List<String> invalid = new List<String>{
      'abc',
      '1.5',
      '0',
      '-2',
      '99999999999'
    };
    for (String bad : invalid) {
      String message = errorOf(
        c.Id,
        new Map<String, Object>{ 'Name' => 'X' },
        new Map<String, Object>{
          'NAME' => new Map<String, Object>{
            'scope' => 'FROM',
            'fromNumber' => bad
          }
        }
      );
      System.assertEquals('Parcela inicial inválida.', message, bad);
    }
  }

  @IsTest
  static void serverSideValuesAreValidated() {
    AXF_OBJ_Contract__c c = contract(2);
    System.assertEquals(
      'O nome do contrato não pode ficar em branco.',
      errorOf(c.Id, new Map<String, Object>{ 'Name' => '  ' })
    );
    for (Integer bad : new List<Integer>{ 0, 601 }) {
      System.assert(
        errorOf(
            c.Id,
            new Map<String, Object>{ 'AXF_CTR_NUM_InstallmentCount__c' => bad }
          )
          .contains('entre 1 e 600')
      );
    }
    System.assertEquals(
      'Carta',
      [SELECT Name FROM AXF_OBJ_Contract__c WHERE Id = :c.Id].Name
    );
  }

  @IsTest
  static void theDueDayMustBeBetween1And31() {
    AXF_OBJ_Contract__c recurring = contract('AXF_Recurring', null);
    for (Object bad : new List<Object>{ 0, 32, '5.5' }) {
      System.assert(
        errorOf(
            recurring.Id,
            new Map<String, Object>{ 'AXF_CTR_NUM_DueDay__c' => bad }
          )
          .contains('entre 1 e 31'),
        String.valueOf(bad)
      );
    }
  }

  @IsTest
  static void thePreviewListsCategoryAndAccountChanges() {
    AXF_OBJ_Contract__c c = contract(2);
    AXF_OBJ_Category__c category = new AXF_OBJ_Category__c(
      Name = 'Casa',
      AXF_CAT_PKL_Type__c = 'Expense'
    );
    insert category;
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert bank;
    Map<String, Object> values = new Map<String, Object>{
      'AXF_CTR_LKP_Category__c' => category.Id,
      'AXF_CTR_LKP_BankAccount__c' => bank.Id
    };
    AXF_CLS_CTRL_ContractScope.Preview onlyCategory = AXF_CLS_CTRL_ContractScope.preview(
      c.Id,
      values,
      new Map<String, Object>{
        'CATEGORY' => scope('ALL'),
        'ACCOUNT' => scope('NONE')
      }
    );
    System.assertEquals(
      new List<String>{ 'Categoria' },
      onlyCategory.rows[0].changedFields
    );
    AXF_CLS_CTRL_ContractScope.Preview both = AXF_CLS_CTRL_ContractScope.preview(
      c.Id,
      values,
      new Map<String, Object>{
        'CATEGORY' => scope('ALL'),
        'ACCOUNT' => scope('ALL')
      }
    );
    System.assertEquals(
      new List<String>{ 'Categoria', 'Conta/Cartão' },
      both.rows[0].changedFields
    );
  }

  @IsTest
  static void invalidRequestsAreRejectedInPortuguese() {
    AXF_OBJ_Contract__c c = contract(2);
    System.assert(errorOf(null, null).contains('Informe o contrato'));
    System.assert(
      errorOf(
          c.Id,
          new Map<String, Object>{ 'AXF_CTR_PKL_Status__c' => 'Closed' }
        )
        .contains('não pode ser editado')
    );
    System.assertNotEquals(
      null,
      errorOf(
        c.Id,
        new Map<String, Object>{ 'AXF_CTR_DAT_FirstDueDate__c' => 'abc' }
      )
    );
    String badScope;
    try {
      AXF_CLS_CTRL_ContractScope.save(
        c.Id,
        new Map<String, Object>{ 'Name' => 'X' },
        new Map<String, Object>{ 'NAME' => scope('QUALQUER') }
      );
    } catch (AuraHandledException e) {
      badScope = e.getMessage();
    }
    System.assert(badScope.contains('Escopo inválido'));
    String noStart;
    try {
      AXF_CLS_CTRL_ContractScope.save(
        c.Id,
        new Map<String, Object>{ 'Name' => 'X' },
        new Map<String, Object>{ 'NAME' => scope('FROM') }
      );
    } catch (AuraHandledException e) {
      noStart = e.getMessage();
    }
    System.assert(noStart.contains('parcela inicial'));
  }

  @IsTest
  static void editingOutsideTheScreenStillPropagatesTheAmount() {
    AXF_OBJ_Contract__c c = contract(3);
    c.AXF_CTR_CUR_Amount__c = 175;
    update c;
    for (AXF_OBJ_Entry__c e : entries(c.Id)) {
      System.assertEquals(175, e.AXF_ENT_CUR_Amount__c);
    }
  }

  @IsTest
  static void defaultScopeIsFutureAndUnchangedValuesSaveNothing() {
    AXF_OBJ_Contract__c c = contract(3);
    AXF_CLS_CTRL_ContractScope.Summary same = AXF_CLS_CTRL_ContractScope.save(
      c.Id,
      new Map<String, Object>{ 'Name' => 'Carta' },
      null
    );
    System.assertEquals(0, same.updated);
    AXF_CLS_CTRL_ContractScope.Summary changed = AXF_CLS_CTRL_ContractScope.save(
      c.Id,
      new Map<String, Object>{ 'AXF_CTR_CUR_Amount__c' => 120 },
      null
    );
    System.assertEquals(3, changed.updated);
  }
}
