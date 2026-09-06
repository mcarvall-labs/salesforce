/**
 * AXF-20 — pure, deterministic schedule generator for planned FinancialTransaction
 * occurrences. Authority for every formula is AMORTIZATION-POLICY.md v1.0.0; this
 * class MUST reproduce Golden Fixtures GF-04 and GF-109..GF-113. No SOQL/DML.
 *
 * Consórcio is out of scope (AXF-97) → returns BLOCKED.
 */
public inherited sharing class ALT_CLS_AmortizationSchedule {
  public static final String POLICY_VERSION = 'AMORT-POLICY@1.0.0';
  private static final Set<String> MODALITIES = new Set<String>{
    'RECURRING',
    'INSTALLMENT',
    'PRICE',
    'SAC'
  };

  public class ScheduleInput {
    @AuraEnabled
    public String modality;
    @AuraEnabled
    public Decimal principal;
    @AuraEnabled
    public Integer installments;
    @AuraEnabled
    public Decimal periodRate;
    @AuraEnabled
    public Date firstDueDate;
    @AuraEnabled
    public Decimal fixedValue;
    @AuraEnabled
    public Decimal flatFeePerInstallment;
    @AuraEnabled
    public Decimal upfrontFee;
  }

  public class Occurrence {
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public String dueDate;
    @AuraEnabled
    public Decimal payment;
    @AuraEnabled
    public Decimal principalPortion;
    @AuraEnabled
    public Decimal interestPortion;
    @AuraEnabled
    public Decimal feePortion;
    @AuraEnabled
    public Decimal closingBalance;
    @AuraEnabled
    public Boolean roundingResidualApplied = false;
  }

  public class ScheduleResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public String modality;
    @AuraEnabled
    public List<Occurrence> occurrences = new List<Occurrence>();
    @AuraEnabled
    public Decimal totalPrincipal = 0;
    @AuraEnabled
    public Decimal totalInterest = 0;
    @AuraEnabled
    public Decimal totalFees = 0;
  }

  public static ScheduleResult generate(ScheduleInput input) {
    ScheduleResult r = new ScheduleResult();
    if (input == null || String.isBlank(input.modality)) {
      return fail(r, 'INVALID', 'Modalidade não informada.');
    }
    r.modality = input.modality.toUpperCase();
    if (r.modality == 'CONSORCIO' || r.modality == 'CONSÓRCIO') {
      return fail(
        r,
        'BLOCKED',
        'Consórcio não tem policy canônica de amortização — ver AXF-97.'
      );
    }
    if (!MODALITIES.contains(r.modality)) {
      return fail(
        r,
        'BLOCKED',
        'Modalidade sem policy canônica: ' + input.modality + '.'
      );
    }
    if (input.installments == null || input.installments < 1) {
      return fail(r, 'INVALID', 'Número de parcelas deve ser ≥ 1.');
    }
    if (input.firstDueDate == null) {
      return fail(r, 'INVALID', 'Data do primeiro vencimento é obrigatória.');
    }

    Decimal flatFee = input.flatFeePerInstallment == null
      ? 0
      : input.flatFeePerInstallment.setScale(2);
    Decimal upfront = input.upfrontFee == null
      ? 0
      : input.upfrontFee.setScale(2);
    if (flatFee < 0 || upfront < 0) {
      return fail(r, 'INVALID', 'Tarifas não podem ser negativas.');
    }

    Integer n = input.installments;
    if (r.modality == 'RECURRING') {
      if (input.fixedValue == null || input.fixedValue <= 0) {
        return fail(
          r,
          'INVALID',
          'Valor fixo da recorrência é obrigatório e positivo.'
        );
      }
      buildRecurring(
        r,
        input.firstDueDate,
        n,
        input.fixedValue.setScale(2),
        flatFee,
        upfront
      );
      return finish(r);
    }

    if (r.modality == 'INSTALLMENT') {
      if (input.principal == null || input.principal <= 0) {
        return fail(r, 'INVALID', 'Total a parcelar é obrigatório e positivo.');
      }
      buildInstallment(
        r,
        input.firstDueDate,
        n,
        input.principal.setScale(2),
        flatFee,
        upfront
      );
      return finish(r);
    }

    // PRICE / SAC
    if (input.principal == null || input.principal <= 0) {
      return fail(
        r,
        'INVALID',
        'Principal financiado é obrigatório e positivo.'
      );
    }
    if (input.periodRate == null || input.periodRate < 0) {
      return fail(
        r,
        'INVALID',
        'Taxa do período é obrigatória e não negativa.'
      );
    }
    Decimal p = input.principal.setScale(2);
    Decimal i = input.periodRate;
    if (r.modality == 'PRICE') {
      buildPrice(r, input.firstDueDate, n, p, i, flatFee, upfront);
    } else {
      buildSac(r, input.firstDueDate, n, p, i, flatFee, upfront);
    }
    return finish(r);
  }

  // --- builders -----------------------------------------------------------

  private static void buildRecurring(
    ScheduleResult r,
    Date first,
    Integer n,
    Decimal v,
    Decimal flatFee,
    Decimal upfront
  ) {
    for (Integer k = 1; k <= n; k++) {
      Occurrence o = base(first, k);
      o.principalPortion = v;
      o.interestPortion = 0;
      o.feePortion = feeFor(k, flatFee, upfront);
      o.closingBalance = null;
      o.payment = (o.principalPortion + o.feePortion).setScale(2);
      r.occurrences.add(o);
    }
  }

  private static void buildInstallment(
    ScheduleResult r,
    Date first,
    Integer n,
    Decimal total,
    Decimal flatFee,
    Decimal upfront
  ) {
    Decimal part = (total / n).setScale(2, System.RoundingMode.HALF_UP);
    Decimal lastPart = total - part * (n - 1);
    for (Integer k = 1; k <= n; k++) {
      Occurrence o = base(first, k);
      o.principalPortion = (k == n) ? lastPart : part;
      o.interestPortion = 0;
      o.feePortion = feeFor(k, flatFee, upfront);
      o.roundingResidualApplied = (k == n && lastPart != part);
      o.closingBalance = null;
      o.payment = (o.principalPortion + o.feePortion).setScale(2);
      r.occurrences.add(o);
    }
  }

  private static void buildPrice(
    ScheduleResult r,
    Date first,
    Integer n,
    Decimal p,
    Decimal i,
    Decimal flatFee,
    Decimal upfront
  ) {
    Decimal pmt;
    if (i == 0) {
      pmt = (p / n).setScale(2, System.RoundingMode.HALF_UP);
    } else {
      Decimal factor = powDecimal(1 + i, n);
      pmt = (p *
        (i * factor) /
        (factor - 1))
        .setScale(2, System.RoundingMode.HALF_UP);
    }
    Decimal balance = p;
    for (Integer k = 1; k <= n; k++) {
      Occurrence o = base(first, k);
      Decimal interest = (balance * i).setScale(2, System.RoundingMode.HALF_UP);
      Decimal amort;
      Decimal payment;
      if (k == n) {
        amort = balance;
        payment = (amort + interest).setScale(2);
        o.roundingResidualApplied = (payment != pmt);
      } else {
        amort = pmt - interest;
        payment = pmt;
      }
      balance = (balance - amort).setScale(2);
      o.principalPortion = amort.setScale(2);
      o.interestPortion = interest;
      o.feePortion = feeFor(k, flatFee, upfront);
      o.closingBalance = balance;
      o.payment = (payment + o.feePortion).setScale(2);
      r.occurrences.add(o);
    }
  }

  private static void buildSac(
    ScheduleResult r,
    Date first,
    Integer n,
    Decimal p,
    Decimal i,
    Decimal flatFee,
    Decimal upfront
  ) {
    Decimal amortBase = (p / n).setScale(2, System.RoundingMode.HALF_UP);
    Decimal amortLast = p - amortBase * (n - 1);
    Decimal balance = p;
    for (Integer k = 1; k <= n; k++) {
      Occurrence o = base(first, k);
      Decimal interest = (balance * i).setScale(2, System.RoundingMode.HALF_UP);
      Decimal amort = (k == n) ? amortLast : amortBase;
      o.roundingResidualApplied = (k == n && amortLast != amortBase);
      balance = (balance - amort).setScale(2);
      o.principalPortion = amort.setScale(2);
      o.interestPortion = interest;
      o.feePortion = feeFor(k, flatFee, upfront);
      o.closingBalance = balance;
      o.payment = (amort + interest + o.feePortion).setScale(2);
      r.occurrences.add(o);
    }
  }

  // --- helpers ----------------------------------------------------------

  private static Occurrence base(Date first, Integer k) {
    Occurrence o = new Occurrence();
    o.sequence = k;
    o.dueDate = String.valueOf(first.addMonths(k - 1));
    return o;
  }

  private static Decimal feeFor(Integer k, Decimal flatFee, Decimal upfront) {
    Decimal fee = flatFee;
    if (k == 1) {
      fee += upfront;
    }
    return fee.setScale(2);
  }

  @TestVisible
  private static Decimal powDecimal(Decimal base, Integer exp) {
    Decimal result = 1;
    for (Integer x = 0; x < exp; x++) {
      result = result * base;
    }
    return result;
  }

  private static ScheduleResult finish(ScheduleResult r) {
    for (Occurrence o : r.occurrences) {
      r.totalPrincipal += o.principalPortion == null ? 0 : o.principalPortion;
      r.totalInterest += o.interestPortion == null ? 0 : o.interestPortion;
      r.totalFees += o.feePortion == null ? 0 : o.feePortion;
    }
    r.totalPrincipal = r.totalPrincipal.setScale(2);
    r.totalInterest = r.totalInterest.setScale(2);
    r.totalFees = r.totalFees.setScale(2);
    r.outcome = 'OK';
    r.message = r.occurrences.size() + ' ocorrência(s) geradas.';
    return r;
  }

  private static ScheduleResult fail(
    ScheduleResult r,
    String outcome,
    String message
  ) {
    r.outcome = outcome;
    r.message = message;
    return r;
  }
}
