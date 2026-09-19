import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.getContext";
import read from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.read";
import startArchive from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.startArchive";
import listRuns from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.listRuns";
import title from "@salesforce/label/c.AXF_ArchiveExplorer_title";
import intro from "@salesforce/label/c.AXF_ArchiveExplorer_intro";
import holderLabel from "@salesforce/label/c.AXF_ArchiveExplorer_holder";
import holderPlaceholder from "@salesforce/label/c.AXF_ArchiveExplorer_holderPlaceholder";
import from from "@salesforce/label/c.AXF_ArchiveExplorer_from";
import to from "@salesforce/label/c.AXF_ArchiveExplorer_to";
import hotWindow from "@salesforce/label/c.AXF_ArchiveExplorer_hotWindow";
import search from "@salesforce/label/c.AXF_ArchiveExplorer_search";
import loadMore from "@salesforce/label/c.AXF_ArchiveExplorer_loadMore";
import loading from "@salesforce/label/c.AXF_ArchiveExplorer_loading";
import empty from "@salesforce/label/c.AXF_ArchiveExplorer_empty";
import idle from "@salesforce/label/c.AXF_ArchiveExplorer_idle";
import archivedBadge from "@salesforce/label/c.AXF_ArchiveExplorer_archivedBadge";
import readOnly from "@salesforce/label/c.AXF_ArchiveExplorer_readOnly";
import colDate from "@salesforce/label/c.AXF_ArchiveExplorer_colDate";
import colDescription from "@salesforce/label/c.AXF_ArchiveExplorer_colDescription";
import colAmount from "@salesforce/label/c.AXF_ArchiveExplorer_colAmount";
import colDirection from "@salesforce/label/c.AXF_ArchiveExplorer_colDirection";
import colStatus from "@salesforce/label/c.AXF_ArchiveExplorer_colStatus";
import colInstitution from "@salesforce/label/c.AXF_ArchiveExplorer_colInstitution";
import colFamily from "@salesforce/label/c.AXF_ArchiveExplorer_colFamily";
import familyBAT from "@salesforce/label/c.AXF_ArchiveExplorer_familyBAT";
import familyCCT from "@salesforce/label/c.AXF_ArchiveExplorer_familyCCT";
import familyFTX from "@salesforce/label/c.AXF_ArchiveExplorer_familyFTX";
import directionCREDIT from "@salesforce/label/c.AXF_ArchiveExplorer_directionCREDIT";
import directionDEBIT from "@salesforce/label/c.AXF_ArchiveExplorer_directionDEBIT";
import runsLabel from "@salesforce/label/c.AXF_ArchiveExplorer_runs";
import noRuns from "@salesforce/label/c.AXF_ArchiveExplorer_noRuns";
import startArchiveLabel from "@salesforce/label/c.AXF_ArchiveExplorer_startArchive";
import startConfirm from "@salesforce/label/c.AXF_ArchiveExplorer_startConfirm";
import confirm from "@salesforce/label/c.AXF_ArchiveExplorer_confirm";
import cancel from "@salesforce/label/c.AXF_ArchiveExplorer_cancel";
import started from "@salesforce/label/c.AXF_ArchiveExplorer_started";
import refresh from "@salesforce/label/c.AXF_ArchiveExplorer_refresh";
import colFamilyRun from "@salesforce/label/c.AXF_ArchiveExplorer_colFamilyRun";
import colPhase from "@salesforce/label/c.AXF_ArchiveExplorer_colPhase";
import colCounts from "@salesforce/label/c.AXF_ArchiveExplorer_colCounts";
import colWatermark from "@salesforce/label/c.AXF_ArchiveExplorer_colWatermark";
import colHotRemoval from "@salesforce/label/c.AXF_ArchiveExplorer_colHotRemoval";
import colCheckpoint from "@salesforce/label/c.AXF_ArchiveExplorer_colCheckpoint";
import phaseSCANNING from "@salesforce/label/c.AXF_ArchiveExplorer_phaseSCANNING";
import phaseWRITING from "@salesforce/label/c.AXF_ArchiveExplorer_phaseWRITING";
import phaseVERIFYING from "@salesforce/label/c.AXF_ArchiveExplorer_phaseVERIFYING";
import phaseHOT_RETAINED from "@salesforce/label/c.AXF_ArchiveExplorer_phaseHOT_RETAINED";
import phaseCOMPLETED from "@salesforce/label/c.AXF_ArchiveExplorer_phaseCOMPLETED";
import phaseFAILED from "@salesforce/label/c.AXF_ArchiveExplorer_phaseFAILED";
import hotBlocked from "@salesforce/label/c.AXF_ArchiveExplorer_hotBlocked";
import errorLabel from "@salesforce/label/c.AXF_ArchiveExplorer_error";
import retry from "@salesforce/label/c.AXF_ArchiveExplorer_retry";
import codeForbidden from "@salesforce/label/c.AXF_ArchiveExplorer_codeForbidden";
import codeNotAccessible from "@salesforce/label/c.AXF_ArchiveExplorer_codeNotAccessible";
import codeInvalidInput from "@salesforce/label/c.AXF_ArchiveExplorer_codeInvalidInput";
import codePolicy from "@salesforce/label/c.AXF_ArchiveExplorer_codePolicy";
import codeRunInProgress from "@salesforce/label/c.AXF_ArchiveExplorer_codeRunInProgress";
import codeAsync from "@salesforce/label/c.AXF_ArchiveExplorer_codeAsync";
import updated from "@salesforce/label/c.AXF_ArchiveExplorer_updated";
import holderSearch from "@salesforce/label/c.AXF_ArchiveExplorer_holderSearch";
import colReason from "@salesforce/label/c.AXF_ArchiveExplorer_colReason";

const labels = {
  title,
  intro,
  holder: holderLabel,
  holderPlaceholder,
  from,
  to,
  hotWindow,
  search,
  loadMore,
  loading,
  empty,
  idle,
  archivedBadge,
  readOnly,
  colDate,
  colDescription,
  colAmount,
  colDirection,
  colStatus,
  colInstitution,
  colFamily,
  familyBAT,
  familyCCT,
  familyFTX,
  directionCREDIT,
  directionDEBIT,
  runs: runsLabel,
  noRuns,
  startArchive: startArchiveLabel,
  startConfirm,
  confirm,
  cancel,
  started,
  refresh,
  colFamilyRun,
  colPhase,
  colCounts,
  colWatermark,
  colHotRemoval,
  colCheckpoint,
  phaseSCANNING,
  phaseWRITING,
  phaseVERIFYING,
  phaseHOT_RETAINED,
  phaseCOMPLETED,
  phaseFAILED,
  hotBlocked,
  error: errorLabel,
  retry,
  codeForbidden,
  codeNotAccessible,
  codeInvalidInput,
  codePolicy,
  codeRunInProgress,
  codeAsync,
  updated,
  holderSearch,
  colReason
};
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
