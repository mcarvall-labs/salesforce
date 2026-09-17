import { LightningElement, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.getContext";
import listSources from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.listSources";
import listCandidates from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.listCandidates";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.confirm";
import title from "@salesforce/label/c.AXF_SourceLink_title";
import intro from "@salesforce/label/c.AXF_SourceLink_intro";
import noCapability from "@salesforce/label/c.AXF_SourceLink_noCapability";
import stepSource from "@salesforce/label/c.AXF_SourceLink_stepSource";
import stepCandidate from "@salesforce/label/c.AXF_SourceLink_stepCandidate";
import stepReview from "@salesforce/label/c.AXF_SourceLink_stepReview";
import holder from "@salesforce/label/c.AXF_SourceLink_holder";
import holderPlaceholder from "@salesforce/label/c.AXF_SourceLink_holderPlaceholder";
import kind from "@salesforce/label/c.AXF_SourceLink_kind";
import kindALL from "@salesforce/label/c.AXF_SourceLink_kindALL";
import kindBANK from "@salesforce/label/c.AXF_SourceLink_kindBANK";
import kindCARD from "@salesforce/label/c.AXF_SourceLink_kindCARD";
import search from "@salesforce/label/c.AXF_SourceLink_search";
import loadSources from "@salesforce/label/c.AXF_SourceLink_loadSources";
import loadMore from "@salesforce/label/c.AXF_SourceLink_loadMore";
import loading from "@salesforce/label/c.AXF_SourceLink_loading";
import noSources from "@salesforce/label/c.AXF_SourceLink_noSources";
import excludedSources from "@salesforce/label/c.AXF_SourceLink_excludedSources";
import colDate from "@salesforce/label/c.AXF_SourceLink_colDate";
import colDescription from "@salesforce/label/c.AXF_SourceLink_colDescription";
import colFunding from "@salesforce/label/c.AXF_SourceLink_colFunding";
import colOrigin from "@salesforce/label/c.AXF_SourceLink_colOrigin";
import colAmount from "@salesforce/label/c.AXF_SourceLink_colAmount";
import colResidual from "@salesforce/label/c.AXF_SourceLink_colResidual";
import colDirection from "@salesforce/label/c.AXF_SourceLink_colDirection";
import colDue from "@salesforce/label/c.AXF_SourceLink_colDue";
import colCategory from "@salesforce/label/c.AXF_SourceLink_colCategory";
import colStatus from "@salesforce/label/c.AXF_SourceLink_colStatus";
import colAction from "@salesforce/label/c.AXF_SourceLink_colAction";
import select from "@salesforce/label/c.AXF_SourceLink_select";
import selected from "@salesforce/label/c.AXF_SourceLink_selected";
import directionDEBIT from "@salesforce/label/c.AXF_SourceLink_directionDEBIT";
import directionCREDIT from "@salesforce/label/c.AXF_SourceLink_directionCREDIT";
import sourceSummary from "@salesforce/label/c.AXF_SourceLink_sourceSummary";
import changeSource from "@salesforce/label/c.AXF_SourceLink_changeSource";
import candidatesIntro from "@salesforce/label/c.AXF_SourceLink_candidatesIntro";
import noCandidates from "@salesforce/label/c.AXF_SourceLink_noCandidates";
import virtualBadge from "@salesforce/label/c.AXF_SourceLink_virtualBadge";
import virtualCount from "@salesforce/label/c.AXF_SourceLink_virtualCount";
import scanTruncated from "@salesforce/label/c.AXF_SourceLink_scanTruncated";
import excludedCandidates from "@salesforce/label/c.AXF_SourceLink_excludedCandidates";
import noForecastOption from "@salesforce/label/c.AXF_SourceLink_noForecastOption";
import statusPLANNED from "@salesforce/label/c.AXF_SourceLink_statusPLANNED";
import statusCONFIRMED from "@salesforce/label/c.AXF_SourceLink_statusCONFIRMED";
import statusESTIMATED from "@salesforce/label/c.AXF_SourceLink_statusESTIMATED";
import reviewIntro from "@salesforce/label/c.AXF_SourceLink_reviewIntro";
import target from "@salesforce/label/c.AXF_SourceLink_target";
import targetNone from "@salesforce/label/c.AXF_SourceLink_targetNone";
import amount from "@salesforce/label/c.AXF_SourceLink_amount";
import amountHelp from "@salesforce/label/c.AXF_SourceLink_amountHelp";
import recognitionDate from "@salesforce/label/c.AXF_SourceLink_recognitionDate";
import changed from "@salesforce/label/c.AXF_SourceLink_changed";
import reviewed from "@salesforce/label/c.AXF_SourceLink_reviewed";
import confirmLabel from "@salesforce/label/c.AXF_SourceLink_confirm";
import confirming from "@salesforce/label/c.AXF_SourceLink_confirming";
import back from "@salesforce/label/c.AXF_SourceLink_back";
import done from "@salesforce/label/c.AXF_SourceLink_done";
import doneReplayed from "@salesforce/label/c.AXF_SourceLink_doneReplayed";
import doneActualOnly from "@salesforce/label/c.AXF_SourceLink_doneActualOnly";
import doneAllocation from "@salesforce/label/c.AXF_SourceLink_doneAllocation";
import doneTarget from "@salesforce/label/c.AXF_SourceLink_doneTarget";
import newLink from "@salesforce/label/c.AXF_SourceLink_newLink";
import policy from "@salesforce/label/c.AXF_SourceLink_policy";
import errorLabel from "@salesforce/label/c.AXF_SourceLink_error";
import codeUNAVAILABLE from "@salesforce/label/c.AXF_SourceLink_codeUNAVAILABLE";
import codeNOT_ACCESSIBLE from "@salesforce/label/c.AXF_SourceLink_codeNOT_ACCESSIBLE";
import codeINVALID_INPUT from "@salesforce/label/c.AXF_SourceLink_codeINVALID_INPUT";
import codeINVALID from "@salesforce/label/c.AXF_SourceLink_codeINVALID";
import codeINVALID_SOURCE from "@salesforce/label/c.AXF_SourceLink_codeINVALID_SOURCE";
import codeINVALID_SOURCE_DATA from "@salesforce/label/c.AXF_SourceLink_codeINVALID_SOURCE_DATA";
import codeNOT_POSTED from "@salesforce/label/c.AXF_SourceLink_codeNOT_POSTED";
import codeFUNDING_NOT_AVAILABLE from "@salesforce/label/c.AXF_SourceLink_codeFUNDING_NOT_AVAILABLE";
import codeREVIEW_OPEN from "@salesforce/label/c.AXF_SourceLink_codeREVIEW_OPEN";
import codeSOURCE_EXHAUSTED from "@salesforce/label/c.AXF_SourceLink_codeSOURCE_EXHAUSTED";
import codeALLOCATIONS_UNVERIFIED from "@salesforce/label/c.AXF_SourceLink_codeALLOCATIONS_UNVERIFIED";
import codeINVALID_TARGET from "@salesforce/label/c.AXF_SourceLink_codeINVALID_TARGET";
import codeTARGET_CANCELLED from "@salesforce/label/c.AXF_SourceLink_codeTARGET_CANCELLED";
import codeTARGET_REALIZED from "@salesforce/label/c.AXF_SourceLink_codeTARGET_REALIZED";
import codeFUNDING_MISMATCH from "@salesforce/label/c.AXF_SourceLink_codeFUNDING_MISMATCH";
import codeCURRENCY_MISMATCH from "@salesforce/label/c.AXF_SourceLink_codeCURRENCY_MISMATCH";
import codeALREADY_LINKED from "@salesforce/label/c.AXF_SourceLink_codeALREADY_LINKED";
import codeREVIEW_REQUIRED from "@salesforce/label/c.AXF_SourceLink_codeREVIEW_REQUIRED";
import codeCONFLICT from "@salesforce/label/c.AXF_SourceLink_codeCONFLICT";
import codeUNAVAILABLE_AMOUNT from "@salesforce/label/c.AXF_SourceLink_codeUNAVAILABLE_AMOUNT";
import codeREPORTING_CURRENCY_REQUIRED from "@salesforce/label/c.AXF_SourceLink_codeREPORTING_CURRENCY_REQUIRED";
import codeMATERIALIZATION_REQUIRED from "@salesforce/label/c.AXF_SourceLink_codeMATERIALIZATION_REQUIRED";
import evIntro from "@salesforce/label/c.AXF_SourceLink_evIntro";
import evColumn from "@salesforce/label/c.AXF_SourceLink_evColumn";
import evConsultative from "@salesforce/label/c.AXF_SourceLink_evConsultative";
import evTied from "@salesforce/label/c.AXF_SourceLink_evTied";
import evLowEvidence from "@salesforce/label/c.AXF_SourceLink_evLowEvidence";
import evTieCount from "@salesforce/label/c.AXF_SourceLink_evTieCount";
import evSort from "@salesforce/label/c.AXF_SourceLink_evSort";
import evSortPOLICY from "@salesforce/label/c.AXF_SourceLink_evSortPOLICY";
import evSortDUE_DATE from "@salesforce/label/c.AXF_SourceLink_evSortDUE_DATE";
import evfEXTERNAL_IDENTITY from "@salesforce/label/c.AXF_SourceLink_evfEXTERNAL_IDENTITY";
import evfSOURCE_IDENTITY from "@salesforce/label/c.AXF_SourceLink_evfSOURCE_IDENTITY";
import evfHOLDER from "@salesforce/label/c.AXF_SourceLink_evfHOLDER";
import evfCURRENCY from "@salesforce/label/c.AXF_SourceLink_evfCURRENCY";
import evfAMOUNT from "@salesforce/label/c.AXF_SourceLink_evfAMOUNT";
import evfRESIDUAL from "@salesforce/label/c.AXF_SourceLink_evfRESIDUAL";
import evfDATE from "@salesforce/label/c.AXF_SourceLink_evfDATE";
import evfDESCRIPTION from "@salesforce/label/c.AXF_SourceLink_evfDESCRIPTION";
import evfCATEGORY from "@salesforce/label/c.AXF_SourceLink_evfCATEGORY";
import evrEXACT from "@salesforce/label/c.AXF_SourceLink_evrEXACT";
import evrCONTAINS from "@salesforce/label/c.AXF_SourceLink_evrCONTAINS";
import evrCOVERS from "@salesforce/label/c.AXF_SourceLink_evrCOVERS";
import evrPARTIAL from "@salesforce/label/c.AXF_SourceLink_evrPARTIAL";
import evrDIFFERENT from "@salesforce/label/c.AXF_SourceLink_evrDIFFERENT";
import evrUNKNOWN from "@salesforce/label/c.AXF_SourceLink_evrUNKNOWN";
import evrREDACTED from "@salesforce/label/c.AXF_SourceLink_evrREDACTED";
import evxEXACT from "@salesforce/label/c.AXF_SourceLink_evxEXACT";
import evxCONTAINS from "@salesforce/label/c.AXF_SourceLink_evxCONTAINS";
import evxCOVERS from "@salesforce/label/c.AXF_SourceLink_evxCOVERS";
import evxPARTIAL from "@salesforce/label/c.AXF_SourceLink_evxPARTIAL";
import evxDIFFERENT from "@salesforce/label/c.AXF_SourceLink_evxDIFFERENT";
import evxUNKNOWN from "@salesforce/label/c.AXF_SourceLink_evxUNKNOWN";
import evxREDACTED from "@salesforce/label/c.AXF_SourceLink_evxREDACTED";
import evxDATE_AFTER from "@salesforce/label/c.AXF_SourceLink_evxDATE_AFTER";
import evxDATE_BEFORE from "@salesforce/label/c.AXF_SourceLink_evxDATE_BEFORE";
import originPLUGGY from "@salesforce/label/c.AXF_SourceLink_originPLUGGY";
import originCSV from "@salesforce/label/c.AXF_SourceLink_originCSV";
import originMANUAL from "@salesforce/label/c.AXF_SourceLink_originMANUAL";
import evxDESCRIPTION_CONTAINS_CANDIDATE from "@salesforce/label/c.AXF_SourceLink_evxDESCRIPTION_CONTAINS_CANDIDATE";
import evxDESCRIPTION_CONTAINED_IN_CANDIDATE from "@salesforce/label/c.AXF_SourceLink_evxDESCRIPTION_CONTAINED_IN_CANDIDATE";
import evxCATEGORY_CONTAINS_CANDIDATE from "@salesforce/label/c.AXF_SourceLink_evxCATEGORY_CONTAINS_CANDIDATE";
import evxCATEGORY_CONTAINED_IN_CANDIDATE from "@salesforce/label/c.AXF_SourceLink_evxCATEGORY_CONTAINED_IN_CANDIDATE";

const labels = {
  title,
  intro,
  noCapability,
  stepSource,
  stepCandidate,
  stepReview,
  holder,
  holderPlaceholder,
  kind,
  kindALL,
  kindBANK,
  kindCARD,
  search,
  loadSources,
  loadMore,
  loading,
  noSources,
  excludedSources,
  colDate,
  colDescription,
  colFunding,
  colOrigin,
  colAmount,
  colResidual,
  colDirection,
  colDue,
  colCategory,
  colStatus,
  colAction,
  select,
  selected,
  directionDEBIT,
  directionCREDIT,
  sourceSummary,
  changeSource,
  candidatesIntro,
  noCandidates,
  virtualBadge,
  virtualCount,
  scanTruncated,
  excludedCandidates,
  noForecastOption,
  statusPLANNED,
  statusCONFIRMED,
  statusESTIMATED,
  reviewIntro,
  target,
  targetNone,
  amount,
  amountHelp,
  recognitionDate,
  changed,
  reviewed,
  confirm: confirmLabel,
  confirming,
  back,
  done,
  doneReplayed,
  doneActualOnly,
  doneAllocation,
  doneTarget,
  newLink,
  policy,
  error: errorLabel,
  codeUNAVAILABLE,
  codeNOT_ACCESSIBLE,
  codeINVALID_INPUT,
  codeINVALID,
  codeINVALID_SOURCE,
  codeINVALID_SOURCE_DATA,
  codeNOT_POSTED,
  codeFUNDING_NOT_AVAILABLE,
  codeREVIEW_OPEN,
  codeSOURCE_EXHAUSTED,
  codeALLOCATIONS_UNVERIFIED,
  codeINVALID_TARGET,
  codeTARGET_CANCELLED,
  codeTARGET_REALIZED,
  codeFUNDING_MISMATCH,
  codeCURRENCY_MISMATCH,
  codeALREADY_LINKED,
  codeREVIEW_REQUIRED,
  codeCONFLICT,
  codeUNAVAILABLE_AMOUNT,
  codeREPORTING_CURRENCY_REQUIRED,
  codeMATERIALIZATION_REQUIRED,
  evIntro,
  evColumn,
  evConsultative,
  evTied,
  evLowEvidence,
  evTieCount,
  evSort,
  evSortPOLICY,
  evSortDUE_DATE,
  evfEXTERNAL_IDENTITY,
  evfSOURCE_IDENTITY,
  evfHOLDER,
  evfCURRENCY,
  evfAMOUNT,
  evfRESIDUAL,
  evfDATE,
  evfDESCRIPTION,
  evfCATEGORY,
  evrEXACT,
  evrCONTAINS,
  evrCOVERS,
  evrPARTIAL,
  evrDIFFERENT,
  evrUNKNOWN,
  evrREDACTED,
  evxEXACT,
  evxCONTAINS,
  evxCOVERS,
  evxPARTIAL,
  evxDIFFERENT,
  evxUNKNOWN,
  evxREDACTED,
  evxDATE_AFTER,
  evxDATE_BEFORE,
  originPLUGGY,
  originCSV,
  originMANUAL,
  evxDESCRIPTION_CONTAINS_CANDIDATE,
  evxDESCRIPTION_CONTAINED_IN_CANDIDATE,
  evxCATEGORY_CONTAINS_CANDIDATE,
  evxCATEGORY_CONTAINED_IN_CANDIDATE
};
import { parseFailure, format, newOperationKey } from "./failures";

const STEP = {
  SOURCE: "SOURCE",
  CANDIDATE: "CANDIDATE",
  REVIEW: "REVIEW",
  DONE: "DONE"
};
const KIND_OPTIONS = [
  { label: labels.kindALL, value: "ALL" },
  { label: labels.kindBANK, value: "BANK" },
  { label: labels.kindCARD, value: "CARD" }
];
const DIRECTION_LABEL = {
  DEBIT: labels.directionDEBIT,
  CREDIT: labels.directionCREDIT
};
const SORT_OPTIONS = [
  { label: labels.evSortPOLICY, value: "POLICY" },
  { label: labels.evSortDUE_DATE, value: "DUE_DATE" }
];
function signed(delta) {
  const n = Number(delta);
  return n > 0 ? `+${n}` : `${n}`;
}
/** Evidence stays a fact: feature + relation + explanation resolved from codes, signed deltas, values as sent. */
function evidenceChip(v) {
  const feature = labels["evf" + v.feature] || v.feature;
  const relation = labels["evr" + v.relation] || v.relation;
  const hasDelta = v.delta !== null && v.delta !== undefined;
  let explanation;
  if (v.explanation === "DATE_AFTER" || v.explanation === "DATE_BEFORE") {
    explanation = format(
      labels["evx" + v.explanation],
      Math.abs(Number(v.delta))
    );
  } else if (labels["evx" + v.explanation]) {
    explanation = format(
      labels["evx" + v.explanation],
      hasDelta ? signed(v.delta) : ""
    );
  } else {
    explanation = format(
      labels["evx" + v.relation] || labels.evxUNKNOWN,
      hasDelta ? signed(v.delta) : ""
    );
  }
  const values =
    v.sourceValue || v.candidateValue
      ? ` ${v.sourceValue ?? "?"} → ${v.candidateValue ?? "?"}`
      : "";
  return {
    key: v.feature,
    label: `${feature}: ${relation}`,
    detail: `${explanation}${values}`
  };
}

const ORIGIN_LABEL = {
  PLUGGY: labels.originPLUGGY,
  CSV: labels.originCSV,
  MANUAL: labels.originMANUAL
};
function dedupe(current, incoming, field) {
  const keyOf = (c) => {
    if (field !== "key") {
      return c[field];
    }
    return c.persisted ? c.targetId : `${c.scheduleId}#${c.sequence}`;
  };
  const seen = new Set(current.map(keyOf));
  return [...current, ...incoming.filter((c) => !seen.has(keyOf(c)))];
}
function conflictCode(error) {
  return error && error.body && error.body.message;
}
function validAmount(value) {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value > 0 &&
    Math.round(value * 100) === value * 100
  );
}
const STATUS_LABEL = {
  PLANNED: labels.statusPLANNED,
  CONFIRMED: labels.statusCONFIRMED,
  ESTIMATED: labels.statusESTIMATED
};

