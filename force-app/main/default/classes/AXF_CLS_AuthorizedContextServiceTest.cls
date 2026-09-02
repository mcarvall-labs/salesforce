@IsTest
private class AXF_CLS_AuthorizedContextServiceTest {
  @IsTest
  static void shouldReturnOnlyHolderContextsWhenRowsAreVisible() {
    Id personTypeId = recordTypeId('AXF_Person');
    Id businessTypeId = recordTypeId('AXF_Business');
    Assert.isNotNull(personTypeId, 'Person holder record type must exist');
    Assert.isNotNull(businessTypeId, 'Business holder record type must exist');

    Account person = contextRow(fakeAccountId(1), 'Ana', 'AXF_Person');
    Account business = contextRow(
      fakeAccountId(2),
      'Axon Ltda',
      'AXF_Business'
    );

    AXF_CLS_AuthorizedContextService.contextsOverride = new List<Account>{
      person,
      business
    };
    AXF_CLS_AuthorizedContextService.currencyOverride = 'BRL';

    Test.startTest();
    List<AXF_CLS_AuthorizedContextService.ContextView> result = AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    Test.stopTest();

    Assert.areEqual(
      2,
      result.size(),
      'Both authorized holders must be returned'
    );
    Assert.areEqual('PERSON', result[0].contextType, 'Person context is typed');
    Assert.areEqual(
      'BUSINESS',
      result[1].contextType,
      'Business context is typed'
    );
    Assert.areEqual(
      'BRL',
      result[0].presentationCurrency,
      'Currency accompanies context'
    );
  }

  @IsTest
  static void shouldReturnEmptyListWhenNoRowsAreVisible() {
    AXF_CLS_AuthorizedContextService.contextsOverride = new List<Account>();
    AXF_CLS_AuthorizedContextService.currencyOverride = 'USD';

    Test.startTest();
    List<AXF_CLS_AuthorizedContextService.ContextView> result = AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    Test.stopTest();

    Assert.areEqual(
      0,
      result.size(),
      'No visible holder must disclose no context'
    );
  }

  @IsTest
  static void shouldQueryVisibleHolderWithUserMode() {
    Id businessTypeId = recordTypeId('AXF_Business');
    Account visibleBusiness = new Account(
      Name = 'Empresa visível AXF-3',
      RecordTypeId = businessTypeId
    );
    insert visibleBusiness;
    AXF_CLS_AuthorizedContextService.currencyOverride = 'BRL';

    Test.startTest();
    List<AXF_CLS_AuthorizedContextService.ContextView> result = AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    Test.stopTest();

    Assert.areEqual(1, result.size(), 'The visible holder must be listed');
    Assert.areEqual(
      visibleBusiness.Id,
      result[0].accountId,
      'The returned context must be the accessible Account'
    );
  }

  private static Id recordTypeId(String developerName) {
    Schema.RecordTypeInfo info = Account.SObjectType.getDescribe(
        SObjectDescribeOptions.DEFERRED
      )
      .getRecordTypeInfosByDeveloperName()
      .get(developerName);
    return info?.getRecordTypeId();
  }

  private static Id fakeAccountId(Integer sequence) {
    return Id.valueOf(
      '001000000000' + String.valueOf(sequence).leftPad(3, '0')
    );
  }

  private static Account contextRow(
    Id accountId,
    String name,
    String recordTypeName
  ) {
    return (Account) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{
          'attributes' => new Map<String, Object>{ 'type' => 'Account' },
          'Id' => accountId,
          'Name' => name,
          'IsPersonAccount' => recordTypeName == 'AXF_Person',
          'RecordType' => new Map<String, Object>{
            'DeveloperName' => recordTypeName
          }
        }
      ),
      Account.class
    );
  }
}
