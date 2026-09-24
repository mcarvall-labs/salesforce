/**
 * @description AXF-157: timesheet of service (revenue, HOURLY) contracts over the AXF-56 WorkRecord
 * engine. Registers one day of work from its clock times (Entrada/Pausa/Retorno/Saída) with the rate,
 * currency and term of the active term version, submits drafts for approval, lists the entries of
 * the authorized context with their billing status and forecasts the revenue of a month grouped by
 * destination bank account (the preferred account of the term recorded on each entry). No new
 * schema: the clock times live only in the WorkRecord description. Approval stays in the contract
 * management screen.
 */
public with sharing class ALT_CLS_TimesheetService {
  public static final String CODE_INVALID_INPUT = 'INVALID_INPUT';
  public static final String CODE_NOT_ACCESSIBLE = 'NOT_ACCESSIBLE';
  public static final String CODE_INVALID_STATE = 'INVALID_STATE';
  /** The same shift already left the editable states (submitted, approved or superseded). */
  public static final String CODE_ALREADY_REGISTERED = 'ALREADY_REGISTERED';
  public static final String BILLED = 'BILLED';
  public static final String PARTIAL = 'PARTIAL';
  public static final String UNBILLED = 'UNBILLED';
  /** Only approved work can be billed; every other status is reported as not billable. */
  public static final String NOT_BILLABLE = 'NOT_BILLABLE';
  /** Forecast group of contracts whose active term has no preferred bank account. */
  public static final String NO_DESTINATION = 'NONE';
  public static final Integer MAX_PERIOD_DAYS = 366;
  public static final Integer MAX_ROWS = 500;
  public static final Integer MAX_CONTRACTS = 200;
  public static final Integer MAX_NOTE_LENGTH = 200;
  private static final String TYPE_REVENUE = 'REVENUE';
  private static final Set<String> BILLING_STATUSES = new Set<String>{
    BILLED,
    PARTIAL,
    UNBILLED,
    NOT_BILLABLE
  };
  private static final Set<String> RECORD_STATUSES = new Set<String>{
    ALT_CLS_WorkRecordService.STATUS_DRAFT,
    ALT_CLS_WorkRecordService.STATUS_SUBMITTED,
    ALT_CLS_WorkRecordService.STATUS_APPROVED,
    ALT_CLS_WorkRecordService.STATUS_REJECTED,
    ALT_CLS_WorkRecordService.STATUS_SUPERSEDED
  };
  private static final Set<String> SUBMITTABLE = new Set<String>{
    ALT_CLS_WorkRecordService.STATUS_DRAFT,
    ALT_CLS_WorkRecordService.STATUS_REJECTED
  };
  /** Statuses that no longer hold their hours: they never block another shift. */
  private static final Set<String> RELEASED_STATUSES = new Set<String>{
    ALT_CLS_WorkRecordService.STATUS_REJECTED,
    ALT_CLS_WorkRecordService.STATUS_SUPERSEDED
  };
  private static final Set<String> FORECAST_STATUSES = new Set<String>{
    ALT_CLS_WorkRecordService.STATUS_APPROVED,
    ALT_CLS_WorkRecordService.STATUS_SUBMITTED
  };
  private static final String TIMES_SEPARATOR = ' | ';
  private static final String NOTE_SEPARATOR = ' · ';
  private static final Pattern CLOCK_PATTERN = Pattern.compile(
    '([01]\\d|2[0-3]):[0-5]\\d'
  );
  /** Description written by this screen: `08:00-12:00 | 13:00-17:30 · note`. */
  private static final Pattern SCREEN_DESCRIPTION = Pattern.compile(
    '(?s)(\\d{2}:\\d{2}-\\d{2}:\\d{2}(?: \\| \\d{2}:\\d{2}-\\d{2}:\\d{2})?)(?: · (.*))?'
  );
  private static final String CONTRACT_FIELDS =
    'Id, Name, AXF_CTR_TXT_Title__c, AXF_CTR_LKP_Account__c, AXF_CTR_LKP_ActiveTermVersion__c, ' +
    'AXF_CTR_DAT_StartDate__c, AXF_CTR_DAT_EndDate__c, AXF_CTR_DAT_TerminationEffectiveDate__c, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_DAT_EffectiveFrom__c, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_DAT_EffectiveTo__c, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_CUR_Rate__c, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_TXT_CurrencyIsoCode__c, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_LKP_PreferredBankAccount__c, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_LKP_PreferredBankAccount__r.Name, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_LKP_PreferredBankAccount__r.AXF_BA_TXT_InstitutionName__c, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_LKP_PreferredBankAccount__r.AXF_BA_TXT_NumberMasked__c, ' +
    'AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_LKP_PreferredBankAccount__r.AXF_BA_TXT_Type__c';
  private static final String ELIGIBLE_FILTER =
    ' AND AXF_CTR_PKL_Lifecycle__c = \'ACTIVE\'' +
    ' AND AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_PKL_Status__c = \'ACTIVE\'' +
    ' AND AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_PKL_RemunerationModel__c = \'HOURLY\'' +
    ' AND AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_CUR_Rate__c != NULL' +
    ' AND AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_TXT_CurrencyIsoCode__c != NULL';

  @TestVisible
  private static Date todayOverride;
  @TestVisible
  private static Integer maxRowsOverride;

  public class TimesheetException extends Exception {
  }

  public class ContractOption {
    public Id contractId;
    public String label;
    public Id holderId;
    public String holderLabel;
    public Decimal rate;
    public String currencyIsoCode;
  }

  public class EntryRequest {
    /** DRAFT or REJECTED entry of this screen being corrected; null for a new day. */
    public Id workRecordId;
    public Id contractId;
    public Date workDate;
    public String startTime;
    public String breakStart;
    public String breakEnd;
    public String endTime;
    public String note;
  }

  public class SubmitRequest {
    public Id workRecordId;
  }

  public class EntryResult {
    public Id workRecordId;
    public Decimal hours;
    public String status;
    /** False when an existing draft/rejected entry was updated. */
    public Boolean created = false;
  }

  public class ListQuery {
    public Integer year;
    public Integer month;
    public Date fromDate;
    public Date toDate;
    public Id contractId;
    public String billingStatus;
    public String recordStatus;
  }

  public class EntryView {
    public Id workRecordId;
    public String recordNumber;
    public Date workDate;
    public Id contractId;
    public String contractLabel;
    /** Clock times when written by this screen; otherwise the raw description. */
    public String times;
    public String note;
    public Decimal hours;
    public Decimal rate;
    public String currencyIsoCode;
    public Decimal totalAmount;
    public String status;
    public String billingStatus;
    public Decimal billedHours;
    public Boolean canSubmit = false;
    /** DRAFT/REJECTED entry written by this screen: its times can be corrected here. */
    public Boolean canEdit = false;
  }

  public class ListView {
    public Integer year;
    public Integer month;
    public Date fromDate;
    public Date toDate;
    public Boolean customPeriod = false;
    public Boolean truncated = false;
    public List<EntryView> entries = new List<EntryView>();
  }

  public class ForecastQuery {
    public Integer year;
    public Integer month;
    /** Destination bank account id, NO_DESTINATION or null for every destination. */
    public String destination;
  }

  public class Destination {
    public String key;
    /** Null for a wallet and for NO_DESTINATION: the screen names them. */
    public String label;
    public Boolean wallet = false;
  }

  public class CurrencyTotal {
    public String currencyIsoCode;
    public Decimal approvedHours = 0;
    public Decimal pendingHours = 0;
    public Decimal approvedAmount = 0;
    public Decimal pendingAmount = 0;
  }

  public class ForecastLine {
    public Id contractId;
    public String contractLabel;
    public String currencyIsoCode;
    public Decimal approvedHours = 0;
    public Decimal approvedAmount = 0;
    public Decimal pendingHours = 0;
    public Decimal pendingAmount = 0;
  }

  public class ForecastGroup {
    public Destination destination;
    public List<ForecastLine> lines = new List<ForecastLine>();
    public List<CurrencyTotal> totals = new List<CurrencyTotal>();
  }

  public class ForecastView {
    public Integer year;
    public Integer month;
    /** Every destination of the month, regardless of the filter. */
    public List<Destination> destinations = new List<Destination>();
    public List<ForecastGroup> groups = new List<ForecastGroup>();
    public List<CurrencyTotal> totals = new List<CurrencyTotal>();
  }

  // ---------------------------------------------------------------- context

  public Boolean canRegister() {
    return Schema.SObjectType.AXF_OBJ_WorkRecord__c.isCreateable();
  }

  public Boolean canSubmit() {
    return Schema.SObjectType.AXF_OBJ_WorkRecord__c.isUpdateable();
  }

  private Map<Id, String> holderCache;
  /** Authorized holders and their labels; the context service is the only authority. */
  private Map<Id, String> holders() {
    if (holderCache == null) {
      holderCache = new Map<Id, String>();
      for (
        AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
      ) {
        holderCache.put(context.accountId, context.label);
      }
    }
    return holderCache;
  }

  // -------------------------------------------------------------- contracts

  /** @description Active service contracts (REVENUE, active HOURLY term with a rate) of the context. */
  public List<ContractOption> contracts() {
    List<ContractOption> result = new List<ContractOption>();
    for (AXF_OBJ_Contract__c row : queryContracts(null, true)) {
      ContractOption option = new ContractOption();
      option.contractId = row.Id;
      option.label = contractLabel(row);
      option.holderId = row.AXF_CTR_LKP_Account__c;
      option.holderLabel = holders().get(row.AXF_CTR_LKP_Account__c);
      option.rate = row.AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_CUR_Rate__c;
      option.currencyIsoCode = row.AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_TXT_CurrencyIsoCode__c;
      result.add(option);
    }
    return result;
  }

  private List<AXF_OBJ_Contract__c> queryContracts(
    Set<Id> contractIds,
    Boolean eligibleOnly
  ) {
    Set<Id> holderIds = holders().keySet();
    if (holderIds.isEmpty() || (contractIds != null && contractIds.isEmpty())) {
      return new List<AXF_OBJ_Contract__c>();
    }
    String soql =
      'SELECT ' +
      CONTRACT_FIELDS +
      ' FROM AXF_OBJ_Contract__c' +
      ' WHERE AXF_CTR_LKP_Account__c IN :holderIds AND AXF_CTR_PKL_Type__c = :revenue' +
      (eligibleOnly ? ELIGIBLE_FILTER : '') +
      (contractIds == null ? '' : ' AND Id IN :contractIds') +
      // A given id set is already bounded; only the open listing is capped.
      ' ORDER BY Name' +
      (contractIds == null ? ' LIMIT :maxContracts' : '');
    return Database.queryWithBinds(
      soql,
      new Map<String, Object>{
        'holderIds' => holderIds,
        'revenue' => TYPE_REVENUE,
        'contractIds' => contractIds == null ? new Set<Id>() : contractIds,
        'maxContracts' => MAX_CONTRACTS
      },
      AccessLevel.USER_MODE
    );
  }

  private static String contractLabel(AXF_OBJ_Contract__c row) {
    return String.isBlank(row.AXF_CTR_TXT_Title__c)
      ? row.Name
      : row.Name + ' · ' + row.AXF_CTR_TXT_Title__c;
  }

  // ------------------------------------------------------------ registering

  /**
   * @description Registers one day of work or corrects a DRAFT/REJECTED entry (`workRecordId`).
   * The clock times identify the shift: resubmitting the same times updates a draft/rejected entry
   * (its note) and is refused once the entry left the editable states. Overlapping shifts of the
   * same day and contract are refused.
   */
  public EntryResult register(EntryRequest request) {
    check(
      request != null &&
        request.workDate != null &&
        request.contractId != null &&
        request.contractId.getSObjectType() ==
        AXF_OBJ_Contract__c.SObjectType &&
        (request.workRecordId == null ||
        request.workRecordId.getSObjectType() ==
        AXF_OBJ_WorkRecord__c.SObjectType) &&
        (request.note == null ||
        request.note.trim().length() <= MAX_NOTE_LENGTH),
      CODE_INVALID_INPUT
    );
    Integer startMinute = minuteOf(request.startTime);
    Integer endMinute = minuteOf(request.endTime);
    String times;
    Integer worked;
    if (
      String.isBlank(request.breakStart) && String.isBlank(request.breakEnd)
    ) {
      check(startMinute < endMinute, CODE_INVALID_INPUT);
      times = request.startTime + '-' + request.endTime;
      worked = endMinute - startMinute;
    } else {
      Integer breakStartMinute = minuteOf(request.breakStart);
      Integer breakEndMinute = minuteOf(request.breakEnd);
      check(
        startMinute < breakStartMinute &&
          breakStartMinute < breakEndMinute &&
          breakEndMinute < endMinute,
        CODE_INVALID_INPUT
      );
      times =
        request.startTime +
        '-' +
        request.breakStart +
        TIMES_SEPARATOR +
        request.breakEnd +
        '-' +
        request.endTime;
      worked = (endMinute - startMinute) - (breakEndMinute - breakStartMinute);
    }
    Decimal hours = Decimal.valueOf(worked)
      .divide(60, 2, System.RoundingMode.HALF_UP);
    check(hours > 0 && hours <= 24, CODE_INVALID_INPUT);
    check(canRegister(), CODE_NOT_ACCESSIBLE);

    List<AXF_OBJ_Contract__c> rows = queryContracts(
      new Set<Id>{ request.contractId },
      true
    );
    check(rows.size() == 1, CODE_NOT_ACCESSIBLE);
    AXF_OBJ_Contract__c contract = rows[0];
    check(withinWindow(contract, request.workDate), CODE_INVALID_INPUT);

    Id targetId = request.workRecordId;
    if (targetId != null) {
      AXF_OBJ_WorkRecord__c editing = readEntry(targetId);
      check(editing.AXF_WR_LKP_Contract__c == contract.Id, CODE_INVALID_INPUT);
      check(
        SUBMITTABLE.contains(editing.AXF_WR_PKL_Status__c),
        CODE_INVALID_STATE
      );
    }
    // The clock times are part of the identity: two shifts of one day never collapse, while an
    // identical resubmission finds the entry it already created.
    String hash = EncodingUtil.convertToHex(
      Crypto.generateDigest(
        'SHA-256',
        Blob.valueOf(
          'AXF157|' +
            contract.Id +
            '|' +
            String.valueOf(request.workDate) +
            '|' +
            times
        )
      )
    );
    // Same lookup scope as the engine's idempotency check (class sharing, by evidence hash).
    List<AXF_OBJ_WorkRecord__c> sameShift = [
      SELECT Id, AXF_WR_PKL_Status__c
      FROM AXF_OBJ_WorkRecord__c
      WHERE AXF_WR_EXI_EvidenceHash__c = :hash
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    Boolean sameRecord = !sameShift.isEmpty();
    if (sameRecord) {
      check(
        SUBMITTABLE.contains(sameShift[0].AXF_WR_PKL_Status__c) &&
        (targetId == null ||
        targetId == sameShift[0].Id),
        CODE_ALREADY_REGISTERED
      );
      targetId = sameShift[0].Id;
    }
    check(targetId == null || canSubmit(), CODE_NOT_ACCESSIBLE);
    check(
      !overlaps(contract.Id, request.workDate, intervalsOf(times), targetId),
      CODE_INVALID_INPUT
    );

    String description = String.isBlank(request.note)
      ? times
      : times + NOTE_SEPARATOR + request.note.trim();
    ALT_CLS_WorkRecordService engine = new ALT_CLS_WorkRecordService();
    Id savedId = targetId;
    if (sameRecord) {
      // The engine returns a record found by its evidence hash unchanged, so the only field that
      // can differ for the same shift (the note in the description) is updated here.
      update as user new AXF_OBJ_WorkRecord__c(
        Id = targetId,
        AXF_WR_TXT_Description__c = description
      );
    } else {
      ALT_CLS_WorkRecordService.WorkRecordInputDTO input = new ALT_CLS_WorkRecordService.WorkRecordInputDTO();
      input.workRecordId = targetId;
      input.contractId = contract.Id;
      input.termVersionId = contract.AXF_CTR_LKP_ActiveTermVersion__c;
      input.startDate = request.workDate;
      input.endDate = request.workDate;
      input.quantity = hours;
      input.rate = contract.AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_CUR_Rate__c;
      input.currencyIsoCode = contract.AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_TXT_CurrencyIsoCode__c;
      input.source = ALT_CLS_WorkRecordService.SOURCE_MANUAL;
      input.description = description;
      input.externalEvidenceHash = hash;
      savedId = engine.registerWorkRecord(input).workRecordId;
    }
    EntryResult result = result(engine.getWorkRecordDetail(savedId));
    result.created = targetId == null;
    return result;
  }

  /** Not in the future, inside the contract and inside the active term. */
  private static Boolean withinWindow(AXF_OBJ_Contract__c contract, Date day) {
    AXF_OBJ_ContractTermVersion__c term = contract.AXF_CTR_LKP_ActiveTermVersion__r;
    Date contractEnd = contract.AXF_CTR_DAT_TerminationEffectiveDate__c != null
      ? contract.AXF_CTR_DAT_TerminationEffectiveDate__c
      : contract.AXF_CTR_DAT_EndDate__c;
    return day <= today() &&
      (contract.AXF_CTR_DAT_StartDate__c == null ||
      day >= contract.AXF_CTR_DAT_StartDate__c) &&
      (contractEnd == null ||
      day <= contractEnd) &&
      (term.AXF_CTV_DAT_EffectiveFrom__c == null ||
      day >= term.AXF_CTV_DAT_EffectiveFrom__c) &&
      (term.AXF_CTV_DAT_EffectiveTo__c == null ||
      day <= term.AXF_CTV_DAT_EffectiveTo__c);
  }

  /**
   * Whether a shift overlaps a same-day entry of the contract that still holds its hours. Entries
   * without times in this screen's format cannot be compared and are ignored.
   */
  private static Boolean overlaps(
    Id contractId,
    Date day,
    List<List<Integer>> shift,
    Id excludedId
  ) {
    for (AXF_OBJ_WorkRecord__c row : [
      SELECT Id, AXF_WR_TXT_Description__c
      FROM AXF_OBJ_WorkRecord__c
      WHERE
        AXF_WR_LKP_Contract__c = :contractId
        AND AXF_WR_DAT_StartDate__c = :day
        AND AXF_WR_PKL_Status__c NOT IN :RELEASED_STATUSES
        AND Id != :excludedId
      WITH USER_MODE
    ]) {
      for (
        List<Integer> existing : intervalsOf(row.AXF_WR_TXT_Description__c)
      ) {
        for (List<Integer> candidate : shift) {
          if (candidate[0] < existing[1] && existing[0] < candidate[1]) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /** Worked intervals (minutes) of a description in this screen's format; empty otherwise. */
  private static List<List<Integer>> intervalsOf(String description) {
    List<List<Integer>> result = new List<List<Integer>>();
    Matcher parsed = description == null
      ? null
      : SCREEN_DESCRIPTION.matcher(description);
    if (parsed == null || !parsed.matches()) {
      return result;
    }
    for (String range : parsed.group(1).split(' \\| ')) {
      result.add(
        new List<Integer>{
          clockMinutes(range.substringBefore('-')),
          clockMinutes(range.substringAfter('-'))
        }
      );
    }
    return result;
  }

  private static Integer clockMinutes(String clock) {
    return Integer.valueOf(clock.substring(0, 2)) * 60 +
      Integer.valueOf(clock.substring(3, 5));
  }

  /** Minutes since midnight of an `HH:mm` clock time; anything else is invalid input. */
  private static Integer minuteOf(String clock) {
    check(
      String.isNotBlank(clock) && CLOCK_PATTERN.matcher(clock).matches(),
      CODE_INVALID_INPUT
    );
    return clockMinutes(clock);
  }

  // ------------------------------------------------------------- submitting

  /** @description DRAFT or REJECTED -> SUBMITTED; approval stays in contract management. */
  public EntryResult submit(SubmitRequest request) {
    check(
      request != null &&
        request.workRecordId != null &&
        request.workRecordId.getSObjectType() ==
        AXF_OBJ_WorkRecord__c.SObjectType,
      CODE_INVALID_INPUT
    );
    check(canSubmit(), CODE_NOT_ACCESSIBLE);
    check(
      SUBMITTABLE.contains(
        readEntry(request.workRecordId).AXF_WR_PKL_Status__c
      ),
      CODE_INVALID_STATE
    );
    return result(
      new ALT_CLS_WorkRecordService().submitWorkRecord(request.workRecordId)
    );
  }

  /** One entry of a revenue contract of the context; anything else is indistinguishable from missing. */
  private AXF_OBJ_WorkRecord__c readEntry(Id workRecordId) {
    List<AXF_OBJ_WorkRecord__c> rows = [
      SELECT
        Id,
        AXF_WR_PKL_Status__c,
        AXF_WR_LKP_Contract__c,
        AXF_WR_LKP_Contract__r.AXF_CTR_LKP_Account__c,
        AXF_WR_LKP_Contract__r.AXF_CTR_PKL_Type__c
      FROM AXF_OBJ_WorkRecord__c
      WHERE Id = :workRecordId
      WITH USER_MODE
      LIMIT 1
    ];
    check(
      rows.size() == 1 &&
        rows[0].AXF_WR_LKP_Contract__r?.AXF_CTR_PKL_Type__c == TYPE_REVENUE &&
        holders()
          .containsKey(rows[0].AXF_WR_LKP_Contract__r?.AXF_CTR_LKP_Account__c),
      CODE_NOT_ACCESSIBLE
    );
    return rows[0];
  }

  private static EntryResult result(
    ALT_CLS_WorkRecordService.WorkRecordDetailDTO detail
  ) {
    EntryResult result = new EntryResult();
    result.workRecordId = detail.workRecordId;
    result.hours = detail.quantity;
    result.status = detail.status;
    return result;
  }

  // ---------------------------------------------------------------- listing

  /** @description Entries of the context in a month or custom period, with their billing status. */
  public ListView entries(ListQuery query) {
    check(query != null, CODE_INVALID_INPUT);
    check(
      (query.contractId == null ||
        query.contractId.getSObjectType() == AXF_OBJ_Contract__c.SObjectType) &&
        (query.billingStatus == null ||
        BILLING_STATUSES.contains(query.billingStatus)) &&
        (query.recordStatus == null ||
        RECORD_STATUSES.contains(query.recordStatus)),
      CODE_INVALID_INPUT
    );
    ListView result = new ListView();
    if (query.fromDate != null || query.toDate != null) {
      check(
        query.fromDate != null &&
          query.toDate != null &&
          query.fromDate <= query.toDate &&
          query.fromDate.daysBetween(query.toDate) < MAX_PERIOD_DAYS,
        CODE_INVALID_INPUT
      );
      result.customPeriod = true;
      result.fromDate = query.fromDate;
      result.toDate = query.toDate;
      result.year = query.fromDate.year();
      result.month = query.fromDate.month();
    } else {
      Date first = monthStart(query.year, query.month);
      result.year = first.year();
      result.month = first.month();
      result.fromDate = first;
      result.toDate = first.addMonths(1).addDays(-1);
    }

    Set<Id> holderIds = holders().keySet();
    if (holderIds.isEmpty()) {
      return result;
    }
    String soql =
      'SELECT Id, Name, AXF_WR_LKP_Contract__c, AXF_WR_LKP_Contract__r.Name,' +
      ' AXF_WR_LKP_Contract__r.AXF_CTR_TXT_Title__c, AXF_WR_DAT_StartDate__c,' +
      ' AXF_WR_NUM_Quantity__c, AXF_WR_CUR_Rate__c, AXF_WR_TXT_CurrencyIsoCode__c,' +
      ' AXF_WR_CUR_TotalAmount__c, AXF_WR_PKL_Status__c, AXF_WR_TXT_Description__c' +
      ' FROM AXF_OBJ_WorkRecord__c' +
      ' WHERE AXF_WR_LKP_Contract__r.AXF_CTR_LKP_Account__c IN :holderIds' +
      ' AND AXF_WR_LKP_Contract__r.AXF_CTR_PKL_Type__c = :revenue' +
      ' AND AXF_WR_DAT_StartDate__c >= :fromDate AND AXF_WR_DAT_StartDate__c <= :toDate' +
      (query.contractId == null
        ? ''
        : ' AND AXF_WR_LKP_Contract__c = :contractId') +
      (query.recordStatus == null
        ? ''
        : ' AND AXF_WR_PKL_Status__c = :recordStatus') +
      ' ORDER BY AXF_WR_DAT_StartDate__c DESC, CreatedDate DESC, Id DESC' +
      ' LIMIT :maxRows';
    Integer rowLimit = maxRowsOverride == null ? MAX_ROWS : maxRowsOverride;
    List<AXF_OBJ_WorkRecord__c> rows = Database.queryWithBinds(
      soql,
      new Map<String, Object>{
        'holderIds' => holderIds,
        'revenue' => TYPE_REVENUE,
        'fromDate' => result.fromDate,
        'toDate' => result.toDate,
        'contractId' => query.contractId,
        'recordStatus' => query.recordStatus,
        'maxRows' => rowLimit + 1
      },
      AccessLevel.USER_MODE
    );
    if (rows.size() > rowLimit) {
      result.truncated = true;
      rows.remove(rowLimit);
    }

    Set<Id> approved = new Set<Id>();
    for (AXF_OBJ_WorkRecord__c row : rows) {
      if (
        row.AXF_WR_PKL_Status__c == ALT_CLS_WorkRecordService.STATUS_APPROVED
      ) {
        approved.add(row.Id);
      }
    }
    // Existing billing rule: allocations of effective, non-cancelled documents; only approved
    // work can be billed.
    Map<Id, Decimal> allocated = ALT_CLS_BillingIntegrity.allocatedByWorkRecord(
      approved,
      ALT_CLS_BillingDraftService.EFFECTIVE_STATES
    );
    Boolean submitAllowed = canSubmit();
    Boolean editAllowed = submitAllowed && canRegister();
    for (AXF_OBJ_WorkRecord__c row : rows) {
      EntryView view = entryView(
        row,
        allocated.get(row.Id),
        submitAllowed,
        editAllowed
      );
      if (
        query.billingStatus == null ||
        query.billingStatus == view.billingStatus
      ) {
        result.entries.add(view);
      }
    }
    return result;
  }

  private static EntryView entryView(
    AXF_OBJ_WorkRecord__c row,
    Decimal allocated,
    Boolean submitAllowed,
    Boolean editAllowed
  ) {
    EntryView view = new EntryView();
    view.workRecordId = row.Id;
    view.recordNumber = row.Name;
    view.workDate = row.AXF_WR_DAT_StartDate__c;
    view.contractId = row.AXF_WR_LKP_Contract__c;
    view.contractLabel = contractLabel(row.AXF_WR_LKP_Contract__r);
    view.hours = row.AXF_WR_NUM_Quantity__c;
    view.rate = row.AXF_WR_CUR_Rate__c;
    view.currencyIsoCode = row.AXF_WR_TXT_CurrencyIsoCode__c;
    view.totalAmount = row.AXF_WR_CUR_TotalAmount__c;
    view.status = row.AXF_WR_PKL_Status__c;
    view.canSubmit = submitAllowed && SUBMITTABLE.contains(view.status);
    String description = row.AXF_WR_TXT_Description__c;
    Matcher parsed = description == null
      ? null
      : SCREEN_DESCRIPTION.matcher(description);
    if (parsed != null && parsed.matches()) {
      view.times = parsed.group(1);
      view.note = parsed.group(2);
      view.canEdit = editAllowed && SUBMITTABLE.contains(view.status);
    } else {
      view.times = description;
    }
    view.billedHours = allocated == null ? 0 : allocated;
    Decimal approvedHours = row.AXF_WR_NUM_Quantity__c == null
      ? 0
      : row.AXF_WR_NUM_Quantity__c;
    if (view.status != ALT_CLS_WorkRecordService.STATUS_APPROVED) {
      view.billingStatus = NOT_BILLABLE;
    } else if (view.billedHours > 0 && view.billedHours >= approvedHours) {
      view.billingStatus = BILLED;
    } else if (view.billedHours > 0) {
      view.billingStatus = PARTIAL;
    } else {
      view.billingStatus = UNBILLED;
    }
    return view;
  }

  // --------------------------------------------------------------- forecast

  /**
   * @description Revenue of a month per contract: approved amount and, apart, the amount still
   * awaiting approval, grouped by destination account. Currencies are never summed together.
   */
  public ForecastView forecast(ForecastQuery query) {
    check(query != null, CODE_INVALID_INPUT);
    check(
      query.destination == null ||
        query.destination == NO_DESTINATION ||
        isBankAccountId(query.destination),
      CODE_INVALID_INPUT
    );
    Date first = monthStart(query.year, query.month);
    Date last = first.addMonths(1).addDays(-1);
    ForecastView result = new ForecastView();
    result.year = first.year();
    result.month = first.month();
    Set<Id> holderIds = holders().keySet();
    if (holderIds.isEmpty()) {
      return result;
    }
    List<AggregateResult> sums = [
      SELECT
        AXF_WR_LKP_Contract__c contractId,
        AXF_WR_LKP_TermVersion__c termId,
        AXF_WR_PKL_Status__c status,
        AXF_WR_TXT_CurrencyIsoCode__c iso,
        SUM(AXF_WR_NUM_Quantity__c) hours,
        SUM(AXF_WR_CUR_TotalAmount__c) amount
      FROM AXF_OBJ_WorkRecord__c
      WHERE
        AXF_WR_LKP_Contract__r.AXF_CTR_LKP_Account__c IN :holderIds
        AND AXF_WR_LKP_Contract__r.AXF_CTR_PKL_Type__c = :TYPE_REVENUE
        AND AXF_WR_PKL_Status__c IN :FORECAST_STATUSES
        AND AXF_WR_DAT_StartDate__c >= :first
        AND AXF_WR_DAT_StartDate__c <= :last
      WITH USER_MODE
      GROUP BY
        AXF_WR_LKP_Contract__c,
        AXF_WR_LKP_TermVersion__c,
        AXF_WR_PKL_Status__c,
        AXF_WR_TXT_CurrencyIsoCode__c
    ];
    Set<Id> contractIds = new Set<Id>();
    Set<Id> termIds = new Set<Id>();
    for (AggregateResult sum : sums) {
      contractIds.add((Id) sum.get('contractId'));
      if (sum.get('termId') != null) {
        termIds.add((Id) sum.get('termId'));
      }
    }
    Map<Id, AXF_OBJ_Contract__c> contracts = new Map<Id, AXF_OBJ_Contract__c>(
      queryContracts(contractIds, false)
    );
    // The destination is the one of the term recorded on the entry, so a later term change never
    // moves past revenue; entries without a term fall back to the active term.
    Map<Id, AXF_OBJ_ContractTermVersion__c> terms = new Map<Id, AXF_OBJ_ContractTermVersion__c>(
      [
        SELECT
          Id,
          AXF_CTV_LKP_PreferredBankAccount__c,
          AXF_CTV_LKP_PreferredBankAccount__r.Name,
          AXF_CTV_LKP_PreferredBankAccount__r.AXF_BA_TXT_InstitutionName__c,
          AXF_CTV_LKP_PreferredBankAccount__r.AXF_BA_TXT_NumberMasked__c,
          AXF_CTV_LKP_PreferredBankAccount__r.AXF_BA_TXT_Type__c
        FROM AXF_OBJ_ContractTermVersion__c
        WHERE Id IN :termIds
        WITH USER_MODE
      ]
    );

    Map<String, ForecastLine> lines = new Map<String, ForecastLine>();
    Map<String, Destination> destinationsByKey = new Map<String, Destination>();
    Map<String, String> lineDestination = new Map<String, String>();
    for (AggregateResult sum : sums) {
      AXF_OBJ_Contract__c contract = contracts.get((Id) sum.get('contractId'));
      if (contract == null) {
        continue;
      }
      String iso = (String) sum.get('iso');
      AXF_OBJ_ContractTermVersion__c term = terms.get((Id) sum.get('termId'));
      Destination destination = toDestination(
        term == null ? contract.AXF_CTR_LKP_ActiveTermVersion__r : term
      );
      String lineKey = contract.Id + '|' + iso + '|' + destination.key;
      ForecastLine line = lines.get(lineKey);
      if (line == null) {
        line = new ForecastLine();
        line.contractId = contract.Id;
        line.contractLabel = contractLabel(contract);
        line.currencyIsoCode = iso;
        lines.put(lineKey, line);
        destinationsByKey.put(destination.key, destination);
        lineDestination.put(lineKey, destination.key);
      }
      Decimal hours = nz((Decimal) sum.get('hours'));
      Decimal amount = nz((Decimal) sum.get('amount'));
      if (
        (String) sum.get('status') == ALT_CLS_WorkRecordService.STATUS_APPROVED
      ) {
        line.approvedHours += hours;
        line.approvedAmount += amount;
      } else {
        line.pendingHours += hours;
        line.pendingAmount += amount;
      }
    }

    // Destinations by label, "no destination" last; lines by contract.
    Map<String, String> destinationBySortKey = new Map<String, String>();
    for (Destination destination : destinationsByKey.values()) {
      destinationBySortKey.put(
        (destination.key == NO_DESTINATION ? '2' : '1') +
          (destination.label == null ? '' : destination.label.toLowerCase()) +
          '|' +
          destination.key,
        destination.key
      );
    }
    List<String> sortKeys = new List<String>(destinationBySortKey.keySet());
    sortKeys.sort();
    List<String> lineKeys = new List<String>();
    Map<String, String> lineBySortKey = new Map<String, String>();
    for (String lineKey : lines.keySet()) {
      String sortKey = lines.get(lineKey).contractLabel + '|' + lineKey;
      lineKeys.add(sortKey);
      lineBySortKey.put(sortKey, lineKey);
    }
    lineKeys.sort();

    Map<String, CurrencyTotal> grandTotals = new Map<String, CurrencyTotal>();
    for (String sortKey : sortKeys) {
      Destination destination = destinationsByKey.get(
        destinationBySortKey.get(sortKey)
      );
      result.destinations.add(destination);
      if (query.destination != null && query.destination != destination.key) {
        continue;
      }
      ForecastGroup forecastGroup = new ForecastGroup();
      forecastGroup.destination = destination;
      Map<String, CurrencyTotal> groupTotals = new Map<String, CurrencyTotal>();
      for (String lineSortKey : lineKeys) {
        String lineKey = lineBySortKey.get(lineSortKey);
        if (lineDestination.get(lineKey) != destination.key) {
          continue;
        }
        ForecastLine line = lines.get(lineKey);
        forecastGroup.lines.add(line);
        accumulate(groupTotals, line);
        accumulate(grandTotals, line);
      }
      forecastGroup.totals = sortedTotals(groupTotals);
      result.groups.add(forecastGroup);
    }
    result.totals = sortedTotals(grandTotals);
    return result;
  }

  private static Destination toDestination(
    AXF_OBJ_ContractTermVersion__c term
  ) {
    Destination result = new Destination();
    AXF_OBJ_BankAccount__c account = term?.AXF_CTV_LKP_PreferredBankAccount__r;
    Id accountId = term?.AXF_CTV_LKP_PreferredBankAccount__c;
    if (accountId == null) {
      result.key = NO_DESTINATION;
      return result;
    }
    result.key = accountId;
    if (account == null) {
      return result;
    }
    result.wallet = 'WALLET'.equalsIgnoreCase(account.AXF_BA_TXT_Type__c);
    if (!result.wallet) {
      String label = String.join(
        new List<String>{
          String.isBlank(account.AXF_BA_TXT_InstitutionName__c)
            ? ''
            : account.AXF_BA_TXT_InstitutionName__c,
          String.isBlank(account.AXF_BA_TXT_NumberMasked__c)
            ? ''
            : account.AXF_BA_TXT_NumberMasked__c
        },
        ' '
      );
      result.label = String.isBlank(label) ? account.Name : label.trim();
    }
    return result;
  }

  private static void accumulate(
    Map<String, CurrencyTotal> totals,
    ForecastLine line
  ) {
    CurrencyTotal total = totals.get(line.currencyIsoCode);
    if (total == null) {
      total = new CurrencyTotal();
      total.currencyIsoCode = line.currencyIsoCode;
      totals.put(line.currencyIsoCode, total);
    }
    total.approvedHours += line.approvedHours;
    total.approvedAmount += line.approvedAmount;
    total.pendingHours += line.pendingHours;
    total.pendingAmount += line.pendingAmount;
  }

  private static List<CurrencyTotal> sortedTotals(
    Map<String, CurrencyTotal> totals
  ) {
    List<String> isos = new List<String>(totals.keySet());
    isos.sort();
    List<CurrencyTotal> result = new List<CurrencyTotal>();
    for (String iso : isos) {
      result.add(totals.get(iso));
    }
    return result;
  }

  // ---------------------------------------------------------------- helpers

  private static Boolean isBankAccountId(String value) {
    try {
      return Id.valueOf(value).getSObjectType() ==
        AXF_OBJ_BankAccount__c.SObjectType;
    } catch (Exception invalid) {
      return false;
    }
  }

  /** Today in the running user's time zone. */
  private static Date today() {
    return todayOverride == null ? Date.today() : todayOverride;
  }

  private static Date monthStart(Integer year, Integer month) {
    Integer y = year == null ? today().year() : year;
    Integer m = month == null ? today().month() : month;
    check(y >= 1900 && y <= 9999 && m >= 1 && m <= 12, CODE_INVALID_INPUT);
    return Date.newInstance(y, m, 1);
  }

  private static Decimal nz(Decimal value) {
    return value == null ? 0 : value;
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new TimesheetException(code);
    }
  }
}
