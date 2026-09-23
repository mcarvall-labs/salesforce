/**
 * @description AXF-153: the shared AXF-MATCHING@1.1.0 window (±5% amount, ±7 days) and its
 * presentation order (|Δamount|, |Δdate|, record id) with explicit ties.
 */
@IsTest
private class ALT_CLS_MatchingWindowTest {
  @IsTest
  static void windowBoundsAreInclusiveAndRejectMissingEvidence() {
    Date base = Date.newInstance(2026, 9, 10);
    Assert.isTrue(ALT_CLS_MatchingWindow.inWindow(100, base, 105, base));
    Assert.isTrue(ALT_CLS_MatchingWindow.inWindow(100, base, 95, base));
    Assert.isTrue(
      ALT_CLS_MatchingWindow.inWindow(100, base, 100, base.addDays(7))
    );
    Assert.isTrue(
      ALT_CLS_MatchingWindow.inWindow(100, base, 100, base.addDays(-7))
    );
    Assert.isFalse(ALT_CLS_MatchingWindow.inWindow(100, base, 105.01, base));
    Assert.isFalse(
      ALT_CLS_MatchingWindow.inWindow(100, base, 100, base.addDays(8))
    );
    Assert.isFalse(ALT_CLS_MatchingWindow.inWindow(null, base, 100, base));
    Assert.isFalse(ALT_CLS_MatchingWindow.inWindow(0, base, 0, base));
    Assert.isFalse(ALT_CLS_MatchingWindow.inWindow(100, null, 100, base));
    Assert.isFalse(ALT_CLS_MatchingWindow.inWindow(100, base, null, base));
    Assert.areEqual(95, ALT_CLS_MatchingWindow.minAmount(100));
    Assert.areEqual(105, ALT_CLS_MatchingWindow.maxAmount(100));
    Assert.areEqual('AXF-MATCHING@1.1.0', ALT_CLS_MatchingWindow.POLICY);
  }

  @IsTest
  static void ordersByAmountThenDaysThenIdAndFlagsTies() {
    List<ALT_CLS_MatchingWindow.Ranked> input = new List<ALT_CLS_MatchingWindow.Ranked>{
      new ALT_CLS_MatchingWindow.Ranked(4, 1, 'c', 'C'),
      new ALT_CLS_MatchingWindow.Ranked(1, 6, 'b', 'B'),
      new ALT_CLS_MatchingWindow.Ranked(1, 2, 'z', 'Z'),
      new ALT_CLS_MatchingWindow.Ranked(1, 2, 'a', 'A')
    };
    List<ALT_CLS_MatchingWindow.Ranked> ordered = ALT_CLS_MatchingWindow.order(
      input
    );
    List<Object> items = new List<Object>();
    for (ALT_CLS_MatchingWindow.Ranked entry : ordered) {
      items.add(entry.item);
    }
    Assert.areEqual(new List<Object>{ 'A', 'Z', 'B', 'C' }, items);
    Assert.isTrue(ordered[0].tied, 'same distances stay an explicit tie');
    Assert.isTrue(ordered[1].tied);
    Assert.isFalse(ordered[2].tied);
    Assert.isFalse(ordered[3].tied);
    Assert.areEqual(
      0,
      ALT_CLS_MatchingWindow.order(new List<ALT_CLS_MatchingWindow.Ranked>())
        .size()
    );
  }
}
