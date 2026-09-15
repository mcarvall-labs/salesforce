/**
 * @description AXF-110: matcher deterministico de recorrencia — candidato mensal e anual com
 * evidencia e proxima estimativa ancorada no ciclo mais recente observado, independencia da ordem
 * de entrada, tolerancia de calendario (ancora de fim de mes e fronteira de mes de postagem),
 * tolerancia de valor com igualdade na fronteira e piso por moeda, historico insuficiente,
 * ambiguidade no mesmo ciclo com precedencia sobre a qualificacao e sem atribuicao arbitraria,
 * separacao por titular/fonte de pagamento/moeda/estabelecimento, deduplicacao da revisao mais
 * recente do mesmo fato, gate de elegibilidade/debito/indicio de servico e estabilidade de replay.
 *
 * O matcher e puro: nenhum teste precisa de DML, usuario ou permissao.
 */
@IsTest
private class ALT_CLS_SubscriptionRecurrenceTest {
  private static final Id OWNER_A = Id.valueOf('001000000000001');
  private static final Id OWNER_B = Id.valueOf('001000000000002');
  // Fonte de pagamento estavel: prefixo real do objeto e forma canonica de 18 caracteres, a
  // mesma que o mapeamento do S1 produz via String.valueOf(Id).
  private static final String SOURCE_A = String.valueOf(
    Id.valueOf(
      AXF_OBJ_BankAccount__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001'
    )
  );
  private static final String SOURCE_B = String.valueOf(
    Id.valueOf(
      AXF_OBJ_BankAccount__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000002'
    )
  );
  private static final String MERCHANT = 'netflix';
  private static final String ELIGIBLE = ALT_CLS_SubscriptionRecurrenceMatcher.ELIGIBLE;
  private static final String SERVICE = ALT_CLS_SubscriptionRecurrenceMatcher.SERVICE_CANDIDATE;
  private static final String DEBIT = ALT_CLS_SubscriptionRecurrenceMatcher.DEBIT;

  private static ALT_CLS_SubscriptionRecurrenceMatcher.Observation observation(
    String key,
    Date chargedOn,
    Decimal magnitude,
    Id ownerId,
    String paymentSourceId,
    String currencyIsoCode,
    String merchant,
    String eligibility,
    String serviceHint,
    String direction
  ) {
    ALT_CLS_SubscriptionRecurrenceMatcher.Observation result = new ALT_CLS_SubscriptionRecurrenceMatcher.Observation();
    result.observationKey = key;
    // Cada cobranca e uma transacao distinta com a mesma fonte de pagamento estavel.
    result.transactionIdentity = 'BANK:tx-' + key;
    result.revision = 1;
    result.ownerId = ownerId;
    result.paymentSourceId = paymentSourceId;
    result.currencyIsoCode = currencyIsoCode;
    result.normalizedMerchant = merchant;
    result.eligibility = eligibility;
    result.serviceHint = serviceHint;
    result.direction = direction;
    result.chargedOn = chargedOn;
    result.magnitude = magnitude;
    return result;
  }

  private static ALT_CLS_SubscriptionRecurrenceMatcher.Observation charge(
    String key,
    Date chargedOn,
    Decimal magnitude
  ) {
    return observation(
      key,
      chargedOn,
      magnitude,
      OWNER_A,
      SOURCE_A,
      'BRL',
      MERCHANT,
      ELIGIBLE,
      SERVICE,
      DEBIT
    );
  }

  private static ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult run(
    List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation> observations
  ) {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateInput input = new ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateInput();
    input.ownerId = OWNER_A;
    input.observations = observations;
    return ALT_CLS_SubscriptionRecurrenceMatcher.evaluate(input);
  }

  private static List<Integer> cycleIndexes(
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream
  ) {
    List<Integer> result = new List<Integer>();
    for (
      ALT_CLS_SubscriptionRecurrenceMatcher.CycleAssignment row : stream.evidence
    ) {
      result.add(row.cycleIndex);
    }
    return result;
  }

  private static List<String> evidenceKeys(
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream
  ) {
    List<String> result = new List<String>();
    for (
      ALT_CLS_SubscriptionRecurrenceMatcher.CycleAssignment row : stream.evidence
    ) {
      result.add(row.observationKey);
    }
    return result;
  }

