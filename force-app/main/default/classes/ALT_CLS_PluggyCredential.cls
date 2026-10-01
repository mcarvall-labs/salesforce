/**
 * @description Stores the Pluggy Client Id / Client Secret in the native External Credential
 * principal and checks them against the Pluggy auth endpoint. Secrets are forwarded to the
 * platform vault and never persisted, logged or returned. The running user needs
 * "Manage Named Credentials" to save and principal access on AXF_EXC_Pluggy to test.
 */
public with sharing class ALT_CLS_PluggyCredential {
  public class Result {
    public Boolean success = false;
    public String message;
  }

  private static final String EXTERNAL_CREDENTIAL = 'AXF_EXC_Pluggy';
  private static final String PRINCIPAL = 'AXF_Pluggy_Principal';
  private static final String AUTH_ENDPOINT = 'callout:AXF_NC_Pluggy_API/auth';

  public interface Vault {
    Boolean exists();
    void write(ConnectApi.CredentialInput input);
  }

  private class NativeVault implements Vault {
    public Boolean exists() {
      try {
        ConnectApi.NamedCredentials.getCredential(
          EXTERNAL_CREDENTIAL,
          PRINCIPAL,
          ConnectApi.CredentialPrincipalType.NamedPrincipal
        );
        return true;
      } catch (ConnectApi.ConnectApiException e) {
        return false;
      }
    }

    public void write(ConnectApi.CredentialInput input) {
      try {
        ConnectApi.NamedCredentials.updateCredential(input);
      } catch (ConnectApi.ConnectApiException e) {
        // A principal never created yet has nothing to update; create it instead.
        ConnectApi.NamedCredentials.createCredential(input);
      }
    }
  }

  @TestVisible
  private static Vault vaultForTests;

  private final Vault vault = vaultForTests != null
    ? vaultForTests
    : new NativeVault();

  public Boolean hasCredentials() {
    return vault.exists();
  }

  public Result save(String clientId, String clientSecret) {
    Result r = new Result();
    if (String.isBlank(clientId) || String.isBlank(clientSecret)) {
      r.message = 'Informe o Client Id e o Client Secret.';
      return r;
    }
    try {
      ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
      input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.CUSTOM;
      input.externalCredential = EXTERNAL_CREDENTIAL;
      input.principalName = PRINCIPAL;
      input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
      input.credentials = new Map<String, ConnectApi.CredentialValueInput>{
        'clientId' => valueInput(clientId, false),
        'clientSecret' => valueInput(clientSecret, true)
      };
      vault.write(input);
      r.success = true;
      r.message = 'Credenciais salvas.';
    } catch (Exception e) {
      r.message =
        'Não foi possível salvar as credenciais (' +
        e.getTypeName() +
        '). Confirme a permissão "Manage Named Credentials".';
    }
    return r;
  }

  public Result testAuthentication() {
    Result r = new Result();
    HttpRequest req = new HttpRequest();
    req.setEndpoint(AUTH_ENDPOINT);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setBody(
      '{"clientId":"{!$Credential.' +
        EXTERNAL_CREDENTIAL +
        '.clientId}","clientSecret":"{!$Credential.' +
        EXTERNAL_CREDENTIAL +
        '.clientSecret}"}'
    );
    try {
      HttpResponse res = new Http().send(req);
      if (res.getStatusCode() == 200 && hasApiKey(res.getBody())) {
        r.success = true;
        r.message = 'Autenticação com o Pluggy realizada com sucesso.';
      } else if (res.getStatusCode() == 401 || res.getStatusCode() == 403) {
        r.message = 'Client Id ou Client Secret inválidos no Pluggy.';
      } else {
        r.message =
          'O Pluggy respondeu com erro (HTTP ' +
          res.getStatusCode() +
          ').';
      }
    } catch (Exception e) {
      r.message =
        'Não foi possível contatar o Pluggy (' +
        e.getTypeName() +
        '). Confirme o acesso à credencial AXF_EXC_Pluggy.';
    }
    return r;
  }

  private Boolean hasApiKey(String body) {
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      body
    );
    return String.isNotBlank((String) parsed.get('apiKey'));
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
