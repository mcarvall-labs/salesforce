/**
 * @description AXF-139: evidence is independent, deterministic and score-free; missing data is
 * UNKNOWN, redacted data never contributes; ordering follows the policy presentation order.
 */
@IsTest
private class ALT_CLS_MatchEvidenceTest {
  private static ALT_CLS_MatchEvidence.Side side(
    String external,
    Id funding,
    Id holder,
    Decimal amount,
    Decimal residual,
    Date onDate,
    String description,
    String category
  ) {
    ALT_CLS_MatchEvidence.Side s = new ALT_CLS_MatchEvidence.Side();
    s.externalIdentity = external;
    s.sourceIdentity = funding;
    s.holderId = holder;
    s.currencyIso = 'BRL';
    s.amount = amount;
    s.residual = residual;
    s.onDate = onDate;
    s.description = description;
    s.category = category;
    return s;
  }

  private static Map<String, ALT_CLS_MatchEvidence.EvidenceView> byFeature(
    List<ALT_CLS_MatchEvidence.EvidenceView> evidence
  ) {
    Map<String, ALT_CLS_MatchEvidence.EvidenceView> result = new Map<String, ALT_CLS_MatchEvidence.EvidenceView>();
    for (ALT_CLS_MatchEvidence.EvidenceView v : evidence) {
      result.put(v.feature, v);
    }
    return result;
  }

  @IsTest
  static void everyFeatureIsReportedIndependentlyWithoutScoreOrTolerance() {
    Id funding =
      AXF_OBJ_BankAccount__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001AAA';
    Id holder =
      Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
    ALT_CLS_MatchEvidence.Side source = side(
      'CSV:key-1',
      funding,
      holder,
      150,
      150,
      Date.newInstance(2026, 9, 14),
      'ALUGUEL  Setembro',
      'Housing'
    );
    ALT_CLS_MatchEvidence.Side candidate = side(
      null,
      funding,
      holder,
      200,
      120,
      Date.newInstance(2026, 9, 20),
      'Aluguel setembro',
      null
    );
    Test.startTest();
    List<ALT_CLS_MatchEvidence.EvidenceView> evidence = ALT_CLS_MatchEvidence.evaluate(
      source,
      candidate
    );
    Test.stopTest();
    List<String> order = new List<String>();
    for (ALT_CLS_MatchEvidence.EvidenceView v : evidence) {
      order.add(v.feature);
    }
    Assert.areEqual(
      ALT_CLS_MatchEvidence.FEATURES,
      order,
      'features come in the fixed policy order'
    );
    Map<String, ALT_CLS_MatchEvidence.EvidenceView> f = byFeature(evidence);
    Assert.areEqual(
      'UNKNOWN',
      f.get('EXTERNAL_IDENTITY').relation,
      'forecast has no external identity'
    );
    Assert.areEqual('EXACT', f.get('SOURCE_IDENTITY').relation);
    Assert.areEqual('EXACT', f.get('HOLDER').relation);
    Assert.areEqual('EXACT', f.get('CURRENCY').relation);
    Assert.areEqual('DIFFERENT', f.get('AMOUNT').relation);
    Assert.areEqual(
      50,
      f.get('AMOUNT').delta,
      'signed difference, never a similarity'
    );
    Assert.areEqual('150', f.get('AMOUNT').sourceValue, 'shown as stored');
    Assert.isNull(
      f.get('EXTERNAL_IDENTITY').sourceValue,
      'unknown carries no value'
    );
    Assert.areEqual(
      'COVERS',
      f.get('RESIDUAL').relation,
      'source remaining extinguishes the candidate'
    );
    Assert.areEqual(-30, f.get('RESIDUAL').delta);
    Assert.areEqual('DIFFERENT', f.get('DATE').relation);
    Assert.areEqual(6, f.get('DATE').delta);
    Assert.areEqual('DATE_AFTER', f.get('DATE').explanation);
    Assert.areEqual(
      'EXACT',
      f.get('DESCRIPTION').relation,
      'case and spacing folded, nothing fuzzy'
    );
    Assert.areEqual(
      'UNKNOWN',
      f.get('CATEGORY').relation,
      'missing evidence is unknown, not negative'
    );
    Assert.isFalse(ALT_CLS_MatchEvidence.lowEvidence(evidence));

    candidate.description = 'Condominio';
    candidate.onDate = Date.newInstance(2026, 9, 10);
    candidate.residual = 150;
    candidate.sourceIdentity = null;
    ALT_CLS_MatchEvidence.EvidenceView residual = byFeature(
        ALT_CLS_MatchEvidence.evaluate(source, candidate)
      )
      .get('RESIDUAL');
    Assert.areEqual('EXACT', residual.relation);
    Map<String, ALT_CLS_MatchEvidence.EvidenceView> g = byFeature(
      ALT_CLS_MatchEvidence.evaluate(source, candidate)
    );
    Assert.areEqual('DATE_BEFORE', g.get('DATE').explanation);
    Assert.areEqual(-4, g.get('DATE').delta);
    Assert.areEqual('DIFFERENT', g.get('DESCRIPTION').relation);
    Assert.areEqual('UNKNOWN', g.get('SOURCE_IDENTITY').relation);
    candidate.residual = 400;
    Assert.areEqual(
      'PARTIAL',
      byFeature(ALT_CLS_MatchEvidence.evaluate(source, candidate))
        .get('RESIDUAL')
        .relation
    );
  }

