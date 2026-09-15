import { LightningElement, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.getContext";
import listSources from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.listSources";
import listCandidates from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.listCandidates";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.confirm";
import labels from "./labels";
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
/** AXF-140: the state comes from the server; the component renders it and derives nothing. */
const STATE_LABEL = {
  CONSULTATIVE: labels.evConsultative,
  BLOCKED: labels.evBlocked
};
/** AXF-140: the conversion evidence is rendered as sent — an omitted amount stays omitted. */
function conversionLine(c) {
  if (!c.conversion) {
    return "";
  }
  const pair = `${c.conversion.originalIso}/${c.conversion.reportingIso}`;
  if (c.conversion.state === "ESTIMATED") {
    return `${labels.convEstimatedLine} ${c.conversion.convertedAmount} ${c.conversion.reportingIso} · 1 ${c.conversion.originalIso} = ${c.conversion.rate} ${c.conversion.reportingIso} (${c.conversion.provider})`;
  }
  if (c.conversion.state === "STALE") {
    // The quote is a fact; a converted amount is not, so none is shown.
    return `${labels.convStaleLine} ${pair} · 1 ${c.conversion.originalIso} = ${c.conversion.rate} ${c.conversion.reportingIso} (${c.conversion.provider})`;
  }
  return `${labels.convUnavailableLine} ${pair}`;
}
/** AXF-140: the remaining residual is shown whenever it exists, including a non-zero one. */
function residualAfterLine(c) {
  if (c.residualAfter === null || c.residualAfter === undefined) {
    return "";
  }
  return `${labels.factResidualAfter} ${c.residualAfter} ${c.currencyIso}`;
}
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
      stateLabel: STATE_LABEL[c.state] || c.state,
      conversionLine: conversionLine(c),
      residualAfterLine: residualAfterLine(c),
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
