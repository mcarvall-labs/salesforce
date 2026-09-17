import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import canExplain from "@salesforce/customPermission/AXF_CanExplainConfidence";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.getHolders";
import explain from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.explain";
import title from "@salesforce/label/c.AXF_ConfidencePanel_title";
import intro from "@salesforce/label/c.AXF_ConfidencePanel_intro";
import scope from "@salesforce/label/c.AXF_ConfidencePanel_scope";
import scopeHelp from "@salesforce/label/c.AXF_ConfidencePanel_scopeHelp";
import explainLabel from "@salesforce/label/c.AXF_ConfidencePanel_explain";
import level from "@salesforce/label/c.AXF_ConfidencePanel_level";
import levelInformative from "@salesforce/label/c.AXF_ConfidencePanel_levelInformative";
import levelDegraded from "@salesforce/label/c.AXF_ConfidencePanel_levelDegraded";
import levelBlocked from "@salesforce/label/c.AXF_ConfidencePanel_levelBlocked";
import asOf from "@salesforce/label/c.AXF_ConfidencePanel_asOf";
import policy from "@salesforce/label/c.AXF_ConfidencePanel_policy";
import sources from "@salesforce/label/c.AXF_ConfidencePanel_sources";
import sourceLabel from "@salesforce/label/c.AXF_ConfidencePanel_source";
import holderLabel from "@salesforce/label/c.AXF_ConfidencePanel_holder";
import origin from "@salesforce/label/c.AXF_ConfidencePanel_origin";
import originPluggy from "@salesforce/label/c.AXF_ConfidencePanel_originPluggy";
import originManual from "@salesforce/label/c.AXF_ConfidencePanel_originManual";
import lastSuccess from "@salesforce/label/c.AXF_ConfidencePanel_lastSuccess";
import never from "@salesforce/label/c.AXF_ConfidencePanel_never";
import freshness from "@salesforce/label/c.AXF_ConfidencePanel_freshness";
import freshnessCurrent from "@salesforce/label/c.AXF_ConfidencePanel_freshnessCurrent";
import freshnessStale from "@salesforce/label/c.AXF_ConfidencePanel_freshnessStale";
import freshnessUnknown from "@salesforce/label/c.AXF_ConfidencePanel_freshnessUnknown";
import limit from "@salesforce/label/c.AXF_ConfidencePanel_limit";
import facts from "@salesforce/label/c.AXF_ConfidencePanel_facts";
import factsUnknown from "@salesforce/label/c.AXF_ConfidencePanel_factsUnknown";
import included from "@salesforce/label/c.AXF_ConfidencePanel_included";
import excluded from "@salesforce/label/c.AXF_ConfidencePanel_excluded";
import openSource from "@salesforce/label/c.AXF_ConfidencePanel_openSource";
import exceptions from "@salesforce/label/c.AXF_ConfidencePanel_exceptions";
import noExceptions from "@salesforce/label/c.AXF_ConfidencePanel_noExceptions";
import exclusions from "@salesforce/label/c.AXF_ConfidencePanel_exclusions";
import noExclusions from "@salesforce/label/c.AXF_ConfidencePanel_noExclusions";
import fx from "@salesforce/label/c.AXF_ConfidencePanel_fx";
import fxSingle from "@salesforce/label/c.AXF_ConfidencePanel_fxSingle";
import fxMulti from "@salesforce/label/c.AXF_ConfidencePanel_fxMulti";
import impactInformative from "@salesforce/label/c.AXF_ConfidencePanel_impactInformative";
import impactDegraded from "@salesforce/label/c.AXF_ConfidencePanel_impactDegraded";
import impactBlocked from "@salesforce/label/c.AXF_ConfidencePanel_impactBlocked";
import allowedActions from "@salesforce/label/c.AXF_ConfidencePanel_allowedActions";
import actionOpenSource from "@salesforce/label/c.AXF_ConfidencePanel_actionOpenSource";
import actionReviewHealth from "@salesforce/label/c.AXF_ConfidencePanel_actionReviewHealth";
import actionNone from "@salesforce/label/c.AXF_ConfidencePanel_actionNone";
import reasonNotAuthorized from "@salesforce/label/c.AXF_ConfidencePanel_reasonNotAuthorized";
import reasonCustody from "@salesforce/label/c.AXF_ConfidencePanel_reasonCustody";
import reasonFieldAccess from "@salesforce/label/c.AXF_ConfidencePanel_reasonFieldAccess";
import reasonNoScope from "@salesforce/label/c.AXF_ConfidencePanel_reasonNoScope";
import reasonPolicyMissing from "@salesforce/label/c.AXF_ConfidencePanel_reasonPolicyMissing";
import exConsentRevoked from "@salesforce/label/c.AXF_ConfidencePanel_exConsentRevoked";
import exConsentStale from "@salesforce/label/c.AXF_ConfidencePanel_exConsentStale";
import exCollectionPaused from "@salesforce/label/c.AXF_ConfidencePanel_exCollectionPaused";
import exStale from "@salesforce/label/c.AXF_ConfidencePanel_exStale";
import exUnknown from "@salesforce/label/c.AXF_ConfidencePanel_exUnknown";
import loading from "@salesforce/label/c.AXF_ConfidencePanel_loading";
import empty from "@salesforce/label/c.AXF_ConfidencePanel_empty";
import errorLabel from "@salesforce/label/c.AXF_ConfidencePanel_error";
import retry from "@salesforce/label/c.AXF_ConfidencePanel_retry";
import codeForbidden from "@salesforce/label/c.AXF_ConfidencePanel_codeForbidden";
import codeInvalidInput from "@salesforce/label/c.AXF_ConfidencePanel_codeInvalidInput";
import updated from "@salesforce/label/c.AXF_ConfidencePanel_updated";
import scopeAvailable from "@salesforce/label/c.AXF_ConfidencePanel_scopeAvailable";
import fxUnknown from "@salesforce/label/c.AXF_ConfidencePanel_fxUnknown";
import reasonNotAHolder from "@salesforce/label/c.AXF_ConfidencePanel_reasonNotAHolder";
import exConnectionNotReadable from "@salesforce/label/c.AXF_ConfidencePanel_exConnectionNotReadable";
import exFutureSuccess from "@salesforce/label/c.AXF_ConfidencePanel_exFutureSuccess";
import exImportDateMissing from "@salesforce/label/c.AXF_ConfidencePanel_exImportDateMissing";
import codeNotAccessible from "@salesforce/label/c.AXF_ConfidencePanel_codeNotAccessible";

