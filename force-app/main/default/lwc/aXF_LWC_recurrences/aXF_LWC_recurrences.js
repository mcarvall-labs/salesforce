import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getContext";
import getSources from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getSources";
import listRecurrences from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.listRecurrences";
import getDetail from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getDetail";
import createRecurrence from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.createRecurrence";
import editAmount from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.editAmount";
import terminate from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.terminate";
import labels from "./labels";
import { failureCode, parseFailure, format, newOperationKey } from "./failures";

/** Periodicity options of the screen and the schedule period they stand for (AXF-155). */
const PERIODS = {
  WEEKLY: { periodDays: 7, periodMonths: null },
  BIWEEKLY: { periodDays: 14, periodMonths: null },
  MONTHLY: { periodDays: null, periodMonths: 1 },
  BIMONTHLY: { periodDays: null, periodMonths: 2 },
  QUARTERLY: { periodDays: null, periodMonths: 3 },
  CUSTOM: { periodDays: null, periodMonths: null }
};
const MAX_PERIOD_MONTHS = 120;
/** Materialized horizon in months (weekly: one less, so the window fits 50 occurrences). */
const HORIZON_MONTHS = 12;
const WEEKLY_HORIZON_MONTHS = 11;
const STATE_ACTIVE = "ACTIVE";

function todayIso() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function isoOf(d) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** First day of the current month: a recurrence never backfills earlier occurrences. */
function monthStartIso() {
  const d = new Date();
  return isoOf(new Date(d.getFullYear(), d.getMonth(), 1));
}

/** Last day of the creation horizon: current month plus `months - 1`. */
function horizonEndIso(months) {
  const d = new Date();
  return isoOf(new Date(d.getFullYear(), d.getMonth() + months, 0));
}

function parseIsoDate(value) {
  if (!value) {
    return null;
  }
  const [y, m, d] = String(value).split("-").map(Number);
  return new Date(y, m - 1, d);
}

function emptyForm() {
  return {
    accountId: null,
    description: "",
    direction: "DEBIT",
    amount: null,
    currencyIsoCode: "BRL",
    firstDueDate: todayIso(),
    periodicity: "MONTHLY",
    periodMonths: null,
    sourceKey: null
  };
}

/** A positive amount with at most two decimal places, as typed. */
function validMoney(value) {
  const text = String(
    value === null || value === undefined ? "" : value
  ).trim();
  return /^\d+(\.\d{1,2})?$/.test(text) && Number(text) > 0;
}

function sourceKeyOf(bankAccountId, creditCardId) {
  if (creditCardId) {
    return `CARD:${creditCardId}`;
  }
  return bankAccountId ? `BANK:${bankAccountId}` : null;
}

