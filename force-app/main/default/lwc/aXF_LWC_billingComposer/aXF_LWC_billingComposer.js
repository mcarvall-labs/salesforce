import { LightningElement, wire } from "lwc";
import getAuthorizedEntities from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getAuthorizedEntities";
import getContracts from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getContracts";
import getCandidates from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getCandidates";
import getApprovedWork from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getApprovedWork";
import compose from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.compose";
import labels from "./labels";

const REASON_LABELS = {
  NOT_ACCESSIBLE: "reasonNotAccessible",
  CONTRACT_MISMATCH: "reasonContractMismatch",
  COUNTERPARTY_MISMATCH: "reasonCounterpartyMismatch",
  ACCOUNT_MISMATCH: "reasonAccountMismatch",
  BLOCKED_FX: "reasonBlockedFx",
  PERIOD_MISMATCH: "reasonPeriodMismatch",
  TYPE_MISMATCH: "reasonTypeMismatch",
  SNAPSHOT_MISSING: "reasonSnapshotMissing",
  SNAPSHOT_STALE: "reasonSnapshotStale",
  ALREADY_BILLED: "reasonAlreadyBilled",
  NOT_PLANNED: "reasonNotPlanned",
  WORK_NOT_APPROVED: "reasonWorkNotApproved",
  WORK_CONTRACT_MISMATCH: "reasonWorkNotApproved",
  WORK_OVER_ALLOCATED: "reasonWorkOverAllocated",
  WORK_INVALID_QUANTITY: "reasonWorkInvalidQuantity",
  DUPLICATE_LINE: "reasonDuplicateLine"
};
const CODE_LABELS = {
  CONFLICT: "codeConflict",
  DOCUMENT_EXISTS: "codeDocumentExists",
  INCOMPATIBLE_LINES: "codeIncompatible",
  INVALID_INPUT: "codeInvalidInput",
  NOT_ACCESSIBLE: "codeNotAccessible",
  TOTAL_NOT_CONSERVED: "codeTotalNotConserved"
};

export function reasonLabel(reason) {
  return labels[REASON_LABELS[reason]] || reason;
}

export function parseFailure(error) {
  const raw = error?.body?.message;
  try {
    const parsed = JSON.parse(raw);
    return {
      message: labels[CODE_LABELS[parsed.code]] || labels.error,
      issues: Array.isArray(parsed.issues) ? parsed.issues : []
    };
  } catch {
    return { message: labels[CODE_LABELS[raw]] || labels.error, issues: [] };
  }
}

function requestKey() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = Math.floor(Math.random() * 16);
    return (c === "x" ? r : (r & 3) | 8).toString(16);
  });
}

export default class BillingComposer extends LightningElement {
  labels = labels;
  entities = [];
  contracts = [];
  candidates = [];
  work = [];
  selection = {};
  allocations = {};
  draft;
  loaded = false;
  busy = false;
  error;
  issues = [];
  success;
  clientRequestId = requestKey();
  form = {
    accountId: "",
    contractId: "",
    counterpartyId: "",
    counterpartyName: "",
    currencyIso: "",
    documentKind: "GENERIC_INVOICE",
    seriesKey: "",
    periodStart: "",
    periodEnd: ""
  };

  @wire(getAuthorizedEntities)
  wiredEntities({ data, error }) {
    if (data) {
      this.entities = data;
    } else if (error) {
      this.error = parseFailure(error).message;
    }
  }

