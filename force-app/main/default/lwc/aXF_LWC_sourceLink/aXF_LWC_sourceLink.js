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
  get sourceDirectionLabel() {
    return this.source
      ? DIRECTION_LABEL[this.source.direction] || this.source.direction
      : "";
  }
  get candidateRows() {
    return this.candidates.map((c, i) => ({
      ...c,
      key: c.persisted ? c.targetId : `${c.scheduleId}#${c.sequence}`,
      index: i,
      statusLabel: STATUS_LABEL[c.status] || c.status,
      isSelected:
        this.target && c.persisted && this.target.targetId === c.targetId
    }));
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
      ? format(labels.scanTruncated, 200)
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
      !this.amount ||
      !this.recognitionDate
    );
  }
  get confirmLabel() {
    return this.busy ? labels.confirming : labels.confirm;
  }
  get targetSummary() {
    if (!this.target) {
      return labels.targetNone;
    }
    return `${this.target.description || this.target.targetId} · ${this.target.dueDate} · ${this.target.residual} ${this.target.currencyIso}`;
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
  }
  handleCandidateTerm(event) {
    this.candidateTerm = event.target.value;
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
      this.sourcePage = page;
      this.sources = more ? [...this.sources, ...page.items] : [...page.items];
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
    this.operationKey = newOperationKey();
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
        ? [...this.candidates, ...page.items]
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
    } finally {
      this.busy = false;
    }
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
