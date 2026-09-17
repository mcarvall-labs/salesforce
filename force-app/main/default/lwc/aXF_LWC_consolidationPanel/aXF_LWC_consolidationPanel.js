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
      // The context itself is unreadable: no holder list is trusted, and the retry refreshes this
      // wire instead of deriving against the context that failed.
      this.context = undefined;
      this.holderOptions = [];
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
  /** A comparison column exists only when the server compared something. */
  get hasConversion() {
    return (
      this.hasTotals &&
      this.result.totals.some((total) => !!total.conversionState)
    );
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
      conversionLabel:
        CONVERSION_LABEL[total.conversionState] || total.conversionState
    }));
  }

  get hasExclusions() {
    return this.isReady && this.result.exclusions.length > 0;
  }
  /**
   * The exclusion names the selection it belongs to: the service echoes the id the caller supplied,
   * and a name exists only while the holder is still listed, so an id is shown when it is not. The
   * count is stated only when it says something — a single excluded selection is not a count.
   */
  get exclusionRows() {
    if (!this.result) {
      return [];
    }
    return this.result.exclusions.map((exclusion, index) => {
      const listed = this.holderOptions.find(
        (option) => option.value === exclusion.accountId
      );
      return {
        key: index,
        reasonLabel: EXCLUSION_LABEL[exclusion.reason] || exclusion.reason,
        selectionLabel: exclusion.accountId
          ? listed
            ? listed.label
            : exclusion.accountId
          : "",
        multiple: exclusion.count > 1,
        count: exclusion.count
      };
    });
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
  /**
   * AXF-123's own withholding: the reason the service reports when a currency has no usable quote.
   * Nothing else may be blamed on the exchange rate.
   */
  get missingFx() {
    return (
      this.isReady &&
      !this.result.comparableTotal &&
      this.result.reasons.indexOf("MISSING_MATERIAL_FX") >= 0
    );
  }
  /**
   * A comparison that was requested and produced no indicator for another reason: the service
   * returns before it compares when the scope is blocked, so the absence is stated as its own fact
   * instead of being reported as "no currency was chosen".
   */
  get comparisonBlocked() {
    return (
      this.isReady &&
      !this.result.comparableTotal &&
      !this.missingFx &&
      !!this.reportingIso
    );
  }
  get noComparisonRequested() {
    return this.isReady && !this.result.comparableTotal && !this.reportingIso;
  }

  /**
   * AXF-124 — the context changed, or the effective access is being revalidated. The displayed
   * consolidated view belongs to the previous context, so it is discarded before anything else and
   * never kept as a fallback: `discard()` is what rejects an answer already in flight and clears the
   * accessible announcement. The holder list is emptied and refreshed rather than trusted (the wire
   * caches it, so a revoked holder would otherwise stay reachable). With a scope selected the server
   * derives the whole unit again through the native model; nothing is decided here.
   */
  handleContextChanged() {
    this.discard();
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
    // Unconditionally, and not only when something is displayed: a derivation already in flight for
    // the previous scope must not land after the scope changed.
    this.discard();
  }

  handleCurrencyChange(event) {
    this.reportingIso = event.detail.value;
    // A displayed view, a failure and a derivation in flight all belong to the previous currency.
    if (
      this.result ||
      this.state === STATE.LOADING ||
      this.state === STATE.ERROR
    ) {
      if (this.selected.length > 0) {
        this.load();
      }
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
    // A derivation already issued belongs to the input that has just changed.
    this.requestToken += 1;
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
