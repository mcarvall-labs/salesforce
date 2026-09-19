import { LightningElement, api, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_Export.getContext";
import requestExport from "@salesforce/apex/AXF_CLS_CTRL_Export.request";
import readExport from "@salesforce/apex/AXF_CLS_CTRL_Export.read";
import downloadExport from "@salesforce/apex/AXF_CLS_CTRL_Export.download";
import title from "@salesforce/label/c.AXF_Export_title";
import intro from "@salesforce/label/c.AXF_Export_intro";
import noCapability from "@salesforce/label/c.AXF_Export_noCapability";
import loading from "@salesforce/label/c.AXF_Export_loading";
import requestLabel from "@salesforce/label/c.AXF_Export_request";
import refreshLabel from "@salesforce/label/c.AXF_Export_refresh";
import downloadLabel from "@salesforce/label/c.AXF_Export_download";
import statusLabel from "@salesforce/label/c.AXF_Export_statusLabel";
import statusREQUESTED from "@salesforce/label/c.AXF_Export_statusREQUESTED";
import statusPREPARED from "@salesforce/label/c.AXF_Export_statusPREPARED";
import statusDOWNLOADED from "@salesforce/label/c.AXF_Export_statusDOWNLOADED";
import statusREVOKED from "@salesforce/label/c.AXF_Export_statusREVOKED";
import statusRUNNING from "@salesforce/label/c.AXF_Export_statusRUNNING";
import statusPARTIAL from "@salesforce/label/c.AXF_Export_statusPARTIAL";
import { parseFailure, outcomeMessage } from "./failures";

const labels = {
  title,
  intro,
  noCapability,
  loading,
  request: requestLabel,
  refresh: refreshLabel,
  download: downloadLabel,
  statusLabel
};

const STATUS_LABEL = {
  REQUESTED: statusREQUESTED,
  PREPARED: statusPREPARED,
  DOWNLOADED: statusDOWNLOADED,
  REVOKED: statusREVOKED,
  RUNNING: statusRUNNING,
  PARTIAL: statusPARTIAL
};

/**
 * AXF-118 request/status/download screen. Every mutation goes through
 * AXF_CLS_CTRL_Export, which is a thin pass-through: this component never decides
 * authorization, capability, resumability or the download window itself — the server
 * revalidates all of that on every call, exactly as it did before this UI existed.
 */
export default class AxfExport extends LightningElement {
  labels = labels;
  /** The holder Account this export is scoped to (record page context). */
  @api recordId;
  context;
  run;
  busy = false;
  error;

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      this.error = undefined;
    } else if (error) {
      this.context = undefined;
      this.error = parseFailure(error);
    }
  }

  get canExport() {
    return this.context && this.context.canExport === true;
  }
  get cannotExport() {
    return this.context && this.context.canExport !== true;
  }
  get canDownload() {
    return !!(this.run && this.run.canDownload);
  }
  get refreshDisabled() {
    return this.busy || !this.run;
  }
  get statusText() {
    if (!this.run) {
      return "";
    }
    return STATUS_LABEL[this.run.status] || this.run.status;
  }

  async handleRequest() {
    if (!this.recordId || this.busy) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      this.run = await requestExport({
        accountId: this.recordId,
        expectedVersion: this.run ? this.run.version : null
      });
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }

  async handleRefresh() {
    if (!this.run || this.busy) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      this.run = await readExport({ runId: this.run.runId });
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }

  async handleDownload() {
    if (!this.run || this.busy) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      const result = await downloadExport({
        runId: this.run.runId,
        expectedVersion: this.run.version
      });
      if (result.ready) {
        this.triggerDownload(result);
      } else {
        this.error = outcomeMessage(result.outcome);
      }
      try {
        this.run = await readExport({ runId: this.run.runId });
      } catch (refreshError) {
        // Only overwrite this.error when there wasn't already a more specific outcome-based
        // message set above (result.ready === true, so this.error is still undefined here).
        if (!this.error) {
          this.error = parseFailure(refreshError);
        }
      }
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }

  /** Client-side only: the bytes already came from an authorized, revalidated download(). */
  triggerDownload(result) {
    const raw = atob(result.bodyBase64);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) {
      bytes[i] = raw.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: result.mimeType });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = result.fileName;
    link.click();
    URL.revokeObjectURL(url);
  }
}
