/**
 * @description Personal report/presentation currency preference (AXF-87). This is a
 * PRESENTATION setting only: it never converts anything, never touches CurrencyIsoCode of a
 * fact, balance, history entry or accounting rate, and moves no money (AC3/AC5). Enabled
 * currencies come from AXF_ReportCurrency__mdt, so the org does not need multi-currency.
 *
 * Storage: AXF_ReportCurrencyPref__c hierarchy custom setting (per user; the org row is the
 * corporate default). getInstance() resolves user -> profile -> org.
 */
public with sharing class AXF_CLS_ReportCurrencyService {
  @TestVisible
  private static Boolean canConfigureOverride;

  @TestVisible
  private static List<AXF_ReportCurrency__mdt> currenciesOverride;

  public class CurrencyOption {
    @AuraEnabled
    public String isoCode;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean suggestedDefault;
  }

  private Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  /** @description Active presentation currencies, ordered with the suggested default first. */
  public List<CurrencyOption> activeCurrencies() {
    List<CurrencyOption> out = new List<CurrencyOption>();
    for (AXF_ReportCurrency__mdt c : source()) {
      if (c.AXF_RCU_BOL_Active__c != true) {
        continue;
      }
      CurrencyOption o = new CurrencyOption();
      o.isoCode = c.AXF_RCU_TXT_IsoCode__c;
      o.label = c.AXF_RCU_TXT_Label__c;
      o.suggestedDefault = c.AXF_RCU_BOL_SuggestedDefault__c == true;
      out.add(o);
    }
    out.sort(new BySuggestedThenIso());
    return out;
  }

  public String suggestedDefault() {
    for (CurrencyOption o : activeCurrencies()) {
      if (o.suggestedDefault) {
        return o.isoCode;
      }
    }
    return null;
  }

  /** @description The running user's effective preference (personal, else corporate). */
  public String effectivePreference() {
    AXF_ReportCurrencyPref__c pref = AXF_ReportCurrencyPref__c.getInstance();
    return (pref == null) ? null : normalize(pref.AXF_RCP_TXT_IsoCode__c);
  }

  /** @description Whether the running user has a PERSONAL preference (not inherited). */
  public Boolean hasPersonalPreference() {
    AXF_ReportCurrencyPref__c personal = AXF_ReportCurrencyPref__c.getValues(
      UserInfo.getUserId()
    );
    return personal != null &&
      String.isNotBlank(personal.AXF_RCP_TXT_IsoCode__c);
  }

  /**
   * @description Sets the running user's own preference. Rejects an inactive currency and,
   * unless `overwriteExisting`, refuses to silently replace a preference already set.
   */
  public void setForCurrentUser(String isoCode, Boolean overwriteExisting) {
    applyTo(UserInfo.getUserId(), isoCode, overwriteExisting == true, false);
  }

  /**
   * @description Admin path (AC2): sets another user's initial preference under
   * AXF_CanConfigure authority, never overwriting an existing choice without confirmation.
   * Profile and language are NOT accepted as proof of the desired currency — only isoCode.
   */
  public void setForUser(Id userId, String isoCode, Boolean overwriteExisting) {
    if (!callerCanConfigure()) {
      throw new AXF_CLS_ReportCurrencyException(
        'Voce nao tem autorizacao para definir a moeda de outro usuario.'
      );
    }
    if (userId == null || userId.getSobjectType() != User.SObjectType) {
      throw new AXF_CLS_ReportCurrencyException('Usuario invalido.');
    }
    applyTo(userId, isoCode, overwriteExisting == true, true);
  }

  private void applyTo(
    Id userId,
    String isoCode,
    Boolean overwriteExisting,
    Boolean adminPath
  ) {
    String iso = normalize(isoCode);
    if (String.isBlank(iso) || !activeIsoCodes().contains(iso)) {
      throw new AXF_CLS_ReportCurrencyException(
        'Moeda nao habilitada para apresentacao: ' + isoCode
      );
    }

    AXF_ReportCurrencyPref__c existing = AXF_ReportCurrencyPref__c.getValues(
      userId
    );
    Boolean alreadySet =
      existing != null && String.isNotBlank(existing.AXF_RCP_TXT_IsoCode__c);
    if (
      alreadySet &&
      !overwriteExisting &&
      !existing.AXF_RCP_TXT_IsoCode__c.equalsIgnoreCase(iso)
    ) {
      throw new AXF_CLS_ReportCurrencyException(
        'CONFIRM_REQUIRED: ja existe uma preferencia (' +
          existing.AXF_RCP_TXT_IsoCode__c +
          '). Confirme para substituir.'
      );
    }

    AXF_ReportCurrencyPref__c row = (existing != null &&
      existing.Id != null)
      ? existing
      : new AXF_ReportCurrencyPref__c(SetupOwnerId = userId);
    row.AXF_RCP_TXT_IsoCode__c = iso;
    Database.upsert(row, AccessLevel.SYSTEM_MODE);
  }

  private Set<String> activeIsoCodes() {
    Set<String> codes = new Set<String>();
    for (CurrencyOption o : activeCurrencies()) {
      codes.add(o.isoCode);
    }
    return codes;
  }

  private static List<AXF_ReportCurrency__mdt> source() {
    if (currenciesOverride != null) {
      return currenciesOverride;
    }
    return [
      SELECT
        AXF_RCU_TXT_IsoCode__c,
        AXF_RCU_TXT_Label__c,
        AXF_RCU_BOL_Active__c,
        AXF_RCU_BOL_SuggestedDefault__c
      FROM AXF_ReportCurrency__mdt
    ];
  }

  private static String normalize(String iso) {
    return String.isBlank(iso) ? null : iso.trim().toUpperCase();
  }

  private class BySuggestedThenIso implements Comparator<CurrencyOption> {
    public Integer compare(CurrencyOption a, CurrencyOption b) {
      if (a.suggestedDefault != b.suggestedDefault) {
        return a.suggestedDefault ? -1 : 1;
      }
      return a.isoCode.compareTo(b.isoCode);
    }
  }
}
