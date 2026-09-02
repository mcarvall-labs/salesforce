/**
 * @description AXF-87. Preference is presentation-only, persisted per user, resumed across
 * sessions; an inactive currency is rejected; an existing choice is not silently replaced;
 * the admin path is authority-gated.
 */
@IsTest
private class AXF_CLS_ReportCurrencyServiceTest {
  private static void seedCurrencies() {
    AXF_CLS_ReportCurrencyService.currenciesOverride = new List<AXF_ReportCurrency__mdt>{
      row('BRL', 'Real', true, true),
      row('USD', 'Dolar', true, false),
      row('JPY', 'Iene', false, false)
    };
  }

  private static AXF_ReportCurrency__mdt row(
    String iso,
    String label,
    Boolean active,
    Boolean suggested
  ) {
    return new AXF_ReportCurrency__mdt(
      AXF_RCU_TXT_IsoCode__c = iso,
      AXF_RCU_TXT_Label__c = label,
      AXF_RCU_BOL_Active__c = active,
      AXF_RCU_BOL_SuggestedDefault__c = suggested
    );
  }

  @IsTest
  static void activeCurrenciesExcludeInactiveAndSuggestedIsFirst() {
    seedCurrencies();
    List<AXF_CLS_ReportCurrencyService.CurrencyOption> opts = new AXF_CLS_ReportCurrencyService()
      .activeCurrencies();
    System.assertEquals(2, opts.size(), 'JPY inactive excluded');
    System.assertEquals('BRL', opts[0].isoCode, 'suggested first');
    System.assertEquals(
      'BRL',
      new AXF_CLS_ReportCurrencyService().suggestedDefault()
    );
  }

  @IsTest
  static void setAndResumePersonalPreference() {
    seedCurrencies();
    AXF_CLS_ReportCurrencyService svc = new AXF_CLS_ReportCurrencyService();

    System.assertEquals(false, svc.hasPersonalPreference());
    svc.setForCurrentUser('usd', false);

    // a fresh service instance re-reads the custom setting (resume across sessions)
    AXF_CLS_ReportCurrencyService fresh = new AXF_CLS_ReportCurrencyService();
    System.assertEquals('USD', fresh.effectivePreference());
    System.assertEquals(true, fresh.hasPersonalPreference());
  }

  @IsTest
  static void nonAdminCanPersistOwnHierarchySettingRow() {
    seedCurrencies();
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE UserType = 'Standard'
      LIMIT 1
    ];
    User participant = new User(
      Alias = 'axfpart',
      Email = 'axf87-participant@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AXF87 Participant',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      ProfileId = standardProfile.Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axf87-participant-' +
        System.now().getTime() +
        '@example.invalid'
    );
    insert participant;

    System.runAs(participant) {
      AXF_CLS_ReportCurrencyService service = new AXF_CLS_ReportCurrencyService();
      service.setForCurrentUser('USD', false);

      AXF_ReportCurrencyPref__c stored = AXF_ReportCurrencyPref__c.getValues(
        UserInfo.getUserId()
      );
      System.assertNotEquals(null, stored, 'personal hierarchy row must exist');
      System.assertEquals('USD', stored.AXF_RCP_TXT_IsoCode__c);
      System.assertEquals('USD', service.effectivePreference());
    }
  }

  @IsTest
  static void inactiveCurrencyIsRejected() {
    seedCurrencies();
    try {
      new AXF_CLS_ReportCurrencyService().setForCurrentUser('JPY', false);
      System.assert(false, 'inactive currency must be rejected');
    } catch (AXF_CLS_ReportCurrencyException e) {
      System.assert(e.getMessage().containsIgnoreCase('nao habilitada'));
    }
  }

  @IsTest
  static void existingPreferenceNotSilentlyReplaced() {
    seedCurrencies();
    AXF_CLS_ReportCurrencyService svc = new AXF_CLS_ReportCurrencyService();
    svc.setForCurrentUser('BRL', false);

    try {
      svc.setForCurrentUser('USD', false);
      System.assert(false, 'must ask for confirmation');
    } catch (AXF_CLS_ReportCurrencyException e) {
      System.assert(e.getMessage().startsWith('CONFIRM_REQUIRED'));
    }

    svc.setForCurrentUser('USD', true); // confirmed
    System.assertEquals('USD', svc.effectivePreference());
  }

  @IsTest
  static void resettingToSameValueIsNoOp() {
    seedCurrencies();
    AXF_CLS_ReportCurrencyService svc = new AXF_CLS_ReportCurrencyService();
    svc.setForCurrentUser('BRL', false);
    svc.setForCurrentUser('brl', false); // same value, no confirm needed
    System.assertEquals('BRL', svc.effectivePreference());
  }

  @IsTest
  static void adminPathRequiresAuthority() {
    seedCurrencies();
    AXF_CLS_ReportCurrencyService.canConfigureOverride = false;
    try {
      new AXF_CLS_ReportCurrencyService()
        .setForUser(UserInfo.getUserId(), 'USD', false);
      System.assert(false, 'unauthorized admin set must fail');
    } catch (AXF_CLS_ReportCurrencyException e) {
      System.assert(e.getMessage().containsIgnoreCase('autoriza'));
    }
  }

  @IsTest
  static void adminPathSetsInitialPreference() {
    seedCurrencies();
    AXF_CLS_ReportCurrencyService.canConfigureOverride = true;
    AXF_CLS_ReportCurrencyService svc = new AXF_CLS_ReportCurrencyService();
    svc.setForUser(UserInfo.getUserId(), 'USD', false);
    System.assertEquals('USD', svc.effectivePreference());
  }

  @IsTest
  static void adminPathRejectsInvalidUser() {
    seedCurrencies();
    AXF_CLS_ReportCurrencyService.canConfigureOverride = true;
    try {
      new AXF_CLS_ReportCurrencyService().setForUser(null, 'USD', false);
      System.assert(false, 'null user must fail');
    } catch (AXF_CLS_ReportCurrencyException e) {
      // expected
    }
  }
}
