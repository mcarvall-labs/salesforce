/**
 * @description Forwards a Client ID / Client Secret straight into a Pluggy External
 * Credential's Named Principal via the native ConnectApi, then discards them. AXF-11 AC1:
 * "os segredos são encaminhados apenas ao mecanismo nativo seguro aprovado de
 * Named/External Credentials". The values are never persisted, logged, returned or placed
 * on any object.
 *
 * The running user needs "Manage Named Credentials" (or Customize Application) — in the
 * Axon model this operation is performed by a System Administrator (the org configurator),
 * so no broad permission is added to any Axon permission set.
 *
 * NOTE: the ConnectApi write itself is skipped under Test.isRunningTest() and must be
 * smoke-tested against a live org before first real use.
 */
public with sharing class AXF_CLS_PluggyCredentialWriter {
  public class Result {
    @AuraEnabled
    public Boolean applied = false;
    @AuraEnabled
    public String message;
  }

  @TestVisible
  private static String lastExternalCredentialForTests;
  @TestVisible
  private static String lastPrincipalForTests;
  @TestVisible
  private static Boolean lastHadSecretForTests;

  /**
   * @description Populates `clientId` / `clientSecret` on `principalName` of
   * `externalCredential`. Returns a sanitized Result; never echoes the values.
   */
  public Result write(
    String externalCredential,
    String principalName,
    String clientId,
    String clientSecret
  ) {
    Result r = new Result();
    if (String.isBlank(clientId) || String.isBlank(clientSecret)) {
      r.message = 'Informe o Client ID e o Client Secret.';
      return r;
    }
    lastExternalCredentialForTests = externalCredential;
    lastPrincipalForTests = principalName;
    lastHadSecretForTests = String.isNotBlank(clientSecret);

    try {
      ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
      input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.CUSTOM;
      input.externalCredential = externalCredential;
      input.principalName = principalName;
      input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;

      Map<String, ConnectApi.CredentialValueInput> values = new Map<String, ConnectApi.CredentialValueInput>();
      values.put('clientId', valueInput(clientId, false));
      values.put('clientSecret', valueInput(clientSecret, true));
      input.credentials = values;

      applyToNativeMechanism(input);

      r.applied = true;
      r.message = 'Credencial encaminhada ao mecanismo nativo de Credenciais Externas.';
    } catch (Exception e) {
      // Sanitized: never surface the values or a raw stack trace.
      r.message =
        'Nao foi possivel salvar a credencial (' +
        e.getTypeName() +
        '). Verifique a permissao "Manage Named Credentials" e o nome do principal.';
    }
    return r;
  }

  private void applyToNativeMechanism(ConnectApi.CredentialInput input) {
    if (Test.isRunningTest()) {
      return; // ConnectApi.NamedCredentials.* is not callable in test context
    }
    try {
      ConnectApi.NamedCredentials.updateCredential(input);
    } catch (ConnectApi.NotFoundException notThere) {
      ConnectApi.NamedCredentials.createCredential(input);
    }
  }

  private ConnectApi.CredentialValueInput valueInput(
    String value,
    Boolean encrypted
  ) {
    ConnectApi.CredentialValueInput v = new ConnectApi.CredentialValueInput();
    v.value = value;
    v.encrypted = encrypted;
    return v;
  }
}