function sameDecimal(a, b) {
  return (
    a !== null &&
    a !== undefined &&
    b !== null &&
    b !== undefined &&
    Number(a) === Number(b)
  );
}

export default class AxfSourceLink extends LightningElement {
  labels = labels;
  kindOptions = KIND_OPTIONS;
  step = STEP.SOURCE;
  context;
  holderOptions = [];
  holderId;
  kind = "ALL";
  sourceTerm = "";
  sources = [];
  sourcePage;
  candidateTerm = "";
  sortMode = "POLICY";
  sortOptions = SORT_OPTIONS;
  candidates = [];
  candidatePage;
  source;
  target;
  noForecast = false;
  amount;
  recognitionDate;
  reviewed = false;
  operationKey;
  result;
  busy = false;
  error;

  @wire(getContext, { search: "" })
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      this.holderOptions = (data.holders || []).map((h) => ({
        label: h.name,
        value: h.accountId
      }));
      this.error = undefined;
    } else if (error) {
      this.context = undefined;
      this.error = parseFailure(error);
    }
  }

  get ready() {
    return this.context !== undefined;
  }
  get canLink() {
    return this.context && this.context.canLink === true;
  }
  get cannotLink() {
    return this.context && this.context.canLink !== true;
  }
  get policyVersion() {
    return this.context ? this.context.policyVersion : "";
  }
  get isSourceStep() {
    return this.step === STEP.SOURCE;
  }
  get isCandidateStep() {
    return this.step === STEP.CANDIDATE;
  }
  get isReviewStep() {
    return this.step === STEP.REVIEW;
  }
  get isDone() {
    return this.step === STEP.DONE;
  }
  get loadDisabled() {
    return this.busy || !this.holderId;
  }
  get sourceRows() {
    return this.sources.map((s) => ({
      ...s,
      key: s.sourceId,
      directionLabel: DIRECTION_LABEL[s.direction] || s.direction,
      originLabel: ORIGIN_LABEL[s.origin] || s.origin,
      kindLabel: s.sourceKind === "CARD" ? labels.kindCARD : labels.kindBANK
    }));
  }
  get hasSources() {
    return this.sources.length > 0;
  }
  get showNoSources() {
    return this.sourcePage && this.sources.length === 0;
  }
  get sourcesHasMore() {
    return this.sourcePage && this.sourcePage.hasMore === true;
  }
  get excludedSourcesText() {
    if (!this.sourcePage) {
      return "";
    }
    return format(
      labels.excludedSources,
      this.sourcePage.scannedCount,
      this.sourcePage.excludedCount
    );
  }
  get sourceScanTruncatedText() {
    return this.sourcePage && this.sourcePage.scanTruncated
      ? format(labels.scanTruncated, this.sourcePage.maxScan)
      : "";
  }
  get sourceDirectionLabel() {
    return this.source
      ? DIRECTION_LABEL[this.source.direction] || this.source.direction
      : "";
  }
  get candidateRows() {
    const rows = this.candidates.map((c, i) => ({
      ...c,
      key: c.persisted ? c.targetId : `${c.scheduleId}#${c.sequence}`,
      index: i,
      statusLabel: STATUS_LABEL[c.status] || c.status,
      isVirtual: !c.persisted,
      evidenceChips: (c.evidence || []).map(evidenceChip)
    }));
    if (this.sortMode === "DUE_DATE") {
      // Presentation only: a stable, deterministic re-sort of the same page — never a score.
      // Undated rows go last, as the server order does.
      const due = (row) => row.dueDate || "9999-12-31";
      rows.sort(
        (a, b) => due(a).localeCompare(due(b)) || a.key.localeCompare(b.key)
      );
    }
    return rows;
  }
  get evidenceIntro() {
    if (!this.candidatePage) {
      return "";
    }
    return format(labels.evIntro, this.candidatePage.matchingPolicy);
  }
  get evidenceCutoff() {
    return this.candidatePage ? this.candidatePage.evidenceCutoff : null;
  }
  get tieText() {
    if (
      !this.candidatePage ||
      (!this.candidatePage.tieCount && !this.candidatePage.lowEvidenceCount)
    ) {
      return "";
    }
    return format(
      labels.evTieCount,
      this.candidatePage.tieCount || 0,
      this.candidatePage.lowEvidenceCount || 0
    );
  }
  handleSort(event) {
    this.sortMode = event.detail.value;
  }
  get hasCandidates() {
    return this.candidates.length > 0;
  }
  get showNoCandidates() {
    return this.candidatePage && this.candidates.length === 0;
  }
  get candidatesHasMore() {
    return this.candidatePage && this.candidatePage.hasMore === true;
  }
  get virtualCountText() {
    return this.candidatePage && this.candidatePage.virtualCount > 0
      ? format(labels.virtualCount, this.candidatePage.virtualCount)
      : "";
  }
  get excludedCandidatesText() {
    return this.candidatePage && this.candidatePage.excludedCount > 0
      ? format(labels.excludedCandidates, this.candidatePage.excludedCount)
      : "";
  }
  get scanTruncatedText() {
    return this.candidatePage && this.candidatePage.scanTruncated
      ? format(labels.scanTruncated, this.candidatePage.maxScan)
      : "";
  }
  get suggestedAmount() {
    if (!this.candidatePage || this.candidatePage.suggestedAmount === null) {
      return null;
    }
    const base = Number(this.candidatePage.suggestedAmount);
    return this.target ? Math.min(base, Number(this.target.residual)) : base;
  }
  get suggestedDate() {
    return this.candidatePage ? this.candidatePage.suggestedDate : null;
  }
  get changed() {
    return (
      !sameDecimal(this.amount, this.suggestedAmount) ||
      this.recognitionDate !== this.suggestedDate
    );
  }
  get confirmDisabled() {
    return (
      this.busy ||
      (this.changed && !this.reviewed) ||
      !validAmount(this.amount) ||
      !this.recognitionDate
    );
  }
  get amountInvalid() {
    return (
      this.amount !== null &&
      this.amount !== undefined &&
      !validAmount(this.amount)
    );
  }
  get sourceOriginLabel() {
    return this.source
      ? ORIGIN_LABEL[this.source.origin] || this.source.origin
      : "";
  }
  get hasTarget() {
    return !!this.target;
  }
  get confirmLabel() {
    return this.busy ? labels.confirming : labels.confirm;
  }
  get targetSummary() {
    if (!this.target) {
      return labels.targetNone;
    }
    return this.target.description || this.target.targetId;
  }
  get resultReplayed() {
    return this.result && this.result.replayed === true;
  }
  get resultActualOnly() {
    return this.result && this.result.createdActualOnly === true;
  }

  handleHolder(event) {
    this.holderId = event.detail.value;
    this.resetSources();
  }
  handleKind(event) {
    this.kind = event.detail.value;
    this.resetSources();
  }
  handleSourceTerm(event) {
    this.sourceTerm = event.target.value;
    // A new term starts a new result set: page 2 of one filter never follows page 1 of another.
    this.sources = [];
    this.sourcePage = undefined;
  }
  handleCandidateTerm(event) {
    this.candidateTerm = event.target.value;
    this.candidates = [];
    this.candidatePage = undefined;
  }
  resetSources() {
    this.sources = [];
    this.sourcePage = undefined;
    this.error = undefined;
  }

  async loadSources(more) {
    if (!this.holderId) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    const pageNumber =
      more && this.sourcePage ? this.sourcePage.pageNumber + 1 : 1;
    const requested = {
      holderId: this.holderId,
      kind: this.kind,
      term: this.sourceTerm
    };
    try {
      const page = await listSources({
        request: JSON.stringify({
          accountId: this.holderId,
          sourceKind: this.kind === "ALL" ? null : this.kind,
          term: this.sourceTerm || null,
          pageNumber,
          pageSize: this.context ? this.context.pageSize : null
        })
      });
      if (
        requested.holderId !== this.holderId ||
        requested.kind !== this.kind ||
        requested.term !== this.sourceTerm
      ) {
        return; // the user moved on; never render another holder's facts
      }
      this.sourcePage = page;
      this.sources = more
        ? dedupe(this.sources, page.items, "sourceId")
        : [...page.items];
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }
  handleLoadSources() {
    this.loadSources(false);
  }
  handleMoreSources() {
    this.loadSources(true);
  }

  handleSelectSource(event) {
    const id = event.currentTarget.dataset.id;
    const found = this.sources.find((s) => s.sourceId === id);
    if (!found) {
      return;
    }
    this.source = found;
    this.target = undefined;
    this.noForecast = false;
    this.candidates = [];
    this.candidatePage = undefined;
    this.candidateTerm = "";
    this.step = STEP.CANDIDATE;
    this.loadCandidates(false);
  }

  async loadCandidates(more) {
    if (!this.source) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    const pageNumber =
      more && this.candidatePage ? this.candidatePage.pageNumber + 1 : 1;
    try {
      const page = await listCandidates({
        request: JSON.stringify({
          sourceId: this.source.sourceId,
          sourceKind: this.source.sourceKind,
          term: this.candidateTerm || null,
          pageNumber,
          pageSize: this.context ? this.context.pageSize : null
        })
      });
      this.candidatePage = page;
      this.source = page.source;
      this.candidates = more
        ? dedupe(this.candidates, page.items, "key")
        : [...page.items];
      if (!page.source.eligible) {
        this.error = parseFailure({
          body: { message: page.source.reasons[0] }
        });
      }
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }
  handleSearchCandidates() {
    this.loadCandidates(false);
  }
  handleMoreCandidates() {
    this.loadCandidates(true);
  }
  handleChangeSource() {
    this.step = STEP.SOURCE;
    this.source = undefined;
    this.target = undefined;
    this.error = undefined;
  }
  handleSelectCandidate(event) {
    const index = Number(event.currentTarget.dataset.index);
    const candidate = this.candidates[index];
    if (!candidate || !candidate.linkable) {
      return;
    }
    this.target = candidate;
    this.noForecast = false;
    this.startReview();
  }
  handleNoForecast() {
    this.target = undefined;
    this.noForecast = true;
    this.startReview();
  }
  startReview() {
    this.amount = this.suggestedAmount;
    this.recognitionDate = this.suggestedDate;
    this.reviewed = false;
    this.error = undefined;
    // One key per draft (source + target choice): a retry of the same draft replays,
    // a different choice never collides with an earlier key.
    this.operationKey = newOperationKey();
    this.step = STEP.REVIEW;
  }
  handleAmount(event) {
    this.amount = event.target.value === "" ? null : Number(event.target.value);
    this.reviewed = false;
  }
  handleDate(event) {
    this.recognitionDate = event.target.value || null;
    this.reviewed = false;
  }
  handleReviewed(event) {
    this.reviewed = event.target.checked;
  }
  handleBack() {
    this.step = STEP.CANDIDATE;
    this.error = undefined;
    this.target = undefined;
    this.loadCandidates(false);
  }

  async handleConfirm() {
    if (this.confirmDisabled) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      const result = await confirm({
        request: JSON.stringify({
          sourceId: this.source.sourceId,
          sourceKind: this.source.sourceKind,
          sourceVersion: this.source.version,
          targetId: this.target ? this.target.targetId : null,
          targetVersion: this.target ? this.target.version : null,
          amount: this.amount,
          recognitionDate: this.recognitionDate,
          changesReviewed: this.changed ? this.reviewed : false,
          operationKey: this.operationKey
        })
      });
      this.result = result;
      this.step = STEP.DONE;
    } catch (e) {
      // The draft stays reviewable; the same operation key replays on retry.
      this.error = parseFailure(e);
      if (conflictCode(e) === "CONFLICT") {
        // Versions moved: refresh source and candidates so the draft can be re-reviewed.
        await this.refreshDraft();
      }
    } finally {
      this.busy = false;
    }
  }
  async refreshDraft() {
    const targetId = this.target ? this.target.targetId : null;
    const keep = this.error;
    await this.loadCandidates(false);
    this.error = keep;
    if (targetId) {
      this.target = this.candidates.find(
        (c) => c.persisted && c.targetId === targetId
      );
      if (!this.target) {
        this.step = STEP.CANDIDATE;
        return;
      }
    }
    this.amount = this.suggestedAmount;
    this.recognitionDate = this.suggestedDate;
    this.reviewed = false;
  }

  handleNewLink() {
    this.step = STEP.SOURCE;
    this.source = undefined;
    this.target = undefined;
    this.result = undefined;
    this.operationKey = undefined;
    this.error = undefined;
    this.resetSources();
  }
}
