/**
 * @description AXF-13 / G6 / D-62. Normalization is deterministic, versioned and idempotent.
 */
@IsTest
private class AXF_CLS_TextNormalizationTest {
  @IsTest
  static void foldsCaseDiacriticsAndPunctuation() {
    System.assertEquals(
      'pao de acucar loja 12',
      AXF_CLS_TextNormalization.normalize('PÃO de Açúcar - Loja #12!')
    );
  }

  @IsTest
  static void isIdempotent() {
    String once = AXF_CLS_TextNormalization.normalize('Compra   CARTÃO  **');
    System.assertEquals(once, AXF_CLS_TextNormalization.normalize(once));
  }

  @IsTest
  static void blankBecomesEmpty() {
    System.assertEquals('', AXF_CLS_TextNormalization.normalize(null));
    System.assertEquals('', AXF_CLS_TextNormalization.normalize('   '));
  }

  @IsTest
  static void policyVersionIsExposed() {
    System.assertEquals('norm-v1', AXF_CLS_TextNormalization.POLICY_VERSION);
  }
}
