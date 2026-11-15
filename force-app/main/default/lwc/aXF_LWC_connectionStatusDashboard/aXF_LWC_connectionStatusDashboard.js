import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getDashboard from "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.getDashboard";
import syncConnection from "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.syncConnection";

const STATUS_LABELS = { Active: "Ativa", Error: "Erro", Paused: "Pausada" };

const COLUMNS = [
  { label: "Titular", fieldName: "holder" },
  { label: "Instituição", fieldName: "institution" },
  { label: "Status", fieldName: "statusLabel" },
  {
    label: "Último sync",
    fieldName: "lastSync",
    type: "date",
    typeAttributes: {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  },
  { label: "Mensagem de erro", fieldName: "errorMessage" },
  {
    type: "button",
    typeAttributes: { label: "Sincronizar", name: "sync" }
  }
];

export default class AXF_LWC_connectionStatusDashboard extends LightningElement {
  columns = COLUMNS;
  data;
  error;
  syncingId;
  syncMessage;
  syncSuccess = false;
  wiredResult;

  @wire(getDashboard)
  wiredDashboard(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.data = data;
      this.error = undefined;
    } else if (error) {
      this.data = undefined;
      this.error = error;
    }
  }

  get syncClass() {
    return this.syncSuccess
      ? "slds-text-color_success"
      : "slds-text-color_error";
  }

  async handleRowAction(event) {
    if (event.detail.action.name !== "sync" || this.syncingId) {
      return;
    }
    this.syncingId = event.detail.row.id;
    this.syncMessage = undefined;
    try {
      const result = await syncConnection({ connectionId: this.syncingId });
      this.syncSuccess = result.success;
      this.syncMessage = result.message;
      await refreshApex(this.wiredResult);
    } catch {
      this.syncSuccess = false;
      this.syncMessage = "Não foi possível sincronizar a conexão.";
    } finally {
      this.syncingId = undefined;
    }
  }

  get isLoading() {
    return !this.data && !this.error;
  }

  get hasRows() {
    return !!this.data && this.data.rows.length > 0;
  }

  get rows() {
    return this.data
      ? this.data.rows.map((row) => ({
          ...row,
          statusLabel: STATUS_LABELS[row.status] || row.status
        }))
      : [];
  }
}
