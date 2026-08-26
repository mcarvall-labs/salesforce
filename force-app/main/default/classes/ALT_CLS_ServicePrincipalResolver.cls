public without sharing class ALT_CLS_ServicePrincipalResolver {
  @TestVisible
  private static Id testPrincipalId;
  public User resolve() {
    String federationIdentifier;
    if (Test.isRunningTest() && testPrincipalId != null)
      federationIdentifier = [
        SELECT FederationIdentifier
        FROM User
        WHERE Id = :testPrincipalId
      ]
      .FederationIdentifier;
    else {
      List<SObject> policies = Database.query(
        'SELECT FederationIdentifier__c FROM AXF_ServicePrincipalPolicy__mdt WHERE Active__c = true AND PolicyVersion__c = \'AXF-SERVICE-PRINCIPAL@1.0.0\' LIMIT 2'
      );
      if (policies.size() != 1)
        throw new ServicePrincipalException('SERVICE_PRINCIPAL_UNAVAILABLE');
      federationIdentifier = (String) policies[0]
        .get('FederationIdentifier__c');
    }
    if (String.isBlank(federationIdentifier))
      throw new ServicePrincipalException('SERVICE_PRINCIPAL_UNAVAILABLE');
    List<User> users = [
      SELECT Id, FederationIdentifier
      FROM User
      WHERE IsActive = TRUE AND FederationIdentifier = :federationIdentifier
      LIMIT 2
    ];
    if (users.size() != 1)
      throw new ServicePrincipalException('SERVICE_PRINCIPAL_UNAVAILABLE');
    List<PermissionSetAssignment> assignments = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :users[0].Id
        AND PermissionSet.Name = 'AXF_PS_SecurityProjector'
      LIMIT 1
    ];
    if (assignments.isEmpty())
      throw new ServicePrincipalException('SERVICE_PRINCIPAL_UNAVAILABLE');
    return users[0];
  }
  public class ServicePrincipalException extends Exception {
  }
}
