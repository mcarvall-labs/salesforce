/**
 * @description Tests for AXF_CLS_CTRL_Holder — thin controller over ALT_CLS_AxonHolder. AXF-80.
 */
@IsTest(isParallel=false)
private class AXF_CLS_CTRL_HolderTest {
  private static void authorize() {
    AXF_CLS_CTRL_Holder.canConfigureOverride = true;
    ALT_CLS_AxonHolder.canConfigureOverride = true;
  }

  @IsTest
  static void canConfigureReflectsOverride() {
    AXF_CLS_CTRL_Holder.canConfigureOverride = false;
    System.assertEquals(false, AXF_CLS_CTRL_Holder.canConfigure());
    AXF_CLS_CTRL_Holder.canConfigureOverride = true;
    System.assertEquals(true, AXF_CLS_CTRL_Holder.canConfigure());
  }

  @IsTest
  static void createListAndGetRoundTrip() {
    authorize();

    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'PERSON';
    si.firstName = 'Fabio';
    si.lastName = 'Gomes';

    Test.startTest();
    ALT_CLS_AxonHolder.SaveResult saved = AXF_CLS_CTRL_Holder.saveHolder(si);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', saved.outcome, saved.message);

    List<ALT_CLS_AxonHolder.HolderView> rows = AXF_CLS_CTRL_Holder.listHolders('Gomes');
    System.assertEquals(1, rows.size());

    ALT_CLS_AxonHolder.HolderView v = AXF_CLS_CTRL_Holder.getHolder(saved.accountId);
    System.assertEquals('PERSON', v.type);
    System.assertEquals('Gomes', v.lastName);
  }

  @IsTest
  static void saveHolderForbiddenWithoutAuthority() {
    AXF_CLS_CTRL_Holder.canConfigureOverride = false;
    ALT_CLS_AxonHolder.canConfigureOverride = false;

    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'BUSINESS';
    si.name = 'Bloqueada SA';

    ALT_CLS_AxonHolder.SaveResult r = AXF_CLS_CTRL_Holder.saveHolder(si);
    System.assertEquals('FORBIDDEN', r.outcome);
  }

  @IsTest
  static void getHolderReturnsNullForMissing() {
    authorize();
    System.assertEquals(null, AXF_CLS_CTRL_Holder.getHolder(null));
  }
}
