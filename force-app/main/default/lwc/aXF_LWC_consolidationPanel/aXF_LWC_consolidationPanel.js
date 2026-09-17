import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import {
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import CONTEXT_CHANGED from "@salesforce/messageChannel/AXF_ContextChanged__c";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ConsolidationPanel.getContext";
import consolidate from "@salesforce/apex/AXF_CLS_CTRL_ConsolidationPanel.consolidate";
import labels from "./labels";
import { parseFailure, format } from "./failures";

const STATE = {
  LOADING: "LOADING",
  IDLE: "IDLE",
  READY: "READY",
  ERROR: "ERROR"
};

const CONFIDENCE_LABEL = {
  FULL: labels.confidenceFULL,
  DEGRADED: labels.confidenceDEGRADED,
  BLOCKED: labels.confidenceBLOCKED
};

const CONFIDENCE_VARIANT = {
  FULL: "success",
  DEGRADED: "warning",
  BLOCKED: "error"
};

const CONVERSION_LABEL = {
  SAME_CURRENCY: labels.fxSAME_CURRENCY,
  ESTIMATED: labels.fxESTIMATED,
  STALE: labels.fxSTALE,
  UNAVAILABLE: labels.fxUNAVAILABLE
};

const HOLDER_STATE_LABEL = {
  AUTHORIZED: labels.holderAuthorized,
  UNKNOWN: labels.holderUnknown
};

const COVERAGE_LABEL = {
  FULL: labels.coverageFull,
  UNVERIFIED: labels.coverageUnverified
};

const EXCLUSION_LABEL = {
  NOT_AUTHORIZED: labels.exNotAuthorized,
  NOT_A_HOLDER: labels.exNotAHolder,
  ALLOCATED_OUTSIDE_SCOPE: labels.exAllocatedOutside,
  ALLOCATED_TO_UNVERIFIED_HOLDER: labels.exAllocatedUnverified
};

const REASON_LABEL = {
  COVERAGE_UNVERIFIED: labels.reasonCoverageUnverified,
  NO_AUTHORIZED_SCOPE: labels.reasonNoScope,
  VOLUME_EXCEEDED: labels.reasonVolumeExceeded,
  MISSING_MATERIAL_FX: labels.reasonMissingFx,
  ALLOCATED_OUTSIDE_SCOPE: labels.reasonAllocatedOutside,
  ALLOCATED_TO_UNVERIFIED_HOLDER: labels.reasonAllocatedUnverified,
  ALLOCATION_UNREADABLE: labels.reasonAllocationUnreadable,
  ALLOCATION_AMBIGUOUS: labels.reasonAllocationAmbiguous,
  ALLOCATION_INVALID: labels.reasonAllocationInvalid,
  ALLOCATION_INCOMPLETE: labels.reasonAllocationIncomplete,
  UNKNOWN_STATUS: labels.reasonUnknownStatus,
  UNKNOWN_DIRECTION: labels.reasonUnknownDirection
};

export default class AxfConsolidationPanel extends LightningElement {
  labels = labels;
  state = STATE.LOADING;
  context;
  wiredContextResult;
  holderOptions = [];
  currencyOptions = [];
  selected = [];
  reportingIso;
  result;
  errorMessage;
  announcement = "";
  requestToken = 0;
  subscription;

  @wire(MessageContext) messageContext;

  connectedCallback() {
    this.subscription = subscribe(this.messageContext, CONTEXT_CHANGED, () =>
      this.handleContextChanged()
    );
  }

  disconnectedCallback() {
    unsubscribe(this.subscription);
    this.subscription = undefined;
  }

  /** Users without the capability see nothing instead of a FORBIDDEN alert. */
  get canRender() {
    return !this.context || this.context.canConsolidate;
  }

  @wire(getContext)
  wiredContext(value) {
    this.wiredContextResult = value;
    const { data, error } = value;
    if (error) {
      this.state = STATE.ERROR;
      this.errorMessage = parseFailure(error);
      return;
    }
    if (!data) {
      return;
    }
    this.context = data;
    this.holderOptions = (data.holders || []).map((holder) => ({
      label: holder.name,
      value: holder.accountId
    }));
    this.currencyOptions = (data.currencies || []).map((currency) => ({
      label: currency.label || currency.isoCode,
      value: currency.isoCode
    }));
    // The caller's reporting currency starts at the ratified presentation preference (AXF-87) and
    // belongs to this surface afterwards, so a later refresh never overwrites a chosen currency.
    if (this.reportingIso === undefined) {
      this.reportingIso = data.defaultReportingIso || "";
    }
    if (this.state === STATE.LOADING) {
      this.state = STATE.IDLE;
      this.errorMessage = undefined;
    }
  }

  get hasCurrencyOptions() {
    return this.currencyOptions.length > 0;
  }
  get isLoading() {
    return this.state === STATE.LOADING;
  }
  get isIdle() {
    return this.state === STATE.IDLE;
  }
  get isReady() {
    return this.state === STATE.READY && !!this.result;
  }
  get isError() {
    return this.state === STATE.ERROR;
  }
  get consolidateDisabled() {
    return this.selected.length === 0 || this.state === STATE.LOADING;
  }

  get confidenceLabel() {
    return this.result
      ? CONFIDENCE_LABEL[this.result.confidence] || this.result.confidence
      : "";
  }
  get confidenceClass() {
    const variant = this.result
      ? CONFIDENCE_VARIANT[this.result.confidence] || "inverse"
      : "inverse";
    return "slds-badge slds-badge_" + variant;
  }
  /** The server echoes the requested range; an unbounded scope is stated, never left blank. */
  get hasPeriod() {
    return !!(this.result && this.result.fromDate);
  }
  get hasReasons() {
    return this.isReady && this.result.reasons.length > 0;
  }
  get reasonRows() {
    if (!this.result) {
      return [];
    }
    return this.result.reasons.map((code, index) => ({
      key: index,
      text: code.startsWith("FIELD_ACCESS:")
        ? labels.reasonFieldAccess
        : REASON_LABEL[code] || code
    }));
  }

  get hasHolders() {
    return this.isReady && this.result.holders.length > 0;
  }
  get holderRows() {
    if (!this.result) {
      return [];
    }
    return this.result.holders.map((holder) => ({
      key: holder.accountId,
      accountName: holder.accountName,
      stateLabel: HOLDER_STATE_LABEL[holder.state] || holder.state,
      coverageLabel: COVERAGE_LABEL[holder.coverage] || holder.coverage
    }));
  }

  get hasTotals() {
    return this.isReady && this.result.totals.length > 0;
  }
  get totalRows() {
    if (!this.result) {
      return [];
    }
    return this.result.totals.map((total) => ({
      key: total.currencyIso,
      currencyIso: total.currencyIso,
      inflow: total.inflow,
      outflow: total.outflow,
      net: total.net,
      factCount: total.factCount,
      holderCount: total.holderCount,
      // Blank when no comparison was requested: the absence is stated once, in that section.
      conversionLabel: CONVERSION_LABEL[total.conversionState] || ""
    }));
  }

  get hasExclusions() {
    return this.isReady && this.result.exclusions.length > 0;
  }
  /** The count stays written out; a collapsed or hover-only disclosure is never used. */
  get exclusionRows() {
    if (!this.result) {
      return [];
    }
    return this.result.exclusions.map((exclusion, index) => ({
      key: index,
      count: exclusion.count,
      reasonLabel: EXCLUSION_LABEL[exclusion.reason] || exclusion.reason
    }));
  }

  get hasComparable() {
    return this.isReady && !!this.result.comparableTotal;
  }
  get comparable() {
    return this.result ? this.result.comparableTotal : undefined;
  }
  /**
   * The aggregate carries no state of its own: it is an estimate as soon as one currency in the
   * result had to be converted, and exact when every total already was in the reporting currency.
   */
  get comparableStateText() {
    return this.result &&
      this.result.totals.some((row) => row.conversionState === "ESTIMATED")
      ? labels.fxESTIMATED
      : labels.fxSAME_CURRENCY;
  }
  /** Named, not implied: the reader is told which currency has no usable quote. */
  get blockedCurrencies() {
    return this.result.totals
      .filter(
        (row) =>
          row.conversionState === "STALE" ||
          row.conversionState === "UNAVAILABLE"
      )
      .map((row) => row.currencyIso)
      .join(", ");
  }
  get comparisonWithheld() {
    return (
      this.isReady && !this.result.comparableTotal && !!this.result.reportingIso
    );
  }

  /**
   * AXF-124 — the context changed, or the effective access is being revalidated. The displayed
   * consolidated view belongs to the previous context, so it is discarded before anything else and
   * never kept as a fallback, an in-flight response is rejected instead of allowed to land, the
   * accessible announcement is cleared, and the holder list is emptied and refreshed rather than
   * trusted (the wire caches it, so a revoked holder would otherwise stay reachable). With a scope
   * selected the server derives the whole unit again through the native model.
   */
  handleContextChanged() {
    this.result = undefined;
    this.announcement = "";
    this.requestToken += 1;
    this.state = STATE.LOADING;
    this.holderOptions = [];
    if (this.wiredContextResult) {
      Promise.resolve(refreshApex(this.wiredContextResult)).catch(() => {});
    }
    if (this.selected.length > 0) {
      this.load();
    } else {
      this.state = STATE.IDLE;
    }
  }

  handleScopeChange(event) {
    this.selected = event.detail.value || [];
    if (this.result) {
      // A displayed view belongs to the previous scope: never leave it on screen as if current.
      this.discard();
    }
  }

  handleCurrencyChange(event) {
    this.reportingIso = event.detail.value;
    if (this.result) {
      // The comparable indicator belongs to the previous currency; it is derived again.
      this.load();
    }
  }

  handleConsolidate() {
    this.load();
  }

  handleRetry() {
    this.errorMessage = undefined;
    if (!this.context && this.wiredContextResult) {
      // The context itself failed: refresh the wire instead of consolidating nothing.
      this.state = STATE.LOADING;
      refreshApex(this.wiredContextResult);
      return;
    }
    this.load();
  }

  discard() {
    this.result = undefined;
    this.announcement = "";
    this.state = STATE.IDLE;
  }

  async load() {
    if (this.selected.length === 0) {
      this.state = STATE.IDLE;
      this.result = undefined;
      return;
    }
    const token = ++this.requestToken;
    this.state = STATE.LOADING;
    try {
      const result = await consolidate({
        accountIds: this.selected,
        reportingIso: this.reportingIso || null
      });
      if (token !== this.requestToken) {
        return; // a newer request superseded this one
      }
      this.result = result;
      this.state = STATE.READY;
      this.announcement = format(labels.updated, this.confidenceLabel);
    } catch (error) {
      if (token !== this.requestToken) {
        return;
      }
      this.result = undefined;
      this.state = STATE.ERROR;
      this.errorMessage = parseFailure(error);
      this.announcement = this.errorMessage;
    }
  }
}