  // ------------------------------------------------------------ AC-1

  @IsTest
  static void monthlyChargesProduceOneCandidateWithEvidenceAndNextEstimate() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 109.90),
        charge('july', Date.newInstance(2025, 7, 5), 109.90),
        charge('august', Date.newInstance(2025, 8, 5), 109.90)
      }
    );

    Assert.areEqual(1, result.streams.size(), 'exactly one stream is proposed');
    Assert.areEqual(1, result.qualifiedStreams);
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.QUALIFIED,
      stream.outcome
    );
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.MONTHLY,
      stream.cadence
    );
    Assert.areEqual(Date.newInstance(2025, 6, 5), stream.anchorDate);
    Assert.areEqual(109.90, stream.referenceAmount);
    Assert.areEqual(new List<Integer>{ 0, 1, 2 }, cycleIndexes(stream));
    Assert.areEqual(
      new List<String>{ 'june', 'july', 'august' },
      evidenceKeys(stream),
      'all three eligible charges are linked to the candidate'
    );
    Assert.areEqual(
      Date.newInstance(2025, 9, 5),
      stream.nextEstimateDate,
      'the next estimate is one cadence after the latest observed cycle'
    );
    Assert.areEqual(3, stream.observedCycles);
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.POLICY_VERSION,
      result.policyVersion
    );
    Assert.areEqual(OWNER_A, result.ownerId);
  }

  @IsTest
  static void nextEstimateFollowsTheLatestObservedCycleNotTheMinimum() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('jan', Date.newInstance(2025, 1, 5), 109.90),
        charge('feb', Date.newInstance(2025, 2, 5), 109.90),
        charge('mar', Date.newInstance(2025, 3, 5), 109.90),
        charge('apr', Date.newInstance(2025, 4, 5), 109.90),
        charge('may', Date.newInstance(2025, 5, 5), 109.90)
      }
    );

    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.QUALIFIED,
      stream.outcome
    );
    Assert.areEqual(
      new List<Integer>{ 0, 1, 2 },
      cycleIndexes(stream),
      'P1 evidence stays the minimum anchored cycles'
    );
    Assert.areEqual(
      5,
      stream.observedCycles,
      'the observed history depth is exposed'
    );
    Assert.areEqual(4, stream.lastObservedCycle);
    Assert.areEqual(
      Date.newInstance(2025, 6, 5),
      stream.nextEstimateDate,
      'the estimate must not fall on an already observed charge date'
    );
  }

  @IsTest
  static void inputOrderDoesNotChangeTheResult() {
    List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation> chronological = new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
      charge('june', Date.newInstance(2025, 6, 5), 109.90),
      charge('july', Date.newInstance(2025, 7, 5), 109.90),
      charge('august', Date.newInstance(2025, 8, 5), 109.90)
    };
    List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation> shuffled = new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
      charge('august', Date.newInstance(2025, 8, 5), 109.90),
      charge('june', Date.newInstance(2025, 6, 5), 109.90),
      charge('july', Date.newInstance(2025, 7, 5), 109.90)
    };

    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment first = run(
        chronological
      )
      .streams[0];
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment second = run(
        shuffled
      )
      .streams[0];

    Assert.areEqual(first.streamKey, second.streamKey);
    Assert.areEqual(first.outcome, second.outcome);
    Assert.areEqual(first.cadence, second.cadence);
    Assert.areEqual(first.anchorDate, second.anchorDate);
    Assert.areEqual(first.nextEstimateDate, second.nextEstimateDate);
    Assert.areEqual(first.referenceAmount, second.referenceAmount);
    Assert.areEqual(
      new List<String>{ 'june', 'july', 'august' },
      evidenceKeys(second)
    );
  }

  @IsTest
  static void twoAnnualChargesProduceOneAnnualCandidate() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('year-one', Date.newInstance(2024, 9, 10), 240.00),
        charge('year-two', Date.newInstance(2025, 9, 10), 240.00)
      }
    );

    Assert.areEqual(1, result.streams.size());
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.QUALIFIED,
      stream.outcome
    );
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.ANNUAL,
      stream.cadence
    );
    Assert.areEqual(new List<Integer>{ 0, 1 }, cycleIndexes(stream));
    Assert.areEqual(Date.newInstance(2026, 9, 10), stream.nextEstimateDate);
  }

  @IsTest
  static void annualReferenceIsTheMedianOfTwoDistinctAmounts() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('year-one', Date.newInstance(2024, 9, 10), 100.00),
        charge('year-two', Date.newInstance(2025, 9, 10), 104.00)
      }
    );

    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.QUALIFIED,
      stream.outcome
    );
    Assert.areEqual(
      102.00,
      stream.referenceAmount,
      'the even median averages the two middle amounts'
    );
  }

  @IsTest
  static void singleAnnualLookingChargeProducesNoCandidate() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('only', Date.newInstance(2025, 9, 10), 240.00)
      }
    );

    Assert.areEqual(0, result.qualifiedStreams);
    Assert.areEqual(1, result.streams.size());
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.INSUFFICIENT_HISTORY,
      stream.outcome
    );
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.REASON_MISSING_CYCLES,
      stream.reason
    );
    Assert.areEqual(
      1,
      stream.evidencedCycles,
      'the single charge is reported as one evidenced cycle'
    );
    Assert.isTrue(
      stream.evidence.isEmpty(),
      'no candidate evidence is proposed'
    );
  }

  // ------------------------------------------------------------ AC-2

  @IsTest
  static void dateToleranceWithinP1StillQualifies() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 109.90),
        charge('july', Date.newInstance(2025, 7, 8), 109.90),
        charge('august', Date.newInstance(2025, 8, 4), 109.90)
      }
    );

    Assert.areEqual(1, result.qualifiedStreams);
    Assert.areEqual(Date.newInstance(2025, 6, 5), result.streams[0].anchorDate);
  }

  @IsTest
  static void dateToleranceBoundaryEqualityQualifies() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 100.00),
        charge('july', Date.newInstance(2025, 7, 10), 100.00),
        charge('august', Date.newInstance(2025, 8, 5), 100.00)
      }
    );

    Assert.areEqual(
      1,
      result.qualifiedStreams,
      'exactly +5 days is inside the P1 monthly tolerance'
    );
  }

  @IsTest
  static void annualDateToleranceBoundaryIsInclusiveAndRejectsBeyond() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult atBoundary = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('year-one', Date.newInstance(2024, 9, 10), 240.00),
        charge('year-two', Date.newInstance(2025, 9, 25), 240.00)
      }
    );
    Assert.areEqual(
      1,
      atBoundary.qualifiedStreams,
      'exactly +15 days is inside the P1 annual tolerance'
    );

    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult beyond = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('year-one', Date.newInstance(2024, 9, 10), 240.00),
        charge('year-two', Date.newInstance(2025, 9, 26), 240.00)
      }
    );
    Assert.areEqual(0, beyond.qualifiedStreams);
    Assert.areEqual(1, beyond.streams[0].unmatchedObservations);
  }

  @IsTest
  static void dateBeyondToleranceLeavesTheCycleMissing() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 100.00),
        charge('july', Date.newInstance(2025, 7, 11), 100.00),
        charge('august', Date.newInstance(2025, 8, 5), 100.00)
      }
    );

    Assert.areEqual(0, result.qualifiedStreams);
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.REASON_MISSING_CYCLES,
      stream.reason
    );
    Assert.areEqual(
      1,
      stream.unmatchedObservations,
      'the out-of-tolerance charge is reported, not silently dropped'
    );
  }

  @IsTest
  static void endOfMonthAnchorClampsWithoutShiftingPermanently() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('january', Date.newInstance(2025, 1, 31), 50.00),
        charge('february', Date.newInstance(2025, 2, 28), 50.00),
        charge('march', Date.newInstance(2025, 3, 31), 50.00)
      }
    );

    Assert.areEqual(1, result.qualifiedStreams);
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      Date.newInstance(2025, 1, 31),
      stream.anchorDate,
      'the anchor keeps day 31'
    );
    Assert.areEqual(
      Date.newInstance(2025, 2, 28),
      stream.evidence[1].expectedDate,
      'February clamps to its last day without changing the anchor'
    );
    Assert.areEqual(
      Date.newInstance(2025, 4, 30),
      stream.nextEstimateDate,
      'the retained anchor is 31, so April clamps to the 30th'
    );
  }

  @IsTest
  static void postingMonthBoundaryDoesNotRejectTheNextCycle() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('january-first', Date.newInstance(2025, 1, 1), 80.00),
        charge('january-thirtieth', Date.newInstance(2025, 1, 30), 80.00),
        charge('march', Date.newInstance(2025, 3, 1), 80.00)
      }
    );

    Assert.areEqual(
      1,
      result.qualifiedStreams,
      'the posting-month boundary alone does not reject the distinct February cycle'
    );
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(new List<Integer>{ 0, 1, 2 }, cycleIndexes(stream));
    Assert.areEqual(
      Date.newInstance(2025, 1, 30),
      stream.evidence[1].chargedOn,
      'the January 30 charge is the evidence of the February cycle'
    );
    Assert.areEqual(
      Date.newInstance(2025, 2, 1),
      stream.evidence[1].expectedDate
    );
  }

  @IsTest
  static void missingCycleBlocksInitialQualification() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 100.00),
        charge('august', Date.newInstance(2025, 8, 5), 100.00)
      }
    );

    Assert.areEqual(0, result.qualifiedStreams);
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.INSUFFICIENT_HISTORY,
      result.streams[0].outcome
    );
  }

  @IsTest
  static void annualLeapDayAnchorClampsOutsideLeapYears() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('leap', Date.newInstance(2024, 2, 29), 120.00),
        charge('next', Date.newInstance(2025, 2, 28), 120.00)
      }
    );

    Assert.areEqual(1, result.qualifiedStreams);
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.ANNUAL,
      stream.cadence
    );
    Assert.areEqual(
      Date.newInstance(2025, 2, 28),
      stream.evidence[1].expectedDate
    );
    Assert.areEqual(Date.newInstance(2026, 2, 28), stream.nextEstimateDate);
  }

  // ------------------------------------------------------------ AC-3 / P2

  @IsTest
  static void valueVariationWithinP2DoesNotPreventTheCandidate() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 100.00),
        charge('july', Date.newInstance(2025, 7, 5), 104.00),
        charge('august', Date.newInstance(2025, 8, 5), 98.00)
      }
    );

    Assert.areEqual(1, result.qualifiedStreams);
    Assert.areEqual(100.00, result.streams[0].referenceAmount);
  }

  @IsTest
  static void valueBandBoundaryEqualityIsAccepted() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 100.00),
        charge('july', Date.newInstance(2025, 7, 5), 100.00),
        charge('august', Date.newInstance(2025, 8, 5), 110.00)
      }
    );

    Assert.areEqual(
      1,
      result.qualifiedStreams,
      'exactly at max(BRL 5, 10%) is accepted'
    );
  }

  @IsTest
  static void valueBeyondTheBandProducesNoCandidateAndKeepsTheReference() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 100.00),
        charge('july', Date.newInstance(2025, 7, 5), 100.00),
        charge('august', Date.newInstance(2025, 8, 5), 111.00)
      }
    );

    Assert.areEqual(0, result.qualifiedStreams);
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.REASON_VALUE_BAND,
      stream.reason
    );
    Assert.areEqual(
      100.00,
      stream.referenceAmount,
      'the reference is retained so the divergence is explainable'
    );
    Assert.areEqual(3, stream.evidence.size());
  }

  @IsTest
  static void theBrlFloorIsNotAppliedToAnotherCurrency() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult usd = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        observation(
          'u1',
          Date.newInstance(2025, 6, 5),
          20.00,
          OWNER_A,
          SOURCE_A,
          'USD',
          MERCHANT,
          ELIGIBLE,
          SERVICE,
          DEBIT
        ),
        observation(
          'u2',
          Date.newInstance(2025, 7, 5),
          20.00,
          OWNER_A,
          SOURCE_A,
          'USD',
          MERCHANT,
          ELIGIBLE,
          SERVICE,
          DEBIT
        ),
        observation(
          'u3',
          Date.newInstance(2025, 8, 5),
          24.00,
          OWNER_A,
          SOURCE_A,
          'USD',
          MERCHANT,
          ELIGIBLE,
          SERVICE,
          DEBIT
        )
      }
    );

    Assert.areEqual(
      0,
      usd.qualifiedStreams,
      'the BRL floor is not a USD floor'
    );
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.REASON_VALUE_BAND,
      usd.streams[0].reason
    );

    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult brl = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('b1', Date.newInstance(2025, 6, 5), 20.00),
        charge('b2', Date.newInstance(2025, 7, 5), 20.00),
        charge('b3', Date.newInstance(2025, 8, 5), 24.00)
      }
    );

    Assert.areEqual(
      1,
      brl.qualifiedStreams,
      'the same variation is inside the BRL floor band'
    );
  }

  @IsTest
  static void twoChargesInTheSameCycleAreReturnedForReview() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 100.00),
        charge('july-first', Date.newInstance(2025, 7, 5), 100.00),
        charge('july-second', Date.newInstance(2025, 7, 8), 100.00)
      }
    );

    Assert.areEqual(0, result.qualifiedStreams);
    Assert.areEqual(1, result.ambiguousStreams);
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.AMBIGUOUS,
      stream.outcome
    );
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.REASON_CYCLE_COLLISION,
      stream.reason
    );
    Assert.areEqual(new List<Integer>{ 1 }, stream.ambiguousCycles);
    Assert.areEqual(
      2,
      stream.ambiguousEvidence.size(),
      'the conflicting charges are returned for review'
    );
    Assert.areEqual(
      new List<String>{ 'july-first', 'july-second' },
      new List<String>{
        stream.ambiguousEvidence[0].observationKey,
        stream.ambiguousEvidence[1].observationKey
      }
    );
    Assert.isTrue(stream.evidence.isEmpty(), 'no arbitrary assignment is made');
  }

  @IsTest
  static void ambiguityTakesPrecedenceOverQualificationInTheOtherCadence() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('january', Date.newInstance(2024, 1, 31), 100.00),
        charge('june-first', Date.newInstance(2024, 6, 1), 100.00),
        charge('june-second', Date.newInstance(2024, 6, 2), 100.00),
        charge('next-year', Date.newInstance(2025, 1, 31), 100.00)
      }
    );

    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.AMBIGUOUS,
      stream.outcome,
      'indistinguishable charges still require review when the annual reading would qualify'
    );
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.REASON_CYCLE_COLLISION,
      stream.reason
    );
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.MONTHLY,
      stream.cadence
    );
  }

  @IsTest
  static void twoIndistinguishablePlansRequireReview() {
    // Mesmo estabelecimento, mesma fonte: dois planos independentes sem evidencia que os separe.
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('plan-a-jan', Date.newInstance(2025, 1, 5), 29.90),
        charge('plan-b-jan', Date.newInstance(2025, 1, 6), 59.90),
        charge('plan-a-feb', Date.newInstance(2025, 2, 5), 29.90),
        charge('plan-b-feb', Date.newInstance(2025, 2, 6), 59.90),
        charge('plan-a-mar', Date.newInstance(2025, 3, 5), 29.90)
      }
    );

    Assert.areEqual(
      0,
      result.qualifiedStreams,
      'plans cannot be merged or attached automatically (P3/AC15)'
    );
    Assert.areEqual(1, result.ambiguousStreams);
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.REASON_CYCLE_COLLISION,
      result.streams[0].reason
    );
  }

  // ------------------------------------------------------------ AC-4 / AC10 / P3

  @IsTest
  static void aDifferentPaymentSourceOrMerchantOrCurrencyCannotBeGrouped() {
    List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation> observations = new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
      charge('a-june', Date.newInstance(2025, 6, 5), 109.90),
      charge('a-july', Date.newInstance(2025, 7, 5), 109.90),
      charge('a-august', Date.newInstance(2025, 8, 5), 109.90),
      observation(
        'b-june',
        Date.newInstance(2025, 6, 5),
        109.90,
        OWNER_A,
        SOURCE_B,
        'BRL',
        MERCHANT,
        ELIGIBLE,
        SERVICE,
        DEBIT
      ),
      observation(
        'c-june',
        Date.newInstance(2025, 6, 5),
        109.90,
        OWNER_A,
        SOURCE_A,
        'USD',
        MERCHANT,
        ELIGIBLE,
        SERVICE,
        DEBIT
      ),
      observation(
        'd-june',
        Date.newInstance(2025, 6, 5),
        109.90,
        OWNER_A,
        SOURCE_A,
        'BRL',
        'spotify',
        ELIGIBLE,
        SERVICE,
        DEBIT
      )
    };

    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      observations
    );

    Assert.areEqual(
      4,
      result.streams.size(),
      'owner+payment source+currency+merchant separates the streams'
    );
    Assert.areEqual(1, result.qualifiedStreams);
    Assert.areEqual(3, result.insufficientHistoryStreams);
  }

  @IsTest
  static void perTransactionIdentityDoesNotSplitAStream() {
    // As cobrancas tem identidades de transacao distintas e a MESMA fonte de pagamento.
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 109.90),
        charge('july', Date.newInstance(2025, 7, 5), 109.90),
        charge('august', Date.newInstance(2025, 8, 5), 109.90)
      }
    );

    Assert.areEqual(
      1,
      result.streams.size(),
      'the transaction identity must never be a grouping dimension'
    );
    Assert.areEqual(SOURCE_A, result.streams[0].paymentSourceId);
  }

  @IsTest
  static void aDifferentOwnerIsOutsideTheAuthorizedScope() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 109.90),
        charge('july', Date.newInstance(2025, 7, 5), 109.90),
        charge('august', Date.newInstance(2025, 8, 5), 109.90),
        observation(
          'other-owner',
          Date.newInstance(2025, 6, 5),
          109.90,
          OWNER_B,
          SOURCE_A,
          'BRL',
          MERCHANT,
          ELIGIBLE,
          SERVICE,
          DEBIT
        )
      }
    );

    Assert.areEqual(
      1,
      result.outOfScopeObservations,
      'authorization scope is reported separately from eligibility'
    );
    Assert.areEqual(0, result.ineligibleObservations);
    Assert.areEqual(3, result.eligibleObservations);
    Assert.areEqual(1, result.streams.size());
  }

  @IsTest
  static void excludedUnknownCreditOrGenericMerchantCannotBeGrouped() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        charge('june', Date.newInstance(2025, 6, 5), 109.90),
        charge('july', Date.newInstance(2025, 7, 5), 109.90),
        charge('august', Date.newInstance(2025, 8, 5), 109.90),
        observation(
          'excluded',
          Date.newInstance(2025, 6, 5),
          109.90,
          OWNER_A,
          SOURCE_A,
          'BRL',
          MERCHANT,
          'EXCLUDED',
          SERVICE,
          DEBIT
        ),
        observation(
          'unknown',
          Date.newInstance(2025, 6, 5),
          109.90,
          OWNER_A,
          SOURCE_A,
          'BRL',
          MERCHANT,
          'UNKNOWN',
          SERVICE,
          DEBIT
        ),
        observation(
          'credit',
          Date.newInstance(2025, 6, 5),
          109.90,
          OWNER_A,
          SOURCE_A,
          'BRL',
          MERCHANT,
          ELIGIBLE,
          SERVICE,
          'CREDIT'
        ),
        observation(
          'generic',
          Date.newInstance(2025, 6, 5),
          109.90,
          OWNER_A,
          SOURCE_A,
          'BRL',
          'amazon',
          ELIGIBLE,
          'NONE',
          DEBIT
        ),
        observation(
          'no-source',
          Date.newInstance(2025, 6, 5),
          109.90,
          OWNER_A,
          null,
          'BRL',
          MERCHANT,
          ELIGIBLE,
          SERVICE,
          DEBIT
        )
      }
    );

    Assert.areEqual(3, result.eligibleObservations);
    Assert.areEqual(5, result.ineligibleObservations);
    Assert.areEqual(1, result.qualifiedStreams);
    Assert.areEqual(3, result.streams[0].evidence.size());
  }

  @IsTest
  static void onlyTheLatestRevisionOfAFactIsEvaluated() {
    ALT_CLS_SubscriptionRecurrenceMatcher.Observation stale = charge(
      'june-stale',
      Date.newInstance(2025, 6, 5),
      100.00
    );
    stale.transactionIdentity = 'BANK:tx-june';
    stale.revision = 1;

    ALT_CLS_SubscriptionRecurrenceMatcher.Observation current = charge(
      'june-current',
      Date.newInstance(2025, 6, 5),
      110.00
    );
    current.transactionIdentity = 'BANK:tx-june';
    current.revision = 2;

    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
        stale,
        current,
        charge('july', Date.newInstance(2025, 7, 5), 110.00),
        charge('august', Date.newInstance(2025, 8, 5), 110.00)
      }
    );

    Assert.areEqual(
      1,
      result.deduplicatedObservations,
      'the superseded revision is not evaluated'
    );
    Assert.areEqual(3, result.eligibleObservations);
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
    Assert.areEqual(
      ALT_CLS_SubscriptionRecurrenceMatcher.QUALIFIED,
      stream.outcome,
      'revision siblings must not collide in the same cycle'
    );
    Assert.areEqual(
      110.00,
      stream.referenceAmount,
      'the latest revision is the evaluated content'
    );
  }

  @IsTest
  static void replayDoesNotInventADifferentStream() {
    List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation> observations = new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>{
      charge('june', Date.newInstance(2025, 6, 5), 109.90),
      charge('july', Date.newInstance(2025, 7, 5), 109.90),
      charge('august', Date.newInstance(2025, 8, 5), 109.90)
    };

    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment first = run(
        observations
      )
      .streams[0];
    ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment replayed = run(
        observations
      )
      .streams[0];

    Assert.areEqual(
      first.streamKey,
      replayed.streamKey,
      'the stream identity depends on content only'
    );
    Assert.areEqual(first.nextEstimateDate, replayed.nextEstimateDate);
    Assert.areEqual(
      first.streamKey,
      AXF_CLS_IdentityFraming.key(
        new List<Object>{ OWNER_A, SOURCE_A, 'BRL', MERCHANT }
      ),
      'the stream key carries no rule version and no transaction identity'
    );
  }

  @IsTest
  static void missingInputIsRejected() {
    try {
      ALT_CLS_SubscriptionRecurrenceMatcher.evaluate(null);
      Assert.fail('a null input must be rejected');
    } catch (ALT_CLS_SubscriptionRecurrenceMatcher.RecurrenceException expected) {
      Assert.areEqual(
        ALT_CLS_SubscriptionRecurrenceMatcher.INVALID_INPUT,
        expected.code
      );
    }

    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateInput withoutOwner = new ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateInput();
    try {
      ALT_CLS_SubscriptionRecurrenceMatcher.evaluate(withoutOwner);
      Assert.fail('a missing owner must be rejected');
    } catch (ALT_CLS_SubscriptionRecurrenceMatcher.RecurrenceException expected) {
      Assert.areEqual(
        ALT_CLS_SubscriptionRecurrenceMatcher.INVALID_INPUT,
        expected.code
      );
    }
  }

  @IsTest
  static void aBatchLargerThanTheLimitIsRejected() {
    List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation> observations = new List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation>();
    Integer oversized = ALT_CLS_SubscriptionRecurrenceMatcher.MAX_BATCH + 1;
    for (Integer index = 0; index < oversized; index++) {
      observations.add(
        charge('bulk-' + index, Date.newInstance(2025, 6, 5), 100.00)
      );
    }

    try {
      run(observations);
      Assert.fail('a batch above MAX_BATCH must be rejected');
    } catch (ALT_CLS_SubscriptionRecurrenceMatcher.RecurrenceException expected) {
      Assert.areEqual(
        ALT_CLS_SubscriptionRecurrenceMatcher.INVALID_INPUT,
        expected.code
      );
    }
  }

  // ------------------------------------------------------------ contrato S1 -> matcher

  @IsTest
  static void mappedS1ObservationsQualifyEndToEnd() {
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(
      ALT_CLS_SubscriptionRecurrenceMatcher.fromObservations(
        new List<AXF_OBJ_TransactionObservation__c>{
          observationRow('june', Date.newInstance(2025, 6, 5), 109.90),
          observationRow('july', Date.newInstance(2025, 7, 5), 109.90),
          observationRow('august', Date.newInstance(2025, 8, 5), 109.90)
        }
      )
    );

    Assert.areEqual(
      1,
      result.qualifiedStreams,
      'the S1 mapping must carry every gate the matcher needs'
    );
    Assert.areEqual(3, result.eligibleObservations);
    Assert.areEqual(0, result.ineligibleObservations);
    Assert.areEqual(SOURCE_A, result.streams[0].paymentSourceId);
  }

  @IsTest
  static void fromObservationsMapsTheS1Contract() {
    List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation> mapped = ALT_CLS_SubscriptionRecurrenceMatcher.fromObservations(
      new List<AXF_OBJ_TransactionObservation__c>{
        observationRow('june', Date.newInstance(2025, 6, 5), 109.90),
        null
      }
    );

    Assert.areEqual(1, mapped.size());
    Assert.areEqual('frame|june', mapped[0].observationKey);
    Assert.areEqual('BANK:tx-june', mapped[0].transactionIdentity);
    Assert.areEqual(1, mapped[0].revision);
    Assert.areEqual(OWNER_A, mapped[0].ownerId);
    Assert.areEqual(SOURCE_A, mapped[0].paymentSourceId);
    Assert.areEqual('BRL', mapped[0].currencyIsoCode);
    Assert.areEqual(MERCHANT, mapped[0].normalizedMerchant);
    Assert.areEqual(ELIGIBLE, mapped[0].eligibility);
    Assert.areEqual(SERVICE, mapped[0].serviceHint);
    Assert.areEqual(DEBIT, mapped[0].direction);
    Assert.areEqual(Date.newInstance(2025, 6, 5), mapped[0].chargedOn);
    Assert.areEqual(109.90, mapped[0].magnitude);

    Assert.isTrue(
      ALT_CLS_SubscriptionRecurrenceMatcher.fromObservations(null).isEmpty()
    );
  }

  @IsTest
  static void anObservationWithoutAResolvedPaymentSourceFailsClosed() {
    AXF_OBJ_TransactionObservation__c row = observationRow(
      'june',
      Date.newInstance(2025, 6, 5),
      109.90
    );
    row.AXF_TOB_LKP_BankTransaction__r = null;
    row.AXF_TOB_LKP_BankTransaction__c = null;

    List<ALT_CLS_SubscriptionRecurrenceMatcher.Observation> mapped = ALT_CLS_SubscriptionRecurrenceMatcher.fromObservations(
      new List<AXF_OBJ_TransactionObservation__c>{ row }
    );

    Assert.isNull(mapped[0].paymentSourceId);
    ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = run(mapped);
    Assert.areEqual(
      0,
      result.eligibleObservations,
      'an unresolved payment source cannot form a stream'
    );
    Assert.areEqual(1, result.ineligibleObservations);
  }

  private static AXF_OBJ_TransactionObservation__c observationRow(
    String key,
    Date chargedOn,
    Decimal magnitude
  ) {
    AXF_OBJ_BankAccountTransaction__c txn = new AXF_OBJ_BankAccountTransaction__c(
      Id = Id.valueOf(
        AXF_OBJ_BankAccountTransaction__c.SObjectType.getDescribe()
          .getKeyPrefix() + '000000000001'
      ),
      AXF_BAT_MDR_BankAccount__c = Id.valueOf(SOURCE_A)
    );
    AXF_OBJ_TransactionObservation__c row = new AXF_OBJ_TransactionObservation__c(
      AXF_TOB_LKP_Account__c = OWNER_A,
      AXF_TOB_LKP_BankTransaction__c = txn.Id,
      AXF_TOB_TXT_SourceIdentity__c = 'BANK:tx-' + key,
      AXF_TOB_NUM_Revision__c = 1,
      AXF_TOB_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_TOB_TXT_NormalizedMerchant__c = MERCHANT,
      AXF_TOB_PKL_Eligibility__c = ELIGIBLE,
      AXF_TOB_PKL_ServiceHint__c = SERVICE,
      AXF_TOB_PKL_Direction__c = DEBIT,
      AXF_TOB_DAT_Date__c = chargedOn,
      AXF_TOB_NUM_Magnitude__c = magnitude,
      AXF_TOB_EXI_ObservationKey__c = 'frame|' + key
    );
    row.AXF_TOB_LKP_BankTransaction__r = txn;
    return row;
  }
}