const labels = {
  title,
  intro,
  scope,
  scopeHelp,
  explain: explainLabel,
  level,
  levelInformative,
  levelDegraded,
  levelBlocked,
  asOf,
  policy,
  sources,
  source: sourceLabel,
  holder: holderLabel,
  origin,
  originPluggy,
  originManual,
  lastSuccess,
  never,
  freshness,
  freshnessCurrent,
  freshnessStale,
  freshnessUnknown,
  limit,
  facts,
  factsUnknown,
  included,
  excluded,
  openSource,
  exceptions,
  noExceptions,
  exclusions,
  noExclusions,
  fx,
  fxSingle,
  fxMulti,
  impactInformative,
  impactDegraded,
  impactBlocked,
  allowedActions,
  actionOpenSource,
  actionReviewHealth,
  actionNone,
  reasonNotAuthorized,
  reasonCustody,
  reasonFieldAccess,
  reasonNoScope,
  reasonPolicyMissing,
  exConsentRevoked,
  exConsentStale,
  exCollectionPaused,
  exStale,
  exUnknown,
  loading,
  empty,
  error: errorLabel,
  retry,
  codeForbidden,
  codeInvalidInput,
  updated,
  scopeAvailable,
  fxUnknown,
  reasonNotAHolder,
  exConnectionNotReadable,
  exFutureSuccess,
  exImportDateMissing,
  codeNotAccessible
};
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