  get entityOptions() {
    return this.entities.map((entity) => ({
      label: entity.label,
      value: entity.accountId
    }));
  }
  get contractOptions() {
    return this.contracts.map((contract) => ({
      label: contract.label,
      value: contract.contractId
    }));
  }
  get kindOptions() {
    return [
      { label: labels.genericInvoice, value: "GENERIC_INVOICE" },
      { label: labels.genericReceipt, value: "GENERIC_RECEIPT" }
    ];
  }
  get workOptions() {
    return this.work
      .filter((record) => record.remainingQuantity > 0)
      .map((record) => ({
        label: `${record.name} · ${labels.remaining} ${record.remainingQuantity}`,
        value: record.workRecordId
      }));
  }
  get hasWork() {
    return this.workOptions.length > 0;
  }
  get contractDisabled() {
    return !this.form.accountId || this.busy;
  }
  get frameComplete() {
    const f = this.form;
    return Boolean(
      f.accountId &&
      f.contractId &&
      f.seriesKey &&
      f.periodStart &&
      f.periodEnd &&
      f.currencyIso
    );
  }
  get loadDisabled() {
    return !this.frameComplete || this.busy;
  }
  get showEmpty() {
    return this.loaded && !this.busy && this.candidates.length === 0;
  }
  get hasCandidates() {
    return this.candidates.length > 0;
  }
  get candidateRows() {
    return this.candidates.map((candidate) => {
      const selected = Boolean(
        this.selection[candidate.financialTransactionId]
      );
      const reasons = (candidate.reasons || []).map((reason) => ({
        key: reason,
        label: reasonLabel(reason)
      }));
      const issueReasons = this.issues
        .filter(
          (issue) =>
            issue.financialTransactionId === candidate.financialTransactionId
        )
        .map((issue) => ({
          key: `${issue.reason}-${issue.workRecordId || ""}`,
          label: reasonLabel(issue.reason)
        }));
      return {
        ...candidate,
        selected,
        disabled: !candidate.eligible || this.busy,
        reasons: reasons.concat(issueReasons),
        hasReasons: reasons.length + issueReasons.length > 0,
        allocations: (
          this.allocations[candidate.financialTransactionId] || []
        ).map((allocation, index) => ({ ...allocation, index })),
        showAllocations: selected && this.hasWork,
        rowClass: selected
          ? "slds-hint-parent axf-row axf-row_selected"
          : "slds-hint-parent axf-row"
      };
    });
  }
  get selectedRows() {
    return this.candidates.filter(
      (candidate) => this.selection[candidate.financialTransactionId]
    );
  }
  get selectedCount() {
    return this.selectedRows.length;
  }
  get selectedTotal() {
    return this.selectedRows
      .reduce((sum, row) => sum + Number(row.amount || 0), 0)
      .toFixed(2);
  }
  get selectedType() {
    const types = new Set(this.selectedRows.map((row) => row.lineType));
    return [...types].join(", ");
  }
  get composeDisabled() {
    return this.busy || this.selectedCount === 0 || !this.frameComplete;
  }
  get holderName() {
    const entity = this.entities.find(
      (row) => row.accountId === this.form.accountId
    );
    return entity ? entity.label : "";
  }
  get contractName() {
    const contract = this.contracts.find(
      (row) => row.contractId === this.form.contractId
    );
    return contract ? contract.label : "";
  }
  get draftLines() {
    return (this.draft?.lines || []).map((line) => ({
      ...line,
      hasAllocations: (line.workAllocations || []).length > 0
    }));
  }

