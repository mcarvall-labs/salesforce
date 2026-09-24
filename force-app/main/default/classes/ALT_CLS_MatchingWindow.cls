/**
 * @description AXF-MATCHING@1.1.0 consultative suggestion window (addendum ratified 2026-09-23 for
 * AXF-151..154), shared by every screen that suggests a counterpart: a candidate is inside the
 * window when |Δamount| ≤ 5% of the base amount and |Δdate| ≤ 7 calendar days. The presentation
 * order is the smaller |Δamount|, then the smaller |Δdate|, then the record id; it is never a score
 * and never selects a winner — equal distances on both axes are flagged as an explicit tie.
 */
public with sharing class ALT_CLS_MatchingWindow {
  public static final String POLICY = 'AXF-MATCHING@1.1.0';
  /** |Δamount| ≤ 5% of the base (source) amount. */
  public static final Decimal AMOUNT_TOLERANCE = 0.05;
  /** |Δdate| ≤ 7 calendar days. */
  public static final Integer DAY_WINDOW = 7;

  /** @description True when the other side is inside the window around the base side. */
  public static Boolean inWindow(
    Decimal baseAmount,
    Date baseDate,
    Decimal otherAmount,
    Date otherDate
  ) {
    if (
      baseAmount == null ||
      baseAmount <= 0 ||
      otherAmount == null ||
      baseDate == null ||
      otherDate == null
    ) {
      return false;
    }
    return (otherAmount - baseAmount).abs() <= baseAmount * AMOUNT_TOLERANCE &&
      Math.abs(baseDate.daysBetween(otherDate)) <= DAY_WINDOW;
  }

  /** @description Lowest amount a query may bound the window with (inclusive). */
  public static Decimal minAmount(Decimal baseAmount) {
    return baseAmount - baseAmount * AMOUNT_TOLERANCE;
  }

  /** @description Highest amount a query may bound the window with (inclusive). */
  public static Decimal maxAmount(Decimal baseAmount) {
    return baseAmount + baseAmount * AMOUNT_TOLERANCE;
  }

  /** One presented candidate: its distances, its id and whatever view the caller shows. */
  public class Ranked {
    public Decimal amountDelta;
    public Integer dayDelta;
    public String recordId;
    public Object item;
    public Boolean tied = false;

    public Ranked(
      Decimal amountDelta,
      Integer dayDelta,
      String recordId,
      Object item
    ) {
      this.amountDelta = amountDelta;
      this.dayDelta = dayDelta;
      this.recordId = recordId;
      this.item = item;
    }

    public String signature() {
      return String.valueOf(amountDelta) + '|' + dayDelta;
    }
  }

  /**
   * @description Sorts in the presentation order and flags ties (same distance on both axes). The
   * input list is not changed; the returned list holds the same entries.
   */
  public static List<Ranked> order(List<Ranked> candidates) {
    List<RankKey> keys = new List<RankKey>();
    Map<String, Integer> signatures = new Map<String, Integer>();
    for (Ranked candidate : candidates) {
      keys.add(new RankKey(candidate));
      String signature = candidate.signature();
      signatures.put(
        signature,
        (signatures.containsKey(signature) ? signatures.get(signature) : 0) + 1
      );
    }
    keys.sort();
    List<Ranked> result = new List<Ranked>();
    for (RankKey key : keys) {
      key.entry.tied = signatures.get(key.entry.signature()) > 1;
      result.add(key.entry);
    }
    return result;
  }

  private class RankKey implements Comparable {
    public Ranked entry;
    public RankKey(Ranked entry) {
      this.entry = entry;
    }
    public Integer compareTo(Object other) {
      Ranked b = ((RankKey) other).entry;
      if (entry.amountDelta != b.amountDelta) {
        return entry.amountDelta < b.amountDelta ? -1 : 1;
      }
      if (entry.dayDelta != b.dayDelta) {
        return entry.dayDelta < b.dayDelta ? -1 : 1;
      }
      return String.valueOf(entry.recordId)
        .compareTo(String.valueOf(b.recordId));
    }
  }
}
