/**
 * @description Versioned, deterministic normalization of a provider description, used both
 * for display and as an input to the fallback identity hash (AXF-13, Fechamento G6 / D-62).
 *
 * The ORIGINAL description is always kept immutable elsewhere; this only produces the
 * derived normalized form. The policy version is emitted so a re-normalization is always an
 * explicit, versioned reprocess — never a silent change.
 */
public inherited sharing class AXF_CLS_TextNormalization {
  /** @description Bump when the rules below change; drives dual-read / backfill (AC6). */
  public static final String POLICY_VERSION = 'norm-v1';

  private static final Map<String, String> DIACRITICS = new Map<String, String>{
    'á' => 'a',
    'à' => 'a',
    'â' => 'a',
    'ã' => 'a',
    'ä' => 'a',
    'é' => 'e',
    'è' => 'e',
    'ê' => 'e',
    'ë' => 'e',
    'í' => 'i',
    'ì' => 'i',
    'î' => 'i',
    'ï' => 'i',
    'ó' => 'o',
    'ò' => 'o',
    'ô' => 'o',
    'õ' => 'o',
    'ö' => 'o',
    'ú' => 'u',
    'ù' => 'u',
    'û' => 'u',
    'ü' => 'u',
    'ç' => 'c',
    'ñ' => 'n'
  };

  private AXF_CLS_TextNormalization() {
  }

  /**
   * @description Normalized form: lower-cased, diacritics folded, non-alphanumeric runs
   * collapsed to a single space, trimmed. `null`/blank => empty string.
   */
  public static String normalize(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String s = raw.toLowerCase();
    for (String k : DIACRITICS.keySet()) {
      s = s.replace(k, DIACRITICS.get(k));
    }
    s = s.replaceAll('[^a-z0-9]+', ' ').trim();
    return s;
  }
}
