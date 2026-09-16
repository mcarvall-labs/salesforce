/**
 * @description AXF-139: observable, independent evidence for reconciliation candidates under
 * AXF-MATCHING@1.0.0. Pure and deterministic — no SOQL, no DML. Every feature is reported as
 * an independent fact with a relation and an explanation code; there is no weight, no score,
 * no tolerance and no automatic selection. Missing evidence is UNKNOWN, never a negative
 * signal. Ordering is presentation only: verified external identity, exact source identity,
 * type rank (persisted before virtual), then record identity.
 */
public inherited sharing class ALT_CLS_MatchEvidence {
  public static final String MATCHING_POLICY = 'AXF-MATCHING@1.0.0';
  public static final String STATE_CONSULTATIVE = 'CONSULTATIVE';
  /** AXF-140, policy §3: a non-zero residual stays PARTIAL — no approved tolerance zeroes it. */
  public static final String STATE_PARTIAL = 'PARTIAL';
  /** AXF-140, policy §3: material evidence is missing (no approved tolerance or default covers it). */
  public static final String STATE_BLOCKED = 'BLOCKED';
  public static final String REL_EXACT = 'EXACT';
  public static final String REL_CONTAINS = 'CONTAINS';
  public static final String REL_COVERS = 'COVERS';
  public static final String REL_PARTIAL = 'PARTIAL';
  public static final String REL_DIFFERENT = 'DIFFERENT';
  public static final String REL_UNKNOWN = 'UNKNOWN';
  public static final String REL_REDACTED = 'REDACTED';
  /** Shortest normalized text that may count as CONTAINS; shorter tokens are DIFFERENT. */
  public static final Integer MIN_CONTAINS_LENGTH = 3;
  /** Feature order is fixed so the UI and the tie detection read the same sequence. */
  public static final List<String> FEATURES = new List<String>{
    'EXTERNAL_IDENTITY',
    'SOURCE_IDENTITY',
    'HOLDER',
    'CURRENCY',
    'AMOUNT',
    'RESIDUAL',
    'DATE',
    'DESCRIPTION',
    'CATEGORY'
  };

  public class EvidenceView {
    @AuraEnabled
    public String feature;
    @AuraEnabled
    public String relation;
    @AuraEnabled
    public String sourceValue;
    @AuraEnabled
    public String candidateValue;
    /** Signed detail for the relation (days between dates, amount difference), null when not applicable. */
    @AuraEnabled
    public Decimal delta;
    /** Explanation code (feature_RELATION, DATE_AFTER/BEFORE, *_CONTAINS_CANDIDATE, *_CONTAINED_IN_CANDIDATE); the UI maps it to a label. */
    @AuraEnabled
    public String explanation;
  }

  /** Minimal, authorization-safe view of the two sides; callers redact before handing values in. */
  public class Side {
    public String externalIdentity;
    public Id sourceIdentity;
    public Id holderId;
    public String currencyIso;
    public Decimal amount;
    public Decimal residual;
    public Date onDate;
    public String description;
    public String category;
    public Boolean descriptionRedacted = false;
    public Boolean categoryRedacted = false;
    /**
     * Evidence the caller is not authorized for and therefore withholds: it is not displayed and
     * cannot order. It is an authorization fact on the side that carries the evidence, never a
     * consequence of the value being absent — absence is UNKNOWN.
     */
    public Boolean externalIdentityRedacted = false;
  }

  /** @description Evaluates every feature independently; the result never ranks the candidate. */
  public static List<EvidenceView> evaluate(Side source, Side candidate) {
    if (source == null || candidate == null) {
      throw new IllegalArgumentException('both sides are required');
    }
    List<EvidenceView> result = new List<EvidenceView>();
    result.add(
      identity(
        'EXTERNAL_IDENTITY',
        source.externalIdentity,
        candidate.externalIdentity,
        source.externalIdentityRedacted || candidate.externalIdentityRedacted
      )
    );
    result.add(
      identity(
        'SOURCE_IDENTITY',
        source.sourceIdentity == null
          ? null
          : String.valueOf(source.sourceIdentity),
        candidate.sourceIdentity == null
          ? null
          : String.valueOf(candidate.sourceIdentity)
      )
    );
    result.add(
      identity(
        'HOLDER',
        source.holderId == null ? null : String.valueOf(source.holderId),
        candidate.holderId == null ? null : String.valueOf(candidate.holderId)
      )
    );
    result.add(identity('CURRENCY', source.currencyIso, candidate.currencyIso));
    result.add(amount(source, candidate));
    result.add(residual(source, candidate));
    result.add(dates(source, candidate));
    result.add(
      text(
        'DESCRIPTION',
        source.description,
        candidate.description,
        source.descriptionRedacted || candidate.descriptionRedacted
      )
    );
    result.add(
      text(
        'CATEGORY',
        source.category,
        candidate.category,
        source.categoryRedacted || candidate.categoryRedacted
      )
    );
    return result;
  }

  private static EvidenceView identity(
    String feature,
    String left,
    String right
  ) {
    return identity(feature, left, right, false);
  }

  /**
   * Withheld evidence is redacted: no value travels and the relation is never EXACT, so it cannot
   * contribute to the presentation order (policy §2 — redaction is not a partial signal).
   */
  private static EvidenceView identity(
    String feature,
    String left,
    String right,
    Boolean redacted
  ) {
    EvidenceView v = new EvidenceView();
    v.feature = feature;
    if (redacted) {
      v.relation = REL_REDACTED;
      v.explanation = feature + '_REDACTED';
      return v;
    }
    v.sourceValue = left;
    v.candidateValue = right;
    if (String.isBlank(left) || String.isBlank(right)) {
      // Unknown on either side: no value travels, nothing to compare or disclose.
      v.sourceValue = null;
      v.candidateValue = null;
      v.relation = REL_UNKNOWN;
      v.explanation = feature + '_UNKNOWN';
    } else if (left.equals(right)) {
      v.relation = REL_EXACT;
      v.explanation = feature + '_EXACT';
    } else {
      v.relation = REL_DIFFERENT;
      v.explanation = feature + '_DIFFERENT';
    }
    return v;
  }

  private static EvidenceView amount(Side source, Side candidate) {
    EvidenceView v = new EvidenceView();
    v.feature = 'AMOUNT';
    v.sourceValue = plain(source.amount);
    v.candidateValue = plain(candidate.amount);
    if (source.amount == null || candidate.amount == null) {
      v.relation = REL_UNKNOWN;
      v.explanation = 'AMOUNT_UNKNOWN';
      return v;
    }
    v.delta = candidate.amount - source.amount;
    if (v.delta == 0) {
      v.relation = REL_EXACT;
      v.explanation = 'AMOUNT_EXACT';
    } else {
      v.relation = REL_DIFFERENT;
      v.explanation = 'AMOUNT_DIFFERENT';
    }
    return v;
  }

  /** Coverage is exact arithmetic on remaining amounts: would the source extinguish the candidate? */
  private static EvidenceView residual(Side source, Side candidate) {
    EvidenceView v = new EvidenceView();
    v.feature = 'RESIDUAL';
    v.sourceValue = plain(source.residual);
    v.candidateValue = plain(candidate.residual);
    if (source.residual == null || candidate.residual == null) {
      v.relation = REL_UNKNOWN;
      v.explanation = 'RESIDUAL_UNKNOWN';
      return v;
    }
    v.delta = candidate.residual - source.residual;
    if (v.delta == 0) {
      v.relation = REL_EXACT;
      v.explanation = 'RESIDUAL_EXACT';
    } else if (v.delta < 0) {
      v.relation = REL_COVERS;
      v.explanation = 'RESIDUAL_COVERS';
    } else {
      v.relation = REL_PARTIAL;
      v.explanation = 'RESIDUAL_PARTIAL';
    }
    return v;
  }

  private static EvidenceView dates(Side source, Side candidate) {
    EvidenceView v = new EvidenceView();
    v.feature = 'DATE';
    v.sourceValue = source.onDate == null
      ? null
      : String.valueOf(source.onDate);
    v.candidateValue = candidate.onDate == null
      ? null
      : String.valueOf(candidate.onDate);
    if (source.onDate == null || candidate.onDate == null) {
      v.relation = REL_UNKNOWN;
      v.explanation = 'DATE_UNKNOWN';
      return v;
    }
    v.delta = source.onDate.daysBetween(candidate.onDate);
    if (v.delta == 0) {
      v.relation = REL_EXACT;
      v.explanation = 'DATE_EXACT';
    } else {
      // No tolerance exists in v1.0.0: the signed distance is shown, never judged.
      v.relation = REL_DIFFERENT;
      v.explanation = v.delta > 0 ? 'DATE_AFTER' : 'DATE_BEFORE';
    }
    return v;
  }

  private static EvidenceView text(
    String feature,
    String left,
    String right,
    Boolean redacted
  ) {
    EvidenceView v = new EvidenceView();
    v.feature = feature;
    if (redacted) {
      v.relation = REL_REDACTED;
      v.explanation = feature + '_REDACTED';
      return v;
    }
    v.sourceValue = left;
    v.candidateValue = right;
    String a = normalize(left);
    String b = normalize(right);
    if (a == '' || b == '') {
      v.relation = REL_UNKNOWN;
      v.explanation = feature + '_UNKNOWN';
    } else if (a == b) {
      v.relation = REL_EXACT;
      v.explanation = feature + '_EXACT';
    } else if (
      Math.min(a.length(), b.length()) >= MIN_CONTAINS_LENGTH &&
      (a.contains(b) || b.contains(a))
    ) {
      v.relation = REL_CONTAINS;
      v.explanation = a.contains(b)
        ? feature + '_CONTAINS_CANDIDATE'
        : feature + '_CONTAINED_IN_CANDIDATE';
    } else {
      v.relation = REL_DIFFERENT;
      v.explanation = feature + '_DIFFERENT';
    }
    return v;
  }

  /** Case/whitespace/diacritic/punctuation folding only; no fuzzy similarity exists in v1.0.0. */
  @TestVisible
  private static String normalize(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    String folded = value.toLowerCase();
    List<String> parts = new List<String>();
    for (String ch : folded.split('')) {
      if (ch == '') {
        continue; // Apex may yield a leading empty token
      }
      Integer at = DIACRITICS.indexOf(ch);
      parts.add(at < 0 ? ch : PLAIN.substring(at, at + 1));
    }
    return String.join(parts, '')
      .replaceAll('[^\\p{L}\\p{N} ]', ' ')
      .normalizeSpace();
  }
  private static final String DIACRITICS = 'áàâãäåéèêëíìîïóòôõöøúùûüçñýÿ';
  private static final String PLAIN = 'aaaaaaeeeeiiiioooooouuuucnyy';

  /** Shown as stored: no rounding, so the values always justify the relation. */
  private static String plain(Decimal value) {
    return value == null ? null : value.toPlainString();
  }

  /** @description Tie signature: identical relation AND exact delta on every feature (no tolerance). */
  public static String signature(List<EvidenceView> evidence) {
    List<String> parts = new List<String>();
    for (EvidenceView v : evidence) {
      parts.add(
        v.feature +
          '=' +
          v.relation +
          (v.delta == null ? '' : '@' + v.delta.toPlainString())
      );
    }
    return String.join(parts, ';');
  }

  /** @description True when no identity, amount, date or text feature is EXACT — uncertainty is explicit. */
  public static Boolean lowEvidence(List<EvidenceView> evidence) {
    for (EvidenceView v : evidence) {
      if (
        v.relation == REL_EXACT &&
        v.feature != 'HOLDER' &&
        v.feature != 'CURRENCY'
      ) {
        return false;
      }
    }
    return true;
  }

  /** Presentation order per policy §2; typeRank 0 = persisted, 1 = virtual. */
  public class OrderKey implements Comparable {
    public Boolean externalExact = false;
    public Boolean sourceExact = false;
    public Integer typeRank = 0;
    public String recordKey = '';
    public Object payload;
    public OrderKey(
      List<EvidenceView> evidence,
      Integer typeRank,
      String recordKey,
      Object payload
    ) {
      for (EvidenceView v : evidence) {
        if (v.feature == 'EXTERNAL_IDENTITY' && v.relation == REL_EXACT) {
          externalExact = true;
        }
        if (v.feature == 'SOURCE_IDENTITY' && v.relation == REL_EXACT) {
          sourceExact = true;
        }
      }
      this.typeRank = typeRank;
      this.recordKey = recordKey;
      this.payload = payload;
    }
    public Integer compareTo(Object other) {
      OrderKey b = (OrderKey) other;
      if (externalExact != b.externalExact) {
        return externalExact ? -1 : 1;
      }
      if (sourceExact != b.sourceExact) {
        return sourceExact ? -1 : 1;
      }
      if (typeRank != b.typeRank) {
        return typeRank < b.typeRank ? -1 : 1;
      }
      return recordKey.compareTo(b.recordKey);
    }
  }
}
