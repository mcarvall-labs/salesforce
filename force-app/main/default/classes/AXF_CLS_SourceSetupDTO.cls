/**
 * @description DTOs returned to the onboarding wizard source steps (Pluggy discovery,
 * holder confirmation and manual sources) over the legacy PROD data model
 * (AXF_OBJ_PluggyConnection__c, AXF_OBJ_BankAccount__c, AXF_OBJ_CreditCard__c).
 *
 * Member names are the exact JSON contract read by aXF_LWC_sourceDiscovery,
 * aXF_LWC_confirmSourceHolders, aXF_LWC_manualFinancialSource and
 * aXF_LWC_onboardingWizard. Concepts the legacy model does not have (custody,
 * record version, holder divergence) are returned as neutral values by the services.
 */
public with sharing class AXF_CLS_SourceSetupDTO {
  /** @description Outcome of a discovery run (or the last known state) of one connection. */
  public class DiscoveryResult {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public String state; // SUCCEEDED | RUNNING | FAILED_RETRYABLE | FAILED_TERMINAL | null
    @AuraEnabled
    public Integer accountsFound = 0;
    @AuraEnabled
    public Integer cardsFound = 0;
    @AuraEnabled
    public Boolean complete = false;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer applied = 0;
    @AuraEnabled
    public Integer released = 0;
    @AuraEnabled
    public Integer pending = 0;
    @AuraEnabled
    public Integer divergent = 0;
    @AuraEnabled
    public Integer bankDivergent = 0;
    @AuraEnabled
    public Integer conflicts = 0;
    @AuraEnabled
    public Integer failed = 0;
  }

  /** @description A bank account or credit card linked to a Pluggy connection. */
  public class DiscoveredSource {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String kind; // BANK | CARD
    @AuraEnabled
    public String institution;
    @AuraEnabled
    public String bankInstitutionName;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public String availability; // AVAILABLE (holder linked) | CUSTODY (no holder yet)
    @AuraEnabled
    public Boolean hasHolder = false;
  }

  /** @description One registered Pluggy connection, as listed by the wizard. */
  public class ConnectionOverview {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public String itemIdHint;
    @AuraEnabled
    public String institution;
    @AuraEnabled
    public String consentState; // ACTIVE | STALE | REVOKED | null
    @AuraEnabled
    public String runState;
    @AuraEnabled
    public Integer accountsFound = 0;
    @AuraEnabled
    public Integer cardsFound = 0;
    @AuraEnabled
    public Boolean discovered = false;
    @AuraEnabled
    public Id bankInstitutionId;
    @AuraEnabled
    public String bankInstitutionName;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderName;
  }

  public class RegisterResult {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public String institution;
    @AuraEnabled
    public Boolean created = false;
    @AuraEnabled
    public String message;
  }

  public class UpdateReferencesResult {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public Id bankInstitutionId;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
  }

  public class DeleteResult {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public String outcome; // DELETED | BLOCKED | NOT_FOUND
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer accounts = 0;
    @AuraEnabled
    public Integer cards = 0;
  }

  public class BankInstitutionResult {
    @AuraEnabled
    public Id institutionId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String bankNumber;
    @AuraEnabled
    public String outcome; // CREATED | ALREADY | INVALID | FORBIDDEN | FAILED
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<String> invalidFields = new List<String>();
  }

  /** @description A source row of the "Confirmar titulares" step. */
  public class SourceView {
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String kind; // BANK | CARD
    @AuraEnabled
    public String institutionName;
    @AuraEnabled
    public String bankInstitutionName;
    @AuraEnabled
    public String maskedNumber;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public String availabilityState;
    @AuraEnabled
    public Integer version = 0;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderName;
    @AuraEnabled
    public Id accountHolderId;
    @AuraEnabled
    public Boolean divergent = false;
  }

  public class HolderOverview {
    @AuraEnabled
    public Boolean forbidden = false;
    @AuraEnabled
    public List<SourceView> pending = new List<SourceView>();
    @AuraEnabled
    public List<SourceView> released = new List<SourceView>();
    @AuraEnabled
    public List<SourceView> divergent = new List<SourceView>();
  }

  public class ConfirmResult {
    @AuraEnabled
    public String outcome; // CONFIRMED | ALREADY | CORRECTED | FORBIDDEN | INVALID | NOT_FOUND | FAILED
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public Id accountHolderId;
    @AuraEnabled
    public Integer version = 0;
    @AuraEnabled
    public String availabilityState;
    @AuraEnabled
    public List<String> invalidFields = new List<String>();
  }

  public class ManualSaveResult {
    @AuraEnabled
    public String outcome; // CREATED | ALREADY | UPDATED | CONFLICT | FORBIDDEN | INVALID | FAILED
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public Id accountHolderId;
    @AuraEnabled
    public Integer version = 0;
    @AuraEnabled
    public List<String> invalidFields = new List<String>();
  }
}
