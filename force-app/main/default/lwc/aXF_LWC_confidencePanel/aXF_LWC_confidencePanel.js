import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import {
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import CONTEXT_CHANGED from "@salesforce/messageChannel/AXF_ContextChanged__c";
import canExplain from "@salesforce/customPermission/AXF_CanExplainConfidence";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.getHolders";
import explain from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.explain";
import labels from "./labels";
import { parseFailure, format } from "./failures";

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
  NO_SUCCESS_RECORDED: labels.exUnknown,
  CONNECTION_NOT_READABLE: labels.exConnectionNotReadable,
  FUTURE_SUCCESS: labels.exFutureSuccess,
  IMPORT_DATE_MISSING: labels.exImportDateMissing
};

const REASON_LABEL = {
  NOT_AUTHORIZED: labels.reasonNotAuthorized,
  NOT_A_HOLDER: labels.reasonNotAHolder,
  HOLDER_NOT_AUTHORIZED: labels.reasonNotAuthorized,
  CUSTODY: labels.reasonCustody,
  SOURCE_EXCLUDED: labels.reasonCustody,
  STALE_SOURCE: labels.exStale,
  UNKNOWN_FRESHNESS: labels.exUnknown,
  NO_AUTHORIZED_SCOPE: labels.reasonNoScope,
  NO_READABLE_SOURCE: labels.reasonNoScope,
  POLICY_MISSING: labels.reasonPolicyMissing,
  POLICY_INVALID: labels.reasonPolicyMissing
};

const ACTION_LABEL = {
  OPEN_SOURCE: labels.actionOpenSource,
  REVIEW_SOURCE_HEALTH: labels.actionReviewHealth
};

/** Fallbacks the server reports as applied; the UI never applies one on its own. */
const FALLBACK_LABEL = {
  FRESHNESS_LIMIT_DEFAULT: labels.fallbackFreshnessLimitDefault,
  IMPORT_DATE_MISSING: labels.exImportDateMissing
};

export default class AxfConfidencePanel extends NavigationMixin(
  LightningElement
) {
  _recordId;
  labels = labels;
  state = STATE.LOADING;
  holderOptions = [];
  holdersLoaded = false;
  selected = [];
  panel;
  errorMessage;
  announcement = "";
  wiredResult;
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

  /** Account record page: fixes the scope to that person/company (re-applied on change). */
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const changed = this._recordId !== value;
    this._recordId = value;
    if (changed && this.holdersLoaded) {
      this.selected = value ? [value] : [];
      this.load();
    }
  }

  /** Users without the capability see nothing instead of a FORBIDDEN alert. */
  get canRender() {
    return canExplain !== false;
  }

  @wire(getHolders)
  wiredHolders(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (error) {
      this.state = STATE.ERROR;
      this.errorMessage = parseFailure(error);
      return;
    }
    if (!data) {
      return;
    }
    this.holdersLoaded = true;
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
  get hasHolders() {
    return this.holderOptions.length > 0;
  }
  /** The canonical policy that declares the states and actions; never derived here. */
  get gatePolicyText() {
    return (this.panel && this.panel.gatePolicy) || "";
  }
  /** Coverage counts may be absent from an older response; never render "undefined". */
  get coverageText() {
    if (!this.panel) {
      return "";
    }
    if (
      typeof this.panel.includedCount !== "number" ||
      typeof this.panel.excludedCount !== "number"
    ) {
      return labels.coverageUnknown;
    }
    return (
      this.panel.includedCount +
      " " +
      labels.included +
      " · " +
      this.panel.excludedCount +
      " " +
      labels.excluded
    );
  }
  get hasFallbacks() {
    return this.fallbacks.length > 0;
  }
  /**
   * "No fallback was needed" is asserted only for a derived result whose fallback list the server
   * actually returned: a blocked panel derives nothing, and an older response may omit the field.
   */
  get showsNoFallbacks() {
    return (
      !!this.panel &&
      this.panel.level !== "BLOCKED" &&
      Array.isArray(this.panel.fallbacks) &&
      this.panel.fallbacks.length === 0
    );
  }
  get fallbacks() {
    if (!this.panel) {
      return [];
    }
    return (this.panel.fallbacks || []).map((code) => ({
      key: code,
      text: FALLBACK_LABEL[code] || code
    }));
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
      hasCurrency: !!source.currencyIso,
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
      text: REASON_LABEL[exclusion.reason] || exclusion.reason
    }));
  }
  get hasExclusions() {
    return this.exclusions.length > 0;
  }
  get fxText() {
    if (!this.panel) {
      return "";
    }
    if (this.panel.currencies.length === 0) {
      return labels.fxUnknown;
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
  get hasReasons() {
    return !!(this.panel && this.panel.reasons.length > 0);
  }
  get gateReasons() {
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

  /**
   * AXF-124 — the context changed, or the effective access is being revalidated. The panel belongs
   * to the previous context, so it is discarded before anything else and never kept as a fallback,
   * an in-flight response is rejected instead of allowed to land, the accessible announcement is
   * cleared, and the holder list is refreshed rather than trusted (it is cached by the wire, so a
   * revoked holder would otherwise stay reachable). With a scope selected the server recomputes the
   * whole unit through the native model; nothing is decided here.
   */
  handleContextChanged() {
    this.panel = undefined;
    this.announcement = "";
    this.requestToken += 1;
    if (this.wiredResult) {
      Promise.resolve(refreshApex(this.wiredResult)).catch(() => {});
    }
    if (this.selected.length === 0) {
      this.state = this.holdersLoaded ? STATE.IDLE : STATE.LOADING;
    } else if (!this.recordId) {
      // On a record page the refreshed holder wire reloads the panel itself.
      this.load();
    }
  }

  handleScopeChange(event) {
    this.selected = event.detail.value || [];
  }

  handleExplain() {
    this.load();
  }

  handleRetry() {
    this.errorMessage = undefined;
    if (!this.holdersLoaded && this.wiredResult) {
      // The holder list itself failed: refresh the wire instead of explaining nothing.
      this.state = STATE.LOADING;
      refreshApex(this.wiredResult);
      return;
    }
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
    const token = ++this.requestToken;
    try {
      const result = await explain({ accountIds: this.selected });
      if (token !== this.requestToken) {
        return; // a newer request superseded this one
      }
      this.panel = result;
      this.state = STATE.READY;
      this.announcement = labels.updated + " " + this.levelLabel;
    } catch (error) {
      if (token !== this.requestToken) {
        return;
      }
      this.panel = undefined;
      this.state = STATE.ERROR;
      this.errorMessage = parseFailure(error);
      this.announcement = this.errorMessage;
    }
  }
}
