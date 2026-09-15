import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
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
  wiredContextResult;
  holderSearch = "";
  holderOptions = [];
  accountId;
  fromDate;
  toDate;
  rows = [];
  runs = [];
  runsError;
  cursor;
  hasMore = false;
  errorMessage;
  announcement = "";
  confirmOpen = false;
  starting = false;
  requestToken = 0;
  runsToken = 0;

  @wire(getContext, { search: "$holderSearch" })
  wiredContext(result) {
    this.wiredContextResult = result;
    const { data, error } = result;
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
    return !this.context || this.context.canRead || this.context.canArchive;
  }
  get isForbidden() {
    return !!this.context && !this.context.canRead && !this.context.canArchive;
  }
  get policyBlocked() {
    return !!this.context && !this.context.hotWindowStart;
  }
  get canRead() {
    return !!(this.context && this.context.canRead);
  }
  get canArchive() {
    return !!(this.context && this.context.canArchive && this.accountId);
  }
  get hotWindowText() {
    return this.context && this.context.hotWindowStart
      ? format(labels.hotWindow, this.formatDay(this.context.hotWindowStart))
      : "";
  }
  /** Last archivable day: the hot window itself is excluded. */
  get maxDate() {
    if (!this.context || !this.context.hotWindowStart) {
      return undefined;
    }
    const day = new Date(this.context.hotWindowStart + "T00:00:00Z");
    day.setUTCDate(day.getUTCDate() - 1);
    return day.toISOString().slice(0, 10);
  }
  formatDay(iso) {
    if (!iso) {
      return "";
    }
    try {
      return new Intl.DateTimeFormat(undefined, {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        timeZone: "UTC"
      }).format(new Date(iso + "T00:00:00Z"));
    } catch {
      return iso;
    }
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
    return (
      !this.accountId ||
      this.state === STATE.LOADING ||
      !this.canRead ||
      this.policyBlocked
    );
  }
  get startDisabled() {
    return this.starting || this.policyBlocked;
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
      watermarkLabel: this.formatDay(run.watermark),
      reasonLabel: run.reason || "",
      hotRemovalLabel:
        run.hotRemoval && run.hotRemoval.startsWith("BLOCKED")
          ? labels.hotBlocked
          : run.hotRemoval || ""
    }));
  }
  get hasRuns() {
    return this.runs.length > 0;
  }

  handleHolderSearch(event) {
    this.holderSearch = event.detail.value || "";
  }
  handleHolderChange(event) {
    this.accountId = event.detail.value;
    this.requestToken++;
    this.rows = [];
    this.cursor = undefined;
    this.hasMore = false;
    this.state = STATE.IDLE;
    this.runsError = undefined;
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
    if (!this.context && this.wiredContextResult) {
      // The context wire failed: refresh it instead of reading with no holder.
      this.state = STATE.INIT;
      refreshApex(this.wiredContextResult);
      return;
    }
    this.load();
  }
  handleDialogKeydown(event) {
    if (event.key === "Escape") {
      this.handleCancelStart();
    }
  }
  handleRefreshRuns() {
    this.loadRuns();
  }
  handleStartArchive() {
    this.confirmOpen = true;
    // Move focus into the dialog once it renders.
    Promise.resolve().then(() => {
      const dialog = this.template.querySelector('[data-id="confirm"]');
      if (dialog) {
        dialog.focus();
      }
    });
  }
  handleCancelStart() {
    this.confirmOpen = false;
    const start = this.template.querySelector('[data-id="start"]');
    if (start) {
      start.focus();
    }
  }
  async handleConfirmStart() {
    this.confirmOpen = false;
    if (this.starting) {
      return;
    }
    this.starting = true;
    const failures = [];
    try {
      for (const family of FAMILIES) {
        try {
          // eslint-disable-next-line no-await-in-loop
          await startArchive({ accountId: this.accountId, family });
        } catch (error) {
          // One family failing never hides the others; the runs table tells which started.
          failures.push(
            (FAMILY_LABEL[family] || family) + ": " + parseFailure(error)
          );
        }
      }
    } finally {
      this.starting = false;
    }
    this.runsError = failures.length ? failures.join(" · ") : undefined;
    this.announcement = this.runsError || labels.started;
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
    const token = ++this.runsToken;
    try {
      const runs = await listRuns({ accountId: this.accountId });
      if (token === this.runsToken) {
        this.runs = runs || [];
      }
    } catch (error) {
      if (token === this.runsToken) {
        this.runs = [];
        this.runsError = parseFailure(error);
      }
    }
  }
}
