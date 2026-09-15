import { LightningElement, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.getContext";
import read from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.read";
import startArchive from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.startArchive";
import listRuns from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.listRuns";
import labels from "./labels";
import { parseFailure, format } from "./failures";

const STATE = {
  INIT: "INIT",
  IDLE: "IDLE",
  LOADING: "LOADING",
  READY: "READY",
  EMPTY: "EMPTY",
  ERROR: "ERROR"
};
const FAMILIES = ["BAT", "CCT", "FTX"];
const FAMILY_LABEL = {
  BAT: labels.familyBAT,
  CCT: labels.familyCCT,
  FTX: labels.familyFTX
};
const DIRECTION_LABEL = {
  CREDIT: labels.directionCREDIT,
  DEBIT: labels.directionDEBIT
};
const PHASE_LABEL = {
  SCANNING: labels.phaseSCANNING,
  WRITING: labels.phaseWRITING,
  VERIFYING: labels.phaseVERIFYING,
  HOT_RETAINED: labels.phaseHOT_RETAINED,
  COMPLETED: labels.phaseCOMPLETED,
  FAILED: labels.phaseFAILED
};

export default class AxfArchiveExplorer extends LightningElement {
  labels = labels;
  state = STATE.INIT;
  context;
  holderOptions = [];
  accountId;
  fromDate;
  toDate;
  rows = [];
  runs = [];
  cursor;
  hasMore = false;
  errorMessage;
  announcement = "";
  confirmOpen = false;
  requestToken = 0;

  @wire(getContext, { search: "" })
  wiredContext({ data, error }) {
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
    if (this.state === STATE.INIT) {
      this.state = STATE.IDLE;
    }
  }

  get canRender() {
    return !this.context || this.context.canRead || this.context.canArchive;
  }
  get canRead() {
    return !!(this.context && this.context.canRead);
  }
  get canArchive() {
    return !!(this.context && this.context.canArchive && this.accountId);
  }
  get hotWindowText() {
    return this.context && this.context.hotWindowStart
      ? format(labels.hotWindow, this.context.hotWindowStart)
      : "";
  }
  get maxDate() {
    return this.context && this.context.hotWindowStart
      ? this.context.hotWindowStart
      : undefined;
  }
  get isIdle() {
    return this.state === STATE.IDLE;
  }
  get isLoading() {
    return this.state === STATE.LOADING;
  }
  get isReady() {
    return this.state === STATE.READY;
  }
  get isEmpty() {
    return this.state === STATE.EMPTY;
  }
  get isError() {
    return this.state === STATE.ERROR;
  }
  get searchDisabled() {
    return !this.accountId || this.state === STATE.LOADING || !this.canRead;
  }
  get tableRows() {
    return this.rows.map((row) => ({
      ...row,
      key: row.archiveKey,
      familyLabel: FAMILY_LABEL[row.family] || row.family,
      directionLabel: DIRECTION_LABEL[row.direction] || row.direction
    }));
  }
  get runRows() {
    return this.runs.map((run) => ({
      ...run,
      key: run.runId,
      familyLabel: FAMILY_LABEL[run.family] || run.family,
      phaseLabel: PHASE_LABEL[run.phase] || run.phase,
      counts: run.scanned + " / " + run.archived + " / " + run.verified,
      hotRemovalLabel:
        run.hotRemoval && run.hotRemoval.startsWith("BLOCKED")
          ? labels.hotBlocked
          : run.hotRemoval || ""
    }));
  }
  get hasRuns() {
    return this.runs.length > 0;
  }

  handleHolderChange(event) {
    this.accountId = event.detail.value;
    this.rows = [];
    this.cursor = undefined;
    this.hasMore = false;
    this.state = STATE.IDLE;
    this.loadRuns();
  }
  handleFromChange(event) {
    this.fromDate = event.detail.value || undefined;
  }
  handleToChange(event) {
    this.toDate = event.detail.value || undefined;
  }
  handleSearch() {
    this.rows = [];
    this.cursor = undefined;
    this.load();
  }
  handleLoadMore() {
    this.load();
  }
  handleRetry() {
    this.errorMessage = undefined;
    this.load();
  }
  handleRefreshRuns() {
    this.loadRuns();
  }
  handleStartArchive() {
    this.confirmOpen = true;
  }
  handleCancelStart() {
    this.confirmOpen = false;
  }
  async handleConfirmStart() {
    this.confirmOpen = false;
    try {
      for (const family of FAMILIES) {
        // eslint-disable-next-line no-await-in-loop
        await startArchive({ accountId: this.accountId, family });
      }
      this.announcement = labels.started;
    } catch (error) {
      this.errorMessage = parseFailure(error);
      this.announcement = this.errorMessage;
      this.state = STATE.ERROR;
    }
    this.loadRuns();
  }

  async load() {
    if (!this.accountId) {
      this.state = STATE.IDLE;
      return;
    }
    const token = ++this.requestToken;
    this.state = STATE.LOADING;
    const request = {
      accountId: this.accountId,
      fromDate: this.fromDate || null,
      toDate: this.toDate || null,
      cursorDate: this.cursor ? this.cursor.date : null,
      cursorKey: this.cursor ? this.cursor.key : null,
      pageSize: 50
    };
    try {
      const result = await read({ request: JSON.stringify(request) });
      if (token !== this.requestToken) {
        return;
      }
      this.rows = this.rows.concat(result.rows || []);
      this.hasMore = !!result.hasMore;
      this.cursor = result.hasMore
        ? { date: result.nextCursorDate, key: result.nextCursorKey }
        : undefined;
      this.state = this.rows.length === 0 ? STATE.EMPTY : STATE.READY;
      this.announcement = labels.updated;
    } catch (error) {
      if (token !== this.requestToken) {
        return;
      }
      this.state = STATE.ERROR;
      this.errorMessage = parseFailure(error);
      this.announcement = this.errorMessage;
    }
  }

  async loadRuns() {
    if (!this.accountId) {
      this.runs = [];
      return;
    }
    try {
      this.runs = await listRuns({ accountId: this.accountId });
    } catch {
      // Runs are informational; a read failure leaves the list empty.
      this.runs = [];
    }
  }
}