  handleEntity(event) {
    this.form = {
      ...this.form,
      accountId: event.detail.value,
      contractId: "",
      counterpartyId: "",
      counterpartyName: "",
      currencyIso: ""
    };
    this.resetCandidates();
    this.contracts = [];
    if (!this.form.accountId) return;
    this.busy = true;
    getContracts({ accountId: this.form.accountId })
      .then((rows) => {
        this.contracts = rows || [];
      })
      .catch((failure) => {
        this.error = parseFailure(failure).message;
      })
      .finally(() => {
        this.busy = false;
      });
  }
  handleContract(event) {
    const contract = this.contracts.find(
      (row) => row.contractId === event.detail.value
    );
    this.form = {
      ...this.form,
      contractId: event.detail.value,
      counterpartyId: contract?.counterpartyId || "",
      counterpartyName: contract?.counterpartyName || "",
      currencyIso: contract?.currencyIso || ""
    };
    this.resetCandidates();
  }
  handleField(event) {
    const { name, value } = event.target;
    this.form = { ...this.form, [name]: value };
    this.resetCandidates();
  }
  resetCandidates() {
    this.candidates = [];
    this.loaded = false;
    this.work = [];
    this.selection = {};
    this.allocations = {};
    this.issues = [];
    this.error = undefined;
    this.success = undefined;
  }
  async loadCandidates() {
    if (!this.frameComplete) {
      this.error = labels.stepRequired;
      return;
    }
    this.busy = true;
    this.error = undefined;
    this.success = undefined;
    this.issues = [];
    this.selection = {};
    this.allocations = {};
    try {
      const [candidates, work] = await Promise.all([
        getCandidates({
          contractId: this.form.contractId,
          periodStart: this.form.periodStart,
          periodEnd: this.form.periodEnd,
          currencyIso: this.form.currencyIso
        }),
        getApprovedWork({ contractId: this.form.contractId })
      ]);
      this.candidates = candidates || [];
      this.work = work || [];
      this.loaded = true;
    } catch (failure) {
      this.error = parseFailure(failure).message;
      this.candidates = [];
    } finally {
      this.busy = false;
    }
  }
  handleSelect(event) {
    const id = event.target.dataset.id;
    const selection = { ...this.selection };
    if (event.target.checked) {
      selection[id] = true;
    } else {
      delete selection[id];
      const allocations = { ...this.allocations };
      delete allocations[id];
      this.allocations = allocations;
    }
    this.selection = selection;
  }
  addAllocation(event) {
    const id = event.target.dataset.id;
    const list = [...(this.allocations[id] || [])];
    list.push({ workRecordId: this.workOptions[0]?.value || "", quantity: "" });
    this.allocations = { ...this.allocations, [id]: list };
  }
  removeAllocation(event) {
    const { id, index } = event.target.dataset;
    const list = [...(this.allocations[id] || [])];
    list.splice(Number(index), 1);
    this.allocations = { ...this.allocations, [id]: list };
  }
  handleAllocationField(event) {
    const { id, index, field } = event.target.dataset;
    const list = [...(this.allocations[id] || [])];
    list[Number(index)] = {
      ...list[Number(index)],
      [field]: event.detail ? event.detail.value : event.target.value
    };
    this.allocations = { ...this.allocations, [id]: list };
  }
  buildRequest() {
    return {
      accountId: this.form.accountId,
      contractId: this.form.contractId,
      counterpartyId: this.form.counterpartyId,
      documentKind: this.form.documentKind,
      seriesKey: this.form.seriesKey,
      periodStart: this.form.periodStart,
      periodEnd: this.form.periodEnd,
      currencyIso: this.form.currencyIso,
      clientRequestId: this.clientRequestId,
      lines: this.selectedRows.map((row) => ({
        financialTransactionId: row.financialTransactionId,
        snapshotId: row.snapshotId,
        workAllocations: (this.allocations[row.financialTransactionId] || [])
          .filter((allocation) => allocation.workRecordId)
          .map((allocation) => ({
            workRecordId: allocation.workRecordId,
            quantity: Number(allocation.quantity)
          }))
      }))
    };
  }
  async composeDraft() {
    if (this.selectedCount === 0) {
      this.error = labels.selectionRequired;
      return;
    }
    this.busy = true;
    this.error = undefined;
    this.success = undefined;
    this.issues = [];
    try {
      this.draft = await compose({
        request: JSON.stringify(this.buildRequest())
      });
      this.success = labels.success;
    } catch (failure) {
      const parsed = parseFailure(failure);
      this.error = parsed.message;
      this.issues = parsed.issues;
    } finally {
      this.busy = false;
    }
  }
  startNew() {
    this.draft = undefined;
    this.clientRequestId = requestKey();
    this.resetCandidates();
  }
}
