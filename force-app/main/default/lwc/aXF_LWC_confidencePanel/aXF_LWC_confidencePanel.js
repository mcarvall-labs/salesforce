import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.getHolders";
import explain from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.explain";
import labels from "./labels";

const STATE = {
  LOADING: "LOADING",
  IDLE: "IDLE",
  READY: "READY",
  ERROR: "ERROR"
};

const LEVEL_META = {
  INFORMATIVE: {
    label: labels.levelInformative,
    variant: "success",
    impact: labels.impactInformative
  },
  DEGRADED: {
    label: labels.levelDegraded,
    variant: "warning",
    impact: labels.impactDegraded
  },
  BLOCKED: {
    label: labels.levelBlocked,
    variant: "error",
    impact: labels.impactBlocked
  }
};

const FRESHNESS_CLASS = {
  CURRENT: "slds-badge slds-badge_success",
  STALE: "slds-badge slds-badge_warning",
  UNKNOWN: "slds-badge slds-badge_inverse"
};

const FRESHNESS_LABEL = {
  CURRENT: labels.freshnessCurrent,
  STALE: labels.freshnessStale,
  UNKNOWN: labels.freshnessUnknown
};

const EXCEPTION_LABEL = {
  CONSENT_REVOKED: labels.exConsentRevoked,
  CONSENT_STALE: labels.exConsentStale,
  COLLECTION_PAUSED: labels.exCollectionPaused,
  FRESHNESS_EXCEEDED: labels.exStale,
  NO_SUCCESS_RECORDED: labels.exUnknown
};

const REASON_LABEL = {
  NOT_AUTHORIZED: labels.reasonNotAuthorized,
  CUSTODY: labels.reasonCustody,
  NO_AUTHORIZED_SCOPE: labels.reasonNoScope,
  NO_READABLE_SOURCE: labels.reasonNoScope,
  POLICY_MISSING: labels.reasonPolicyMissing
};

const ACTION_LABEL = {
  OPEN_SOURCE: labels.actionOpenSource,
  REVIEW_SOURCE_HEALTH: labels.actionReviewHealth
};

const CODE_LABEL = {
  FORBIDDEN: labels.codeForbidden,
  INVALID_INPUT: labels.codeInvalidInput
};

export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || labels.error;
}

function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    return args[index] === undefined ? match : args[index];
  });
}

