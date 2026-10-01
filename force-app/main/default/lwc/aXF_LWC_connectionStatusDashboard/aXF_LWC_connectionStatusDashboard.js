import { LightningElement, wire } from "lwc";
import getDashboard from "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.getDashboard";

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
  { label: "Mensagem de erro", fieldName: "errorMessage" }
];

export default class AXF_LWC_connectionStatusDashboard extends LightningElement {
  columns = COLUMNS;
  data;
  error;

  @wire(getDashboard)
  wiredDashboard({ data, error }) {
    if (data) {
      this.data = data;
      this.error = undefined;
    } else if (error) {
      this.data = undefined;
      this.error = error;
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