  @IsTest
  static void redactedAndContainsRelationsNeverExposeValues() {
    ALT_CLS_MatchEvidence.Side source = side(
      null,
      null,
      null,
      10,
      10,
      Date.today(),
      'Mercado Pão de Açúcar',
      'Food'
    );
    ALT_CLS_MatchEvidence.Side candidate = side(
      null,
      null,
      null,
      10,
      10,
      Date.today(),
      'pao de acucar',
      'food'
    );
    candidate.categoryRedacted = true;
    Test.startTest();
    Map<String, ALT_CLS_MatchEvidence.EvidenceView> f = byFeature(
      ALT_CLS_MatchEvidence.evaluate(source, candidate)
    );
    Test.stopTest();
    Assert.areEqual(
      'CONTAINS',
      f.get('DESCRIPTION').relation,
      'diacritics folded, containment only'
    );
    Assert.areEqual(
      'DESCRIPTION_CONTAINS_CANDIDATE',
      f.get('DESCRIPTION').explanation,
      'direction of the containment is explicit'
    );
    Assert.areEqual('REDACTED', f.get('CATEGORY').relation);
    Assert.isNull(
      f.get('CATEGORY').sourceValue,
      'redacted evidence carries no value'
    );
    Assert.isNull(f.get('CATEGORY').candidateValue);
    Assert.areEqual('UNKNOWN', f.get('HOLDER').relation);
    Assert.areEqual('EXACT', f.get('AMOUNT').relation);
    Assert.areEqual('EXACT', f.get('DATE').relation);
    Assert.areEqual(
      'mercado pao de acucar',
      ALT_CLS_MatchEvidence.normalize('  Mercado  PÃO de Açúcar ')
    );
    Assert.areEqual(
      'aluguel set',
      ALT_CLS_MatchEvidence.normalize('ALUGUEL-SET'),
      'punctuation folded to a separator'
    );
    Assert.areEqual(
      'acucar ultimo ano',
      ALT_CLS_MatchEvidence.normalize('Açúcar Último Ãno'),
      'every entry of the fold table maps to its plain letter'
    );
    // A trivial token never counts as containment.
    ALT_CLS_MatchEvidence.Side shortSide = side(
      null,
      null,
      null,
      1,
      1,
      Date.today(),
      'x',
      null
    );
    ALT_CLS_MatchEvidence.Side longSide = side(
      null,
      null,
      null,
      1,
      1,
      Date.today(),
      'pix mercado',
      null
    );
    Assert.areEqual(
      'DIFFERENT',
      byFeature(ALT_CLS_MatchEvidence.evaluate(shortSide, longSide))
        .get('DESCRIPTION')
        .relation
    );
    // Identity is case-sensitive: provider keys differing by case are not the same key.
    ALT_CLS_MatchEvidence.Side upper = side(
      'CSV:Abc',
      null,
      null,
      1,
      1,
      Date.today(),
      null,
      null
    );
    ALT_CLS_MatchEvidence.Side lower = side(
      'CSV:abc',
      null,
      null,
      1,
      1,
      Date.today(),
      null,
      null
    );
    Assert.areEqual(
      'DIFFERENT',
      byFeature(ALT_CLS_MatchEvidence.evaluate(upper, lower))
        .get('EXTERNAL_IDENTITY')
        .relation
    );
    try {
      ALT_CLS_MatchEvidence.evaluate(null, lower);
      Assert.fail('both sides are required');
    } catch (IllegalArgumentException expected) {
      Assert.isNotNull(expected);
    }
  }