export default class AxfConfidencePanel extends NavigationMixin(
  LightningElement
) {
  /** Account record page: fixes the scope to that person/company. */
  @api recordId;
  labels = labels;
  state = STATE.LOADING;
  holderOptions = [];
  selected = [];
  panel;
  errorMessage;
  announcement = "";

  @wire(getHolders)
  wiredHolders({ data, error }) {
    if (error) {
      this.state = STATE.ERROR;
      this.errorMessage = parseFailure(error);
      return;
    }
    if (!data) {
      return;
    }
    this.holderOptions = data.map((holder) => ({
      label: holder.name,
      value: holder.accountId
    }));
    if (this.recordId) {
      this.selected = [this.recordId];
      this.load();
    } else {
      this.state = STATE.IDLE;
    }
  }

  get isLoading() {
    return this.state === STATE.LOADING;
  }
  get isIdle() {
    return this.state === STATE.IDLE;
  }
  get isReady() {
    return this.state === STATE.READY && this.panel;
  }
  get isError() {
    return this.state === STATE.ERROR;
  }
  get showSelector() {
    return !this.recordId;
  }
  get canExplainDisabled() {
    return this.selected.length === 0 || this.state === STATE.LOADING;
  }

  get levelLabel() {
    const meta = LEVEL_META[this.panel && this.panel.level];
    return meta ? meta.label : this.panel && this.panel.level;
  }
  get levelVariant() {
    const meta = LEVEL_META[this.panel && this.panel.level];
    return meta ? meta.variant : "inverse";
  }
  get levelClass() {
    return "slds-badge slds-badge_" + this.levelVariant + " axf-level";
  }
  get impactText() {
    const meta = LEVEL_META[this.panel && this.panel.level];
    return meta ? meta.impact : "";
  }
  get isBlocked() {
    return this.panel && this.panel.level === "BLOCKED";
  }

  get sources() {
    if (!this.panel) {
      return [];
    }
    return this.panel.sources.map((source) => ({
      ...source,
      key: source.sourceId,
      originLabel:
        source.origin === "PLUGGY" ? labels.originPluggy : labels.originManual,
      freshnessLabel: FRESHNESS_LABEL[source.freshness] || source.freshness,
      freshnessClass:
        FRESHNESS_CLASS[source.freshness] || FRESHNESS_CLASS.UNKNOWN,
      inclusionLabel: source.included
        ? labels.included
        : labels.excluded +
          (source.exclusionReason
            ? " · " +
              (REASON_LABEL[source.exclusionReason] || source.exclusionReason)
            : ""),
      factsLabel:
        source.factCount === null || source.factCount === undefined
          ? labels.factsUnknown
          : String(source.factCount),
      hasLastSuccess: !!source.lastSuccessAt,
      exceptionLabels: (source.exceptions || []).map(
        (code) => EXCEPTION_LABEL[code] || code
      ),
      ariaLabel: labels.openSource + ": " + source.label
    }));
  }
  get hasExceptions() {
    return this.exceptions.length > 0;
  }
  get exceptions() {
    if (!this.panel) {
      return [];
    }
    const rows = [];
    this.panel.sources.forEach((source) => {
      (source.exceptions || []).forEach((code) => {
        rows.push({
          key: source.sourceId + code,
          text: (EXCEPTION_LABEL[code] || code) + " — " + source.label
        });
      });
    });
    return rows;
  }
  get exclusions() {
    if (!this.panel) {
      return [];
    }
    return this.panel.exclusions.map((exclusion, index) => ({
      key: index,
      text:
        (REASON_LABEL[exclusion.reason] || exclusion.reason) +
        (exclusion.count > 1 ? " ×" + exclusion.count : "")
    }));
  }
  get hasExclusions() {
    return this.exclusions.length > 0;
  }
  get fxText() {
    if (!this.panel) {
      return "";
    }
    return this.panel.currencies.length > 1
      ? format(labels.fxMulti, this.panel.currencies.join(", "))
      : labels.fxSingle;
  }
  get actions() {
    if (!this.panel || this.panel.allowedActions.length === 0) {
      return [{ key: "none", text: labels.actionNone }];
    }
    return this.panel.allowedActions.map((code) => ({
      key: code,
      text: ACTION_LABEL[code] || code
    }));
  }
  get blockedReasons() {
    if (!this.panel) {
      return [];
    }
    return this.panel.reasons.map((reason, index) => ({
      key: index,
      text: reason.startsWith("FIELD_ACCESS:")
        ? labels.reasonFieldAccess
        : REASON_LABEL[reason] || EXCEPTION_LABEL[reason] || reason
    }));
  }

  handleScopeChange(event) {
    this.selected = event.detail.value || [];
  }

  handleExplain() {
    this.load();
  }

  handleRetry() {
    this.errorMessage = undefined;
    this.load();
  }

  handleOpenSource(event) {
    const sourceId = event.currentTarget.dataset.source;
    const source = this.panel.sources.find((row) => row.sourceId === sourceId);
    if (!source || !source.navigable) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: sourceId, actionName: "view" }
    });
  }

  async load() {
    if (this.selected.length === 0) {
      this.state = STATE.IDLE;
      this.panel = undefined;
      return;
    }
    this.state = STATE.LOADING;
    try {
      this.panel = await explain({ accountIds: this.selected });
      this.state = STATE.READY;
      this.announcement = labels.updated + " " + this.levelLabel;
    } catch (error) {
      this.panel = undefined;
      this.state = STATE.ERROR;
      this.errorMessage = parseFailure(error);
      this.announcement = this.errorMessage;
    }
  }
}
