/**
 * @description AXF-87. Controller returns options + current + suggested; save surfaces the
 * confirm-required signal and the plain success/failure.
 */
@IsTest
private class AXF_CLS_CTRL_ReportCurrencyPrefTest {
  private static void seed() {
    AXF_CLS_ReportCurrencyService.currenciesOverride = new List<AXF_ReportCurrency__mdt>{
      new AXF_ReportCurrency__mdt(
        AXF_RCU_TXT_IsoCode__c = 'BRL',
        AXF_RCU_TXT_Label__c = 'Real',
        AXF_RCU_BOL_Active__c = true,
        AXF_RCU_BOL_SuggestedDefault__c = true
      ),
      new AXF_ReportCurrency__mdt(
        AXF_RCU_TXT_IsoCode__c = 'USD',
        AXF_RCU_TXT_Label__c = 'Dolar',
        AXF_RCU_BOL_Active__c = true,
        AXF_RCU_BOL_SuggestedDefault__c = false
      )
    };
  }

  @IsTest
  static void stateExposesOptionsAndSuggestion() {
    seed();
    AXF_CLS_CTRL_ReportCurrencyPref.StateDTO d = AXF_CLS_CTRL_ReportCurrencyPref.getState();
    System.assertEquals(2, d.options.size());
    System.assertEquals('BRL', d.suggestedIsoCode);
    System.assertEquals(false, d.hasPersonalPreference);
    System.assertEquals(null, d.currentIsoCode);
  }

  @IsTest
  static void setPreferenceSavesAndThenAsksToConfirm() {
    seed();
    AXF_CLS_CTRL_ReportCurrencyPref.SaveResultDTO first = AXF_CLS_CTRL_ReportCurrencyPref.setPreference(
      'BRL',
      false
    );
    System.assertEquals(true, first.applied);
    System.assertEquals('BRL', first.currentIsoCode);

    AXF_CLS_CTRL_ReportCurrencyPref.SaveResultDTO second = AXF_CLS_CTRL_ReportCurrencyPref.setPreference(
      'USD',
      false
    );
    System.assertEquals(false, second.applied);
    System.assertEquals(true, second.confirmRequired);

    AXF_CLS_CTRL_ReportCurrencyPref.SaveResultDTO confirmed = AXF_CLS_CTRL_ReportCurrencyPref.setPreference(
      'USD',
      true
    );
    System.assertEquals(true, confirmed.applied);
    System.assertEquals('USD', confirmed.currentIsoCode);
  }

  @IsTest
  static void setPreferenceRejectsInactive() {
    seed();
    AXF_CLS_CTRL_ReportCurrencyPref.SaveResultDTO r = AXF_CLS_CTRL_ReportCurrencyPref.setPreference(
      'JPY',
      false
    );
    System.assertEquals(false, r.applied);
    System.assertEquals(false, r.confirmRequired == true);
    System.assert(r.message.containsIgnoreCase('nao habilitada'));
  }
}