export default class AxfLwcRecurrences extends LightningElement {
  labels = labels;
  context;
  loading = true;
  error;
  message;
  messageIsError = false;
  recurrences = [];
  showForm = false;
  form = emptyForm();
  formError;
  sources = [];
  sourcesLoading = false;
  sourcesSeq = 0;
  createKey;
  selectedId;
  detail;
  detailLoading = false;
  detailSeq = 0;
  editingId;
  editAmountDraft;
  editKey;
  endingId;
  endDateDraft;
  endKey;
  busy = false;
  prefill;
  prefillApplied;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const state = (pageRef && pageRef.state) || {};
    const keys = [
      "c__accountId",
      "c__direction",
      "c__amount",
      "c__firstDueDate",
      "c__currencyIsoCode",
      "c__bankAccountId",
      "c__creditCardId",
      "c__description"
    ];
    if (!keys.some((key) => state[key])) {
      return;
    }
    const signature = keys.map((key) => state[key] || "").join("|");
    if (signature === this.prefillApplied) {
      return;
    }
    this.prefill = { ...state, signature };
    this.applyPrefill();
  }

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      if (data.canUse) {
        this.loadRecurrences();
        this.applyPrefill();
      } else {
        this.loading = false;
      }
    } else if (error) {
      this.error = parseFailure(error);
      this.loading = false;
    }
  }

  // ------------------------------------------------------------ getters

  get noCapability() {
    return Boolean(this.context) && !this.context.canUse;
  }
  get canManage() {
    return Boolean(this.context) && this.context.canManage === true;
  }
  get showReadOnly() {
    return Boolean(this.context) && this.context.canUse && !this.canManage;
  }
  get showNewButton() {
    return this.canManage && !this.showForm;
  }
  get hasRecurrences() {
    return this.recurrences.length > 0;
  }
  get showEmpty() {
    return !this.loading && this.context?.canUse && !this.hasRecurrences;
  }
  get messageClass() {
    return this.messageIsError
      ? "slds-notify slds-notify_alert slds-alert_error slds-var-m-bottom_small"
      : "slds-notify slds-notify_alert slds-alert_success slds-var-m-bottom_small";
  }

  get holderOptions() {
    return ((this.context && this.context.holders) || []).map((h) => ({
      label: h.label,
      value: h.accountId
    }));
  }
  get natureOptions() {
    return [
      { label: labels.natureDEBIT, value: "DEBIT" },
      { label: labels.natureCREDIT, value: "CREDIT" }
    ];
  }
  get periodicityOptions() {
    return Object.keys(PERIODS).map((value) => ({
      label: labels[`period${value}`],
      value
    }));
  }
  get minFirstDueDate() {
    return monthStartIso();
  }
  get maxFirstDueDate() {
    return horizonEndIso(
      this.form.periodicity === "WEEKLY"
        ? WEEKLY_HORIZON_MONTHS
        : HORIZON_MONTHS
    );
  }
  get minEndDate() {
    return todayIso();
  }
  get isCustomPeriod() {
    return this.form.periodicity === "CUSTOM";
  }
  get sourceOptions() {
    return this.sources.map((s) => ({
      label: s.label,
      value: sourceKeyOf(s.bankAccountId, s.creditCardId)
    }));
  }
  get showNoSources() {
    return (
      Boolean(this.form.accountId) &&
      !this.sourcesLoading &&
      this.sources.length === 0
    );
  }
  get sourceDisabled() {
    return !this.form.accountId || this.sourcesLoading;
  }

  get recurrenceRows() {
    return this.recurrences.map((r) => {
      const name = r.description || labels.notAvailable;
      const active = r.state === STATE_ACTIVE;
      return {
        ...r,
        key: r.scheduleId,
        name,
        periodText: this.periodText(r),
        natureText:
          r.direction === "CREDIT" ? labels.natureCREDIT : labels.natureDEBIT,
        sourceText: r.sourceLabel || labels.notAvailable,
        nextDueText: r.nextDueDate
          ? this.formatDate(r.nextDueDate)
          : labels.notAvailable,
        stateText: active
          ? labels.stateACTIVE
          : format(labels.stateENDED, this.formatDate(r.terminationDate)),
        currency: r.currencyIsoCode || "BRL",
        selected: r.scheduleId === this.selectedId,
        rowClass: r.scheduleId === this.selectedId ? "slds-is-selected" : "",
        canChange: this.canManage && active,
        editing: r.scheduleId === this.editingId,
        ending: r.scheduleId === this.endingId,
        maxEndDate: this.maxEndOf(r),
        viewLabel: format(labels.viewOccurrencesFor, name),
        editLabel: format(labels.editAmountFor, name),
        endLabel: format(labels.endFor, name)
      };
    });
  }

  get selectedRecurrence() {
    return this.recurrences.find((r) => r.scheduleId === this.selectedId);
  }
  get detailCaption() {
    const selected = this.selectedRecurrence;
    return format(
      labels.occurrencesCaption,
      (selected && selected.description) || labels.notAvailable
    );
  }
  get occurrenceRows() {
    if (!this.detail) {
      return [];
    }
    const currency =
      (this.detail.recurrence && this.detail.recurrence.currencyIsoCode) ||
      "BRL";
    return this.detail.occurrences.map((o) => ({
      ...o,
      key: o.transactionId,
      dueText: this.formatDate(o.dueDate),
      statusText: labels[`occ${o.status}`] || o.status,
      currency,
      cancelled: o.status === "CANCELLED"
    }));
  }
  get hasOccurrences() {
    return Boolean(this.detail) && this.detail.occurrences.length > 0;
  }
  get showNoOccurrences() {
    return Boolean(this.detail) && !this.detailLoading && !this.hasOccurrences;
  }

  /** Ending is allowed from today up to the due date of the last persisted occurrence. */
  maxEndOf(r) {
    const today = todayIso();
    return r && r.lastDueDate && r.lastDueDate > today ? r.lastDueDate : today;
  }

  periodText(r) {
    if (r.periodDays === 7) {
      return labels.periodWEEKLY;
    }
    if (r.periodDays === 14) {
      return labels.periodBIWEEKLY;
    }
    if (r.periodMonths === 1) {
      return labels.periodMONTHLY;
    }
    if (r.periodMonths === 2) {
      return labels.periodBIMONTHLY;
    }
    if (r.periodMonths === 3) {
      return labels.periodQUARTERLY;
    }
    return r.periodMonths
      ? format(labels.periodEveryMonths, r.periodMonths)
      : labels.notAvailable;
  }

  formatDate(value) {
    const date = parseIsoDate(value);
    return date
      ? new Intl.DateTimeFormat(LOCALE, { dateStyle: "short" }).format(date)
      : labels.notAvailable;
  }

  // ------------------------------------------------------------ loading

  async loadRecurrences() {
    this.loading = true;
    try {
      this.recurrences = (await listRecurrences()) || [];
      this.error = undefined;
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.loading = false;
    }
  }

  async loadSources() {
    const seq = ++this.sourcesSeq;
    const accountId = this.form.accountId;
    if (!accountId) {
      this.sources = [];
      return;
    }
    this.sourcesLoading = true;
    try {
      const result = await getSources({
        request: JSON.stringify({ accountId })
      });
      if (seq !== this.sourcesSeq) {
        return;
      }
      this.sources = result || [];
      const keys = this.sourceOptions.map((o) => o.value);
      if (this.form.sourceKey && !keys.includes(this.form.sourceKey)) {
        this.form = { ...this.form, sourceKey: null };
      }
      this.applySourceCurrency();
    } catch (e) {
      if (seq === this.sourcesSeq) {
        this.sources = [];
        this.formError = parseFailure(e);
      }
    } finally {
      if (seq === this.sourcesSeq) {
        this.sourcesLoading = false;
      }
    }
  }

  async loadDetail(scheduleId) {
    const seq = ++this.detailSeq;
    this.detailLoading = true;
    try {
      const result = await getDetail({
        request: JSON.stringify({ scheduleId })
      });
      if (seq === this.detailSeq) {
        this.detail = result;
        this.moveFocus("[data-detail-heading]");
      }
    } catch (e) {
      if (seq === this.detailSeq) {
        this.detail = undefined;
        this.showMessage(parseFailure(e), true);
      }
    } finally {
      if (seq === this.detailSeq) {
        this.detailLoading = false;
      }
    }
  }

  /** The recurrence is posted in the currency of its origin. */
  applySourceCurrency() {
    const source = this.sources.find(
      (s) =>
        sourceKeyOf(s.bankAccountId, s.creditCardId) === this.form.sourceKey
    );
    if (source && source.currencyIsoCode) {
      this.form = { ...this.form, currencyIsoCode: source.currencyIsoCode };
    }
  }

  // ------------------------------------------------------------ prefill

  /** The entry wizard hands a recurring entry over pre-filled (AXF-153 -> AXF-155). */
  applyPrefill() {
    if (!this.prefill || !this.context || !this.canManage) {
      return;
    }
    const state = this.prefill;
    this.prefillApplied = state.signature;
    this.prefill = undefined;
    const holders = this.holderOptions.map((o) => o.value);
    const accountId = holders.includes(state.c__accountId)
      ? state.c__accountId
      : null;
    const amount = Number(state.c__amount);
    this.form = {
      ...emptyForm(),
      accountId,
      description: state.c__description || "",
      direction: state.c__direction === "CREDIT" ? "CREDIT" : "DEBIT",
      amount: amount > 0 ? amount : null,
      currencyIsoCode: state.c__currencyIsoCode || "BRL",
      firstDueDate: state.c__firstDueDate || todayIso(),
      sourceKey: accountId
        ? sourceKeyOf(state.c__bankAccountId, state.c__creditCardId)
        : null
    };
    this.openForm();
  }

  // ------------------------------------------------------------ create

  handleNew() {
    this.form = emptyForm();
    if (this.holderOptions.length === 1) {
      this.form = { ...this.form, accountId: this.holderOptions[0].value };
    }
    this.openForm();
  }

  openForm() {
    this.showForm = true;
    this.formError = undefined;
    this.createKey = undefined;
    this.sources = [];
    this.loadSources();
    this.moveFocus("[data-form-heading]");
  }

  handleCancelForm() {
    this.showForm = false;
    this.formError = undefined;
    this.createKey = undefined;
    this.moveFocus("[data-new]");
  }

  handleFormField(event) {
    const field = event.target.dataset.field;
    const value = event.detail ? event.detail.value : event.target.value;
    this.form = { ...this.form, [field]: value };
    // Another payload is another command: the idempotency key never outlives its content.
    this.createKey = undefined;
    this.formError = undefined;
    if (field === "accountId") {
      this.form = { ...this.form, sourceKey: null };
      this.loadSources();
    }
    if (field === "sourceKey") {
      this.applySourceCurrency();
    }
  }

  formRequest() {
    const f = this.form;
    const period = PERIODS[f.periodicity];
    const periodMonths =
      f.periodicity === "CUSTOM" ? Number(f.periodMonths) : period.periodMonths;
    const [kind, id] = (f.sourceKey || "").split(":");
    return {
      accountId: f.accountId,
      description: String(f.description || "").trim(),
      direction: f.direction,
      amount: Number(f.amount),
      currencyIsoCode: String(f.currencyIsoCode || "")
        .trim()
        .toUpperCase(),
      firstDueDate: f.firstDueDate,
      periodDays: period.periodDays,
      periodMonths: period.periodDays ? null : periodMonths,
      bankAccountId: kind === "BANK" ? id : null,
      creditCardId: kind === "CARD" ? id : null
    };
  }

  isValid(request) {
    const months = request.periodMonths;
    return (
      Boolean(request.accountId) &&
      request.description.length > 0 &&
      validMoney(this.form.amount) &&
      /^[A-Z]{3}$/.test(request.currencyIsoCode) &&
      Boolean(request.firstDueDate) &&
      request.firstDueDate >= this.minFirstDueDate &&
      request.firstDueDate <= this.maxFirstDueDate &&
      (Boolean(request.periodDays) ||
        (Number.isInteger(months) &&
          months >= 1 &&
          months <= MAX_PERIOD_MONTHS)) &&
      Boolean(request.bankAccountId || request.creditCardId)
    );
  }

  async handleCreate() {
    if (this.busy) {
      return;
    }
    const request = this.formRequest();
    if (!this.isValid(request)) {
      this.formError = labels.formInvalid;
      this.moveFocus("[data-form-error]");
      return;
    }
    if (!this.createKey) {
      this.createKey = newOperationKey();
    }
    this.busy = true;
    try {
      const result = await createRecurrence({
        request: JSON.stringify({ ...request, operationKey: this.createKey })
      });
      this.createKey = undefined;
      this.showForm = false;
      this.showMessage(format(labels.created, result.changedCount), false);
      await this.loadRecurrences();
    } catch (e) {
      this.formError = parseFailure(e);
      this.moveFocus("[data-form-error]");
    } finally {
      this.busy = false;
    }
  }

  // ------------------------------------------------------------ detail

  handleView(event) {
    const id = event.currentTarget.dataset.id;
    this.selectedId = id;
    this.detail = undefined;
    this.loadDetail(id);
  }

  handleCloseDetail() {
    this.detailSeq += 1;
    const id = this.selectedId;
    this.selectedId = undefined;
    this.detail = undefined;
    this.detailLoading = false;
    this.moveFocus(`[data-view="${id}"]`);
  }

  // ------------------------------------------------------------ edit / end

  handleEdit(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.recurrences.find((r) => r.scheduleId === id);
    this.endingId = undefined;
    this.editingId = id;
    this.editAmountDraft = row ? row.amount : null;
    this.editKey = undefined;
  }

  handleEditAmount(event) {
    this.editAmountDraft = event.detail
      ? event.detail.value
      : event.target.value;
    this.editKey = undefined;
  }

  handleCancelChange() {
    const id = this.editingId || this.endingId;
    this.editingId = undefined;
    this.endingId = undefined;
    this.editKey = undefined;
    this.endKey = undefined;
    this.moveFocus(`[data-view="${id}"]`);
  }

  async handleSaveAmount() {
    const row = this.recurrences.find((r) => r.scheduleId === this.editingId);
    const amount = Number(this.editAmountDraft);
    if (!row || !validMoney(this.editAmountDraft) || this.busy) {
      if (row && !this.busy) {
        this.showMessage(labels.codeINVALID_INPUT, true);
      }
      return;
    }
    if (!this.editKey) {
      this.editKey = newOperationKey();
    }
    await this.runChange(
      editAmount,
      {
        scheduleId: row.scheduleId,
        amount,
        expectedVersion: row.version,
        operationKey: this.editKey
      },
      labels.amountSaved
    );
  }

  handleEnd(event) {
    const id = event.currentTarget.dataset.id;
    this.editingId = undefined;
    this.endingId = id;
    this.endDateDraft = todayIso();
    this.endKey = undefined;
  }

  handleEndDate(event) {
    this.endDateDraft = event.detail ? event.detail.value : event.target.value;
    this.endKey = undefined;
  }

  async handleConfirmEnd() {
    const row = this.recurrences.find((r) => r.scheduleId === this.endingId);
    if (!row || this.busy) {
      return;
    }
    const date = this.endDateDraft;
    if (!date || date < todayIso() || date > this.maxEndOf(row)) {
      this.showMessage(labels.codeINVALID_INPUT, true);
      return;
    }
    if (!this.endKey) {
      this.endKey = newOperationKey();
    }
    await this.runChange(
      terminate,
      {
        scheduleId: row.scheduleId,
        terminationDate: this.endDateDraft,
        expectedVersion: row.version,
        operationKey: this.endKey
      },
      labels.ended
    );
  }

  async runChange(command, request, successLabel) {
    this.busy = true;
    try {
      const result = await command({ request: JSON.stringify(request) });
      this.editingId = undefined;
      this.endingId = undefined;
      this.editKey = undefined;
      this.endKey = undefined;
      this.showMessage(
        format(successLabel, result.changedCount, result.protectedCount),
        false
      );
      await this.refreshAfterChange(request.scheduleId);
    } catch (e) {
      this.showMessage(parseFailure(e), true);
      if (failureCode(e) === "CONFLICT") {
        // The recurrence moved on: reload it rather than retry on a stale version.
        this.editingId = undefined;
        this.endingId = undefined;
        await this.refreshAfterChange(request.scheduleId);
      }
    } finally {
      this.busy = false;
    }
  }

  async refreshAfterChange(scheduleId) {
    await this.loadRecurrences();
    if (this.selectedId === scheduleId) {
      await this.loadDetail(scheduleId);
    }
  }

  // ------------------------------------------------------------ helpers

  showMessage(text, isError) {
    this.message = text;
    this.messageIsError = isError;
    this.moveFocus("[data-message]");
  }

  moveFocus(selector) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const el = this.template.querySelector(selector);
      if (el) {
        el.focus();
      }
    });
  }
}
