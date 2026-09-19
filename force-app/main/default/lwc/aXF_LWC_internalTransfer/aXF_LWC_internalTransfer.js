import { LightningElement, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.getContext";
import listPending from "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.listPending";
import confirmTransfer from "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.confirm";
import title from "@salesforce/label/c.AXF_InternalTransfer_title";
import intro from "@salesforce/label/c.AXF_InternalTransfer_intro";
import noCapability from "@salesforce/label/c.AXF_InternalTransfer_noCapability";
import loading from "@salesforce/label/c.AXF_InternalTransfer_loading";
import empty from "@salesforce/label/c.AXF_InternalTransfer_empty";
import colDebit from "@salesforce/label/c.AXF_InternalTransfer_colDebit";
import colCredit from "@salesforce/label/c.AXF_InternalTransfer_colCredit";
import colAmount from "@salesforce/label/c.AXF_InternalTransfer_colAmount";
import colDate from "@salesforce/label/c.AXF_InternalTransfer_colDate";
import confirmLabelText from "@salesforce/label/c.AXF_InternalTransfer_confirm";
import confirmingLabel from "@salesforce/label/c.AXF_InternalTransfer_confirming";
import feesNote from "@salesforce/label/c.AXF_InternalTransfer_feesNote";
import doneConfirmed from "@salesforce/label/c.AXF_InternalTransfer_doneConfirmed";
import doneUnilateral from "@salesforce/label/c.AXF_InternalTransfer_doneUnilateral";
import doneReplayed from "@salesforce/label/c.AXF_InternalTransfer_doneReplayed";
import refresh from "@salesforce/label/c.AXF_InternalTransfer_refresh";
import { parseFailure, newOperationKey } from "./failures";

const labels = {
  title,
  intro,
  noCapability,
  loading,
  empty,
  colDebit,
  colCredit,
  colAmount,
  colDate,
  confirm: confirmLabelText,
  confirming: confirmingLabel,
  feesNote,
  doneConfirmed,
  doneUnilateral,
  doneReplayed,
  refresh
};

export default class AxfInternalTransfer extends LightningElement {
  labels = labels;
  context;
  items = [];
  busy = false;
  loaded = false;
  error;
  operationKeys = {};

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      this.error = undefined;
      if (data.canConfirm) {
        this.load();
      }
    } else if (error) {
      this.context = undefined;
      this.error = parseFailure(error);
    }
  }

  get canConfirm() {
    return this.context && this.context.canConfirm === true;
  }
  get cannotConfirm() {
    return this.context && this.context.canConfirm !== true;
  }
  get showEmpty() {
    return this.loaded && !this.busy && this.rows.length === 0;
  }
  get rows() {
    return this.items.map((item, index) => ({
      ...item,
      index,
      key: item.internalTransferId,
      confirmLabel: item.busy ? labels.confirming : labels.confirm,
      done: !!item.result,
      resultLabel: this.resultLabel(item.result)
    }));
  }

  resultLabel(result) {
    if (!result) {
      return "";
    }
    if (result.replayed) {
      return labels.doneReplayed;
    }
    return result.state === "CONFIRMED"
      ? labels.doneConfirmed
      : labels.doneUnilateral;
  }

  async load() {
    this.busy = true;
    this.error = undefined;
    try {
      const items = await listPending();
      this.items = (items || []).map((item) => {
        if (!this.operationKeys[item.internalTransferId]) {
          this.operationKeys[item.internalTransferId] = newOperationKey();
        }
        return {
          ...item,
          operationKey: this.operationKeys[item.internalTransferId],
          busy: false,
          result: undefined,
          rowError: undefined
        };
      });
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
      this.loaded = true;
    }
  }

  async handleConfirm(event) {
    const index = Number(event.currentTarget.dataset.index);
    const row = this.items[index];
    if (!row || row.busy) {
      return;
    }
    row.busy = true;
    row.rowError = undefined;
    this.items = [...this.items];
    try {
      const result = await confirmTransfer({
        request: JSON.stringify({
          internalTransferId: row.internalTransferId,
          expectedVersion: row.version,
          operationKey: row.operationKey
        })
      });
      row.result = result;
      row.state = result.state;
    } catch (e) {
      row.rowError = parseFailure(e);
    } finally {
      row.busy = false;
      this.items = [...this.items];
    }
  }

  handleRefresh() {
    this.load();
  }
}
