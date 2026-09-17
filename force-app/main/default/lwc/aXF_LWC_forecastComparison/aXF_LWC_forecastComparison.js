import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import {
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import CONTEXT_CHANGED from "@salesforce/messageChannel/AXF_ContextChanged__c";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ForecastComparison.getContext";
import compare from "@salesforce/apex/AXF_CLS_CTRL_ForecastComparison.compare";
import labels from "./labels";
import { parseFailure, format } from "./failures";

const STATE = {
  INIT: "INIT",
  IDLE: "IDLE",
  LOADING: "LOADING",
  READY: "READY",
  ERROR: "ERROR"
};
const SCENARIOS = ["CONSERVATIVE", "INTERMEDIATE", "OPTIMISTIC"];
const SCENARIO_LABEL = {
  CONSERVATIVE: labels.scenarioCONSERVATIVE,
  INTERMEDIATE: labels.scenarioINTERMEDIATE,
  OPTIMISTIC: labels.scenarioOPTIMISTIC
};
const CONFIDENCE_LABEL = {
  INFORMATIVE: labels.confidenceINFORMATIVE,
  DEGRADED: labels.confidenceDEGRADED,
  BLOCKED: labels.confidenceBLOCKED
};
const CONFIDENCE_VARIANT = {
  INFORMATIVE: "success",
  DEGRADED: "warning",
  BLOCKED: "error"
};
const REASON_LABEL = {
  COVERAGE_UNVERIFIED: labels.reasonCOVERAGE_UNVERIFIED,
  NO_AUTHORIZED_SCOPE: labels.reasonNO_AUTHORIZED_SCOPE,
  VOLUME_EXCEEDED: labels.reasonVOLUME_EXCEEDED,
  COMMITMENT_UNBOUNDED: labels.reasonCOMMITMENT_UNBOUNDED,
  OBLIGATIONS_BEYOND_HORIZON: labels.reasonOBLIGATIONS_BEYOND_HORIZON,
  OVERDUE_OBLIGATIONS: labels.reasonOVERDUE_OBLIGATIONS,
  MULTI_CURRENCY: labels.reasonMULTI_CURRENCY,
  AS_OF_NOT_TODAY: labels.reasonAS_OF_NOT_TODAY,
  NO_CONTRIBUTIONS: labels.reasonNO_CONTRIBUTIONS,
  INCOMPLETE_CONTRIBUTION: labels.reasonINCOMPLETE_CONTRIBUTION,
  NO_APPROVED_METHOD: labels.reasonNO_APPROVED_METHOD,
  SCHEDULE_STALE: labels.reasonSCHEDULE_STALE,
  SCHEDULE_AMBIGUOUS: labels.reasonSCHEDULE_AMBIGUOUS,
  SCHEDULE_INVALID: labels.reasonSCHEDULE_INVALID,
  SCHEDULE_UNSUPPORTED: labels.reasonSCHEDULE_UNSUPPORTED,
  SCHEDULE_FORBIDDEN: labels.reasonSCHEDULE_FORBIDDEN,
  SCHEDULE_NOT_FOUND: labels.reasonSCHEDULE_NOT_FOUND
};
const EXCLUSION_LABEL = {
  NOT_AUTHORIZED: labels.exNOT_AUTHORIZED,
  NOT_A_HOLDER: labels.exNOT_A_HOLDER,
  COVERAGE_UNVERIFIED: labels.exCOVERAGE_UNVERIFIED,
  NO_APPROVED_METHOD: labels.reasonNO_APPROVED_METHOD
};
const ACTION_LABEL = { REVIEW_SCHEDULES: labels.actionREVIEW_SCHEDULES };

function scenarioInOut(row, scenario) {
  let inflow = row.confirmedIn;
  let outflow = row.confirmedOut;
  if (scenario !== "CONSERVATIVE") {
    inflow += row.probableIn;
    outflow += row.probableOut;
  }
  if (scenario === "OPTIMISTIC") {
    inflow += row.uncertainIn;
    outflow += row.uncertainOut;
  }
  return { inflow, outflow, net: inflow - outflow };
}

export default class AxfForecastComparison extends LightningElement {
  labels = labels;
  state = STATE.INIT;
  context;
  wiredContextResult;
  holderOptions = [];
  selected = [];
  horizonMonths = 12;
  scenario = "INTERMEDIATE";
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

  @wire(getContext, { search: "" })
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
    if (this.state === STATE.INIT || this.state === STATE.ERROR) {
      this.state = STATE.IDLE;
      this.errorMessage = undefined;
    }
  }

  get canRender() {
    return !this.context || this.context.canCompare;
  }
  get isForbidden() {
    return !!this.context && !this.context.canCompare;
  }
  get horizonOptions() {
    const horizons = (this.context && this.context.horizons) || [
      3, 6, 9, 12, 15, 18, 21, 24
    ];
    return horizons.map((months) => ({
      label: String(months),
      value: String(months)
    }));
  }
  get scenarioOptions() {
    return SCENARIOS.map((code) => ({
      label: SCENARIO_LABEL[code],
      value: code
    }));
  }
  get horizonValue() {
    return String(this.horizonMonths);
  }
  get isIdle() {
    return this.state === STATE.IDLE;
  }
  get isLoading() {
    return this.state === STATE.LOADING;
  }
  get isReady() {
    return this.state === STATE.READY && !!this.result;
  }
  get noContributions() {
    return (
      this.isReady &&
      this.result.periods.length === 0 &&
      this.result.horizons.length === 0 &&
      this.result.overdue.length === 0
    );
  }
  get hasHorizons() {
    return this.isReady && this.result.horizons.length > 0;
  }
  get hasPeriods() {
    return this.isReady && this.result.periods.length > 0;
  }
  get isError() {
    return this.state === STATE.ERROR;
  }
  get compareDisabled() {
    return this.selected.length === 0 || this.state === STATE.LOADING;
  }
  get confidenceLabel() {
    return this.result ? CONFIDENCE_LABEL[this.result.confidence] : "";
  }
  get confidenceClass() {
    const variant = this.result
      ? CONFIDENCE_VARIANT[this.result.confidence] || "inverse"
      : "inverse";
    return "slds-badge slds-badge_" + variant;
  }
  get isBlocked() {
    return !!this.result && this.result.confidence === "BLOCKED";
  }
  get scenarioLabel() {
    return SCENARIO_LABEL[this.scenario];
  }
  get periodsTitle() {
    return format(labels.periods, this.scenarioLabel);
  }
  get reasons() {
    if (!this.result) {
      return [];
    }
    return this.result.reasons.map((code, index) => ({
      key: index,
      text: REASON_LABEL[code] || code
    }));
  }
  get exclusions() {
    if (!this.result) {
      return [];
    }
    return this.result.exclusions.map((exclusion, index) => ({
      key: index,
      text: EXCLUSION_LABEL[exclusion.reason] || exclusion.reason
    }));
  }
  get hasExclusions() {
    return this.exclusions.length > 0;
  }
  get actions() {
    if (!this.result || this.result.allowedActions.length === 0) {
      return [{ key: "none", text: labels.actionNone }];
    }
    return this.result.allowedActions.map((code) => ({
      key: code,
      text: ACTION_LABEL[code] || code
    }));
  }
  get periodRows() {
    if (!this.result) {
      return [];
    }
    return this.result.periods.map((row) => {
      const totals = scenarioInOut(row, this.scenario);
      return {
        ...row,
        key: row.periodKey + row.currencyIso,
        inflow: totals.inflow,
        outflow: totals.outflow,
        net: totals.net
      };
    });
  }
  get horizonRows() {
    if (!this.result) {
      return [];
    }
    return this.result.horizons.map((row) => ({
      ...row,
      key: row.horizonMonths + row.currencyIso,
      rowClass:
        row.horizonMonths === this.result.horizonMonths
          ? "slds-is-selected axf-selected"
          : ""
    }));
  }
  get beyondRows() {
    if (!this.result) {
      return [];
    }
    return this.result.horizons
      .filter(
        (row) =>
          row.horizonMonths === this.result.horizonMonths && row.beyondCount > 0
      )
      .map((row) => ({
        key: row.currencyIso,
        text: format(
          labels.beyondText,
          row.beyondCount,
          this.result.horizonEnd,
          row.beyondOut + " " + row.currencyIso,
          row.beyondIn + " " + row.currencyIso
        )
      }));
  }
  get hasBeyond() {
    return this.beyondRows.length > 0;
  }
  get overdueRows() {
    if (!this.result) {
      return [];
    }
    return this.result.overdue.map((row) => ({ ...row, key: row.currencyIso }));
  }
  get hasOverdue() {
    return this.overdueRows.length > 0;
  }
  get sourceRows() {
    if (!this.result) {
      return [];
    }
    return this.result.sources.map((source, index) => ({
      ...source,
      key: index,
      kindLabel:
        source.kind === "SCHEDULE" ? labels.sourceSCHEDULE : labels.sourcePLAN,
      coverageText: source.coverageComplete ? "" : labels.incompleteCoverage
    }));
  }

  /**
   * AXF-124 — the context changed, or the effective access is being revalidated. The displayed
   * result belongs to the previous context, so it is discarded before anything else and never kept
   * as a fallback, an in-flight response is rejected instead of allowed to land, the accessible
   * announcement is cleared, and the holder context is emptied and refreshed rather than trusted
   * (the wire caches it, so a revoked holder would otherwise stay reachable). The server then
   * recomputes the whole unit — totals, confidence, attention and explanations — through the native
   * model.
   */
  handleContextChanged() {
    this.result = undefined;
    this.announcement = "";
    // Only a selected scope makes load() bump the token; with the scope empty nothing else would
    // reject an answer already in flight, so the token is bumped here for both arms.
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
      // A displayed result belongs to the previous scope: never leave it on screen as if current.
      this.result = undefined;
      this.state = STATE.IDLE;
      this.announcement = "";
    }
  }
  handleHorizonChange(event) {
    this.horizonMonths = parseInt(event.detail.value, 10);
    if (this.result) {
      this.load();
    }
  }
  handleScenarioChange(event) {
    this.scenario = event.detail.value;
    if (this.result) {
      // Scenario totals are already in the result (tiers): re-announce, no server call.
      this.announce();
    }
  }
  handleCompare() {
    this.load();
  }
  handleRetry() {
    this.errorMessage = undefined;
    if (!this.context && this.wiredContextResult) {
      this.state = STATE.INIT;
      refreshApex(this.wiredContextResult);
      return;
    }
    this.load();
  }

  announce() {
    if (!this.result) {
      return;
    }
    this.announcement = format(
      labels.updated,
      this.scenarioLabel,
      this.result.horizonMonths,
      this.confidenceLabel
    );
  }

  async load() {
    if (this.selected.length === 0) {
      this.state = STATE.IDLE;
      return;
    }
    const token = ++this.requestToken;
    this.state = STATE.LOADING;
    try {
      const result = await compare({
        request: JSON.stringify({
          accountIds: this.selected,
          horizonMonths: this.horizonMonths,
          scenario: this.scenario,
          asOf: null
        })
      });
      if (token !== this.requestToken) {
        return;
      }
      this.result = result;
      // Every response renders confidence, reasons and exclusions; "empty" is a fact
      // inside the result (no contributions), never a substitute for a BLOCKED explanation.
      this.state = STATE.READY;
      this.announce();
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
