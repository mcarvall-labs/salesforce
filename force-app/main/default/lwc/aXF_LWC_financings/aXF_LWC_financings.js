import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_Financings.getContext";
import listFinancings from "@salesforce/apex/AXF_CLS_CTRL_Financings.listFinancings";
import getDetail from "@salesforce/apex/AXF_CLS_CTRL_Financings.getDetail";
import previewSettlement from "@salesforce/apex/AXF_CLS_CTRL_Financings.previewSettlement";
import editAmount from "@salesforce/apex/AXF_CLS_CTRL_Financings.editAmount";
import terminate from "@salesforce/apex/AXF_CLS_CTRL_Financings.terminate";
import settle from "@salesforce/apex/AXF_CLS_CTRL_Financings.settle";
import labels from "./labels";
import { failureCode, parseFailure, format, newOperationKey } from "./failures";

const PLANNER_TAB = "AXF_ScheduleWizard";

function pad(n) {
  return String(n).padStart(2, "0");
}

function todayIso() {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function parseIsoDate(value) {
  if (!value) {
    return null;
  }
  const [y, m, d] = String(value).split("-").map(Number);
  return new Date(y, m - 1, d);
}

/** A positive amount with at most two decimal places, as typed. */
function validMoney(value) {
  const text = String(
    value === null || value === undefined ? "" : value
  ).trim();
  return /^\d+(\.\d{1,2})?$/.test(text) && Number(text) > 0;
}

/** Row identity: the schedule, or the legacy AXF-20 group key. */
function keyOf(f) {
  return f.scheduleId || `legacy:${f.legacyKey}`;
}

export default class AxfLwcFinancings extends NavigationMixin(
  LightningElement
) {
  labels = labels;
  context;
  loading = true;
  error;
  message;
  messageIsError = false;
  financings = [];
  selectedKey;
  detail;
  detailLoading = false;
  detailSeq = 0;
  editingKey;
  editAmountDraft;
  editKey;
  endingKey;
  endDateDraft;
  endKey;
  settlingKey;
  settlement;
  settleAmountDraft;
  settleDateDraft;
  settleKey;
  busy = false;

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      if (data.canUse) {
        this.loadFinancings();
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
  get hasFinancings() {
    return this.financings.length > 0;
  }
  get showEmpty() {
    return !this.loading && this.context?.canUse && !this.hasFinancings;
  }
  get messageClass() {
    return this.messageIsError
      ? "slds-notify slds-notify_alert slds-alert_error slds-var-m-bottom_small"
      : "slds-notify slds-notify_alert slds-alert_success slds-var-m-bottom_small";
  }
  get minDate() {
    return todayIso();
  }

  get financingRows() {
    return this.financings.map((f) => {
      const key = keyOf(f);
      const name = this.nameOf(f);
      const managed = !f.legacy;
      return {
        ...f,
        key,
        name,
        methodText: labels[`method${f.method}`] || f.method,
        progressText: format(
          labels.progress,
          f.paidCount || 0,
          f.totalInstallments || 0
        ),
        nextDueText: f.nextDueDate
          ? this.formatDate(f.nextDueDate)
          : labels.notAvailable,
        hasNextAmount: f.nextAmount !== null && f.nextAmount !== undefined,
        hasBalance:
          f.outstandingBalance !== null && f.outstandingBalance !== undefined,
        stateText: labels[`state${f.state}`] || f.state,
        currency: f.currencyIsoCode || "BRL",
        rowClass: key === this.selectedKey ? "slds-is-selected" : "",
        canEdit: managed && f.canEdit === true && this.canManage,
        canChange: managed && f.canChange === true && this.canManage,
        editing: key === this.editingKey,
        ending: key === this.endingKey,
        settling: key === this.settlingKey,
        idle:
          key !== this.editingKey &&
          key !== this.endingKey &&
          key !== this.settlingKey,
        maxEndDate: this.maxEndOf(f),
        viewLabel: format(labels.viewInstallmentsFor, name),
        editLabel: format(labels.editAmountFor, name),
        endLabel: format(labels.endFor, name),
        settleLabel: format(labels.settleFor, name)
      };
    });
  }

  get selectedFinancing() {
    return this.financings.find((f) => keyOf(f) === this.selectedKey);
  }
  get detailCaption() {
    const selected = this.selectedFinancing;
    return format(
      labels.installmentsCaption,
      selected ? this.nameOf(selected) : labels.notAvailable
    );
  }
  get installmentRows() {
    if (!this.detail) {
      return [];
    }
    const currency =
      (this.detail.financing && this.detail.financing.currencyIsoCode) || "BRL";
    return this.detail.installments.map((i) => ({
      ...i,
      key: `${i.sequence}`,
      dueText: this.formatDate(i.dueDate),
      statusText: labels[`inst${i.status}`] || i.status,
      hasInterest:
        i.interestPortion !== null && i.interestPortion !== undefined,
      hasPrincipal:
        i.principalPortion !== null && i.principalPortion !== undefined,
      hasBalance: i.closingBalance !== null && i.closingBalance !== undefined,
      currency
    }));
  }
  get hasInstallments() {
    return Boolean(this.detail) && this.detail.installments.length > 0;
  }
  get showNoInstallments() {
    return Boolean(this.detail) && !this.detailLoading && !this.hasInstallments;
  }

  nameOf(f) {
    return f.description || labels[`method${f.method}`] || labels.notAvailable;
  }

  /** Cancelling is allowed from today up to the due date of the last persisted installment. */
  maxEndOf(f) {
    const today = todayIso();
    return f && f.lastDueDate && f.lastDueDate > today ? f.lastDueDate : today;
  }

  formatDate(value) {
    const date = parseIsoDate(value);
    return date
      ? new Intl.DateTimeFormat(LOCALE, { dateStyle: "short" }).format(date)
      : labels.notAvailable;
  }

  findRow(key) {
    return this.financings.find((f) => keyOf(f) === key);
  }

  // ------------------------------------------------------------ loading

  async loadFinancings() {
    this.loading = true;
    try {
      this.financings = (await listFinancings()) || [];
      this.error = undefined;
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.loading = false;
    }
  }

  async loadDetail(key) {
    const row = this.findRow(key);
    if (!row) {
      return;
    }
    const seq = ++this.detailSeq;
    this.detailLoading = true;
    const query = row.scheduleId
      ? { scheduleId: row.scheduleId }
      : { legacyKey: row.legacyKey };
    try {
      const result = await getDetail({ request: JSON.stringify(query) });
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

  // ------------------------------------------------------------ navigation

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: PLANNER_TAB }
    });
  }

  // ------------------------------------------------------------ detail

  handleView(event) {
    const key = event.currentTarget.dataset.id;
    this.selectedKey = key;
    this.detail = undefined;
    this.loadDetail(key);
  }

  handleCloseDetail() {
    this.detailSeq += 1;
    const key = this.selectedKey;
    this.selectedKey = undefined;
    this.detail = undefined;
    this.detailLoading = false;
    this.moveFocus(`[data-view="${key}"]`);
  }

  // ------------------------------------------------------------ edit / end / settle

  resetChanges() {
    this.editingKey = undefined;
    this.endingKey = undefined;
    this.settlingKey = undefined;
    this.settlement = undefined;
    this.editKey = undefined;
    this.endKey = undefined;
    this.settleKey = undefined;
  }

  handleEdit(event) {
    const key = event.currentTarget.dataset.id;
    const row = this.findRow(key);
    this.resetChanges();
    this.editingKey = key;
    this.editAmountDraft = row ? row.nextAmount : null;
  }

  handleEditAmount(event) {
    this.editAmountDraft = event.detail
      ? event.detail.value
      : event.target.value;
    this.editKey = undefined;
  }

  handleCancelChange() {
    const key = this.editingKey || this.endingKey || this.settlingKey;
    this.resetChanges();
    this.moveFocus(`[data-view="${key}"]`);
  }

  async handleSaveAmount() {
    const row = this.findRow(this.editingKey);
    if (!row || this.busy) {
      return;
    }
    if (!validMoney(this.editAmountDraft)) {
      this.showMessage(labels.codeINVALID_INPUT, true);
      return;
    }
    if (!this.editKey) {
      this.editKey = newOperationKey();
    }
    await this.runChange(
      editAmount,
      {
        scheduleId: row.scheduleId,
        amount: Number(this.editAmountDraft),
        expectedVersion: row.version,
        operationKey: this.editKey
      },
      (result) =>
        format(labels.amountSaved, result.changedCount, result.protectedCount)
    );
  }

  handleEnd(event) {
    const key = event.currentTarget.dataset.id;
    this.resetChanges();
    this.endingKey = key;
    this.endDateDraft = todayIso();
  }

  handleEndDate(event) {
    this.endDateDraft = event.detail ? event.detail.value : event.target.value;
    this.endKey = undefined;
  }

  async handleConfirmEnd() {
    const row = this.findRow(this.endingKey);
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
        terminationDate: date,
        expectedVersion: row.version,
        operationKey: this.endKey
      },
      (result) =>
        format(labels.ended, result.changedCount, result.protectedCount)
    );
  }

  async handleSettle(event) {
    const key = event.currentTarget.dataset.id;
    const row = this.findRow(key);
    if (!row || this.busy) {
      return;
    }
    this.resetChanges();
    this.busy = true;
    try {
      const preview = await previewSettlement({
        request: JSON.stringify({ scheduleId: row.scheduleId })
      });
      this.settlingKey = key;
      this.settlement = preview;
      this.settleAmountDraft = preview.suggestedAmount;
      this.settleDateDraft = preview.minDate || todayIso();
      this.moveFocus("[data-settle-amount]");
    } catch (e) {
      this.showMessage(parseFailure(e), true);
    } finally {
      this.busy = false;
    }
  }

  handleSettleAmount(event) {
    this.settleAmountDraft = event.detail
      ? event.detail.value
      : event.target.value;
    this.settleKey = undefined;
  }

  async handleSettleDate(event) {
    this.settleDateDraft = event.detail
      ? event.detail.value
      : event.target.value;
    this.settleKey = undefined;
    const preview = this.settlement;
    const date = this.settleDateDraft;
    if (!preview || !date || date < preview.minDate || date > preview.maxDate) {
      return;
    }
    // The suggestion depends on the date: installments due up to it stay owed.
    try {
      const refreshed = await previewSettlement({
        request: JSON.stringify({
          scheduleId: preview.scheduleId,
          settlementDate: date
        })
      });
      if (this.settleDateDraft === date && this.settlement) {
        this.settlement = refreshed;
        this.settleAmountDraft = refreshed.suggestedAmount;
      }
    } catch (e) {
      this.showMessage(parseFailure(e), true);
    }
  }

  async handleConfirmSettle() {
    const row = this.findRow(this.settlingKey);
    const preview = this.settlement;
    if (!row || !preview || this.busy) {
      return;
    }
    const date = this.settleDateDraft;
    if (
      !validMoney(this.settleAmountDraft) ||
      !date ||
      date < preview.minDate ||
      date > preview.maxDate
    ) {
      this.showMessage(labels.codeINVALID_INPUT, true);
      return;
    }
    if (!this.settleKey) {
      this.settleKey = newOperationKey();
    }
    await this.runChange(
      settle,
      {
        scheduleId: row.scheduleId,
        amount: Number(this.settleAmountDraft),
        settlementDate: date,
        expectedVersion: preview.version,
        operationKey: this.settleKey
      },
      (result) => format(labels.settled, result.changedCount)
    );
  }

  async runChange(command, request, successMessage) {
    this.busy = true;
    try {
      const result = await command({ request: JSON.stringify(request) });
      this.resetChanges();
      this.showMessage(successMessage(result), false);
      await this.refreshAfterChange(request.scheduleId);
    } catch (e) {
      this.showMessage(parseFailure(e), true);
      if (failureCode(e) === "CONFLICT") {
        // The financing moved on: reload it rather than retry on a stale version.
        this.resetChanges();
        await this.refreshAfterChange(request.scheduleId);
      }
    } finally {
      this.busy = false;
    }
  }

  async refreshAfterChange(scheduleId) {
    await this.loadFinancings();
    if (this.selectedKey === scheduleId) {
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