  @IsTest
  static void orderingIsPresentationOnlyAndTiesAreExplicit() {
    Id funding =
      AXF_OBJ_BankAccount__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001AAA';
    ALT_CLS_MatchEvidence.Side source = side(
      'CSV:k',
      funding,
      null,
      100,
      100,
      Date.today(),
      'x',
      null
    );
    ALT_CLS_MatchEvidence.Side plain = side(
      null,
      null,
      null,
      100,
      100,
      Date.today(),
      'x',
      null
    );
    ALT_CLS_MatchEvidence.Side funded = side(
      null,
      funding,
      null,
      50,
      50,
      Date.today().addDays(9),
      'y',
      null
    );
    ALT_CLS_MatchEvidence.Side external = side(
      'CSV:k',
      null,
      null,
      1,
      1,
      Date.today().addDays(30),
      'z',
      null
    );
    List<ALT_CLS_MatchEvidence.EvidenceView> plainEvidence = ALT_CLS_MatchEvidence.evaluate(
      source,
      plain
    );
    List<ALT_CLS_MatchEvidence.EvidenceView> fundedEvidence = ALT_CLS_MatchEvidence.evaluate(
      source,
      funded
    );
    List<ALT_CLS_MatchEvidence.EvidenceView> externalEvidence = ALT_CLS_MatchEvidence.evaluate(
      source,
      external
    );
    List<ALT_CLS_MatchEvidence.OrderKey> keys = new List<ALT_CLS_MatchEvidence.OrderKey>{
      new ALT_CLS_MatchEvidence.OrderKey(plainEvidence, 0, 'b', 'plain-b'),
      new ALT_CLS_MatchEvidence.OrderKey(plainEvidence, 1, 'a', 'virtual-a'),
      new ALT_CLS_MatchEvidence.OrderKey(plainEvidence, 0, 'a', 'plain-a'),
      new ALT_CLS_MatchEvidence.OrderKey(fundedEvidence, 0, 'z', 'funded'),
      new ALT_CLS_MatchEvidence.OrderKey(externalEvidence, 1, 'q', 'external')
    };
    Test.startTest();
    keys.sort();
    Test.stopTest();
    List<String> order = new List<String>();
    for (ALT_CLS_MatchEvidence.OrderKey k : keys) {
      order.add((String) k.payload);
    }
    Assert.areEqual(
      new List<String>{
        'external',
        'funded',
        'plain-a',
        'plain-b',
        'virtual-a'
      },
      order,
      'verified external identity, exact source identity, type rank, record id — the best amount/date match does not lead'
    );
    Assert.areEqual(
      ALT_CLS_MatchEvidence.signature(plainEvidence),
      ALT_CLS_MatchEvidence.signature(
        ALT_CLS_MatchEvidence.evaluate(source, plain)
      ),
      'identical evidence yields the same signature (tie)'
    );
    // Same relations, different exact deltas: not a tie.
    ALT_CLS_MatchEvidence.Side near = side(
      null,
      null,
      null,
      101,
      101,
      Date.today().addDays(1),
      'q',
      null
    );
    ALT_CLS_MatchEvidence.Side far = side(
      null,
      null,
      null,
      900,
      900,
      Date.today().addDays(300),
      'q',
      null
    );
    Assert.areNotEqual(
      ALT_CLS_MatchEvidence.signature(
        ALT_CLS_MatchEvidence.evaluate(source, near)
      ),
      ALT_CLS_MatchEvidence.signature(
        ALT_CLS_MatchEvidence.evaluate(source, far)
      ),
      'deltas are part of the tie signature'
    );
    Assert.areNotEqual(
      ALT_CLS_MatchEvidence.signature(plainEvidence),
      ALT_CLS_MatchEvidence.signature(fundedEvidence)
    );
    Assert.isTrue(
      ALT_CLS_MatchEvidence.lowEvidence(
        ALT_CLS_MatchEvidence.evaluate(
          side(null, null, null, 1, 1, Date.today().addDays(1), 'a', null),
          side(null, null, null, 2, 2, Date.today(), 'b', null)
        )
      ),
      'nothing exact beyond holder/currency is explicit uncertainty'
    );
  }
}
