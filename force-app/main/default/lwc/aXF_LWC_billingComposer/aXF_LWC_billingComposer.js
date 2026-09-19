import { LightningElement, wire } from "lwc";
import getAuthorizedEntities from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getAuthorizedEntities";
import getContracts from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getContracts";
import getCandidates from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getCandidates";
import getApprovedWork from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getApprovedWork";
import compose from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.compose";
import title from "@salesforce/label/c.AXF_BillingComposer_title";
import intro from "@salesforce/label/c.AXF_BillingComposer_intro";
import holder from "@salesforce/label/c.AXF_BillingComposer_holder";
import contractLabel from "@salesforce/label/c.AXF_BillingComposer_contract";
import counterparty from "@salesforce/label/c.AXF_BillingComposer_counterparty";
import currency from "@salesforce/label/c.AXF_BillingComposer_currency";
import documentKind from "@salesforce/label/c.AXF_BillingComposer_documentKind";
import genericInvoice from "@salesforce/label/c.AXF_BillingComposer_genericInvoice";
import genericReceipt from "@salesforce/label/c.AXF_BillingComposer_genericReceipt";
import seriesKey from "@salesforce/label/c.AXF_BillingComposer_seriesKey";
import periodStart from "@salesforce/label/c.AXF_BillingComposer_periodStart";
import periodEnd from "@salesforce/label/c.AXF_BillingComposer_periodEnd";
import loadCandidates from "@salesforce/label/c.AXF_BillingComposer_loadCandidates";
import candidatesLabel from "@salesforce/label/c.AXF_BillingComposer_candidates";
import select from "@salesforce/label/c.AXF_BillingComposer_select";
import entry from "@salesforce/label/c.AXF_BillingComposer_entry";
import snapshot from "@salesforce/label/c.AXF_BillingComposer_snapshot";
import amount from "@salesforce/label/c.AXF_BillingComposer_amount";
import serviceDate from "@salesforce/label/c.AXF_BillingComposer_serviceDate";
import lineType from "@salesforce/label/c.AXF_BillingComposer_lineType";
import incompatibilities from "@salesforce/label/c.AXF_BillingComposer_incompatibilities";
import eligible from "@salesforce/label/c.AXF_BillingComposer_eligible";
import noCandidates from "@salesforce/label/c.AXF_BillingComposer_noCandidates";
import workAllocations from "@salesforce/label/c.AXF_BillingComposer_workAllocations";
import workRecord from "@salesforce/label/c.AXF_BillingComposer_workRecord";
import remaining from "@salesforce/label/c.AXF_BillingComposer_remaining";
import quantityLabel from "@salesforce/label/c.AXF_BillingComposer_quantity";
import addAllocation from "@salesforce/label/c.AXF_BillingComposer_addAllocation";
import removeAllocation from "@salesforce/label/c.AXF_BillingComposer_removeAllocation";
import noWork from "@salesforce/label/c.AXF_BillingComposer_noWork";
import summary from "@salesforce/label/c.AXF_BillingComposer_summary";
import selectedLines from "@salesforce/label/c.AXF_BillingComposer_selectedLines";
import total from "@salesforce/label/c.AXF_BillingComposer_total";
import composeLabel from "@salesforce/label/c.AXF_BillingComposer_compose";
import composing from "@salesforce/label/c.AXF_BillingComposer_composing";
import loading from "@salesforce/label/c.AXF_BillingComposer_loading";
import draft from "@salesforce/label/c.AXF_BillingComposer_draft";
import document from "@salesforce/label/c.AXF_BillingComposer_document";
import revision from "@salesforce/label/c.AXF_BillingComposer_revision";
import stateFieldLabel from "@salesforce/label/c.AXF_BillingComposer_state";
import origin from "@salesforce/label/c.AXF_BillingComposer_origin";
import lines from "@salesforce/label/c.AXF_BillingComposer_lines";
import linesTotal from "@salesforce/label/c.AXF_BillingComposer_linesTotal";
import newDraft from "@salesforce/label/c.AXF_BillingComposer_newDraft";
import success from "@salesforce/label/c.AXF_BillingComposer_success";
import errorLabel from "@salesforce/label/c.AXF_BillingComposer_error";
import selectionRequired from "@salesforce/label/c.AXF_BillingComposer_selectionRequired";
import stepRequired from "@salesforce/label/c.AXF_BillingComposer_stepRequired";
import reasonNotAccessible from "@salesforce/label/c.AXF_BillingComposer_reasonNotAccessible";
import reasonContractMismatch from "@salesforce/label/c.AXF_BillingComposer_reasonContractMismatch";
import reasonCounterpartyMismatch from "@salesforce/label/c.AXF_BillingComposer_reasonCounterpartyMismatch";
import reasonAccountMismatch from "@salesforce/label/c.AXF_BillingComposer_reasonAccountMismatch";
import reasonBlockedFx from "@salesforce/label/c.AXF_BillingComposer_reasonBlockedFx";
import reasonPeriodMismatch from "@salesforce/label/c.AXF_BillingComposer_reasonPeriodMismatch";
import reasonTypeMismatch from "@salesforce/label/c.AXF_BillingComposer_reasonTypeMismatch";
import reasonSnapshotMissing from "@salesforce/label/c.AXF_BillingComposer_reasonSnapshotMissing";
import reasonSnapshotStale from "@salesforce/label/c.AXF_BillingComposer_reasonSnapshotStale";
import reasonAlreadyBilled from "@salesforce/label/c.AXF_BillingComposer_reasonAlreadyBilled";
import reasonNotPlanned from "@salesforce/label/c.AXF_BillingComposer_reasonNotPlanned";
import reasonWorkNotApproved from "@salesforce/label/c.AXF_BillingComposer_reasonWorkNotApproved";
import reasonWorkOverAllocated from "@salesforce/label/c.AXF_BillingComposer_reasonWorkOverAllocated";
import reasonWorkInvalidQuantity from "@salesforce/label/c.AXF_BillingComposer_reasonWorkInvalidQuantity";
import reasonDuplicateLine from "@salesforce/label/c.AXF_BillingComposer_reasonDuplicateLine";
import codeConflict from "@salesforce/label/c.AXF_BillingComposer_codeConflict";
import codeDocumentExists from "@salesforce/label/c.AXF_BillingComposer_codeDocumentExists";
import codeIncompatible from "@salesforce/label/c.AXF_BillingComposer_codeIncompatible";
import codeInvalidInput from "@salesforce/label/c.AXF_BillingComposer_codeInvalidInput";
import codeNotAccessible from "@salesforce/label/c.AXF_BillingComposer_codeNotAccessible";
import codeTotalNotConserved from "@salesforce/label/c.AXF_BillingComposer_codeTotalNotConserved";
import codeRejected from "@salesforce/label/c.AXF_BillingComposer_codeRejected";
import codeContractNotBillable from "@salesforce/label/c.AXF_BillingComposer_codeContractNotBillable";
import reasonInvalidAmount from "@salesforce/label/c.AXF_BillingComposer_reasonInvalidAmount";
import reasonWorkContractMismatch from "@salesforce/label/c.AXF_BillingComposer_reasonWorkContractMismatch";
import noEntities from "@salesforce/label/c.AXF_BillingComposer_noEntities";
import contractIncomplete from "@salesforce/label/c.AXF_BillingComposer_contractIncomplete";
import periodInvalid from "@salesforce/label/c.AXF_BillingComposer_periodInvalid";
import quantityRequired from "@salesforce/label/c.AXF_BillingComposer_quantityRequired";
import duplicateWork from "@salesforce/label/c.AXF_BillingComposer_duplicateWork";
import typeMixed from "@salesforce/label/c.AXF_BillingComposer_typeMixed";
import remainingBalance from "@salesforce/label/c.AXF_BillingComposer_remainingBalance";
import stateDraft from "@salesforce/label/c.AXF_BillingComposer_stateDraft";
import stateReviewed from "@salesforce/label/c.AXF_BillingComposer_stateReviewed";
import stateIssuing from "@salesforce/label/c.AXF_BillingComposer_stateIssuing";
import stateIssued from "@salesforce/label/c.AXF_BillingComposer_stateIssued";
import stateCancelled from "@salesforce/label/c.AXF_BillingComposer_stateCancelled";
import lifecycleOpen from "@salesforce/label/c.AXF_BillingComposer_lifecycleOpen";
import lifecycleClosed from "@salesforce/label/c.AXF_BillingComposer_lifecycleClosed";

const labels = {
  title,
  intro,
  holder,
  contract: contractLabel,
  counterparty,
  currency,
  documentKind,
  genericInvoice,
  genericReceipt,
  seriesKey,
  periodStart,
  periodEnd,
  loadCandidates,
  candidates: candidatesLabel,
  select,
  entry,
  snapshot,
  amount,
  serviceDate,
  lineType,
  incompatibilities,
  eligible,
  noCandidates,
  workAllocations,
  workRecord,
  remaining,
  quantity: quantityLabel,
  addAllocation,
  removeAllocation,
  noWork,
  summary,
  selectedLines,
  total,
  compose: composeLabel,
  composing,
  loading,
  draft,
  document,
  revision,
  state: stateFieldLabel,
  origin,
  lines,
  linesTotal,
  newDraft,
  success,
  error: errorLabel,
  selectionRequired,
  stepRequired,
  reasonNotAccessible,
  reasonContractMismatch,
  reasonCounterpartyMismatch,
  reasonAccountMismatch,
  reasonBlockedFx,
  reasonPeriodMismatch,
  reasonTypeMismatch,
  reasonSnapshotMissing,
  reasonSnapshotStale,
  reasonAlreadyBilled,
  reasonNotPlanned,
  reasonWorkNotApproved,
  reasonWorkOverAllocated,
  reasonWorkInvalidQuantity,
  reasonDuplicateLine,
  codeConflict,
  codeDocumentExists,
  codeIncompatible,
  codeInvalidInput,
  codeNotAccessible,
  codeTotalNotConserved,
  codeRejected,
  codeContractNotBillable,
  reasonInvalidAmount,
  reasonWorkContractMismatch,
  noEntities,
  contractIncomplete,
  periodInvalid,
  quantityRequired,
  duplicateWork,
  typeMixed,
  remainingBalance,
  stateDraft,
  stateReviewed,
  stateIssuing,
  stateIssued,
  stateCancelled,
  lifecycleOpen,
  lifecycleClosed
};

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
  WORK_CONTRACT_MISMATCH: "reasonWorkContractMismatch",
  INVALID_AMOUNT: "reasonInvalidAmount",
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
  TOTAL_NOT_CONSERVED: "codeTotalNotConserved",
  REJECTED: "codeRejected",
  UNEXPECTED: "error",
  ACCOUNT_MISMATCH: "reasonAccountMismatch",
  COUNTERPARTY_MISMATCH: "reasonCounterpartyMismatch",
  CONTRACT_NOT_BILLABLE: "codeContractNotBillable"
};
const STATE_LABELS = {
  DRAFT: "stateDraft",
  REVIEWED: "stateReviewed",
  ISSUING: "stateIssuing",
  ISSUED: "stateIssued",
  CANCELLED: "stateCancelled",
  OPEN: "lifecycleOpen",
  CLOSED: "lifecycleClosed"
};

export function stateLabel(state) {
  return labels[STATE_LABELS[state]] || state;
}

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

/**
 * Idempotency key = session key + content fingerprint: replaying the same payload reuses the
 * key (same document), while an edited payload gets a new key instead of a CONFLICT.
 */
export function contentKey(sessionKey, payload) {
  const text = JSON.stringify(payload);
  let hash = 5381;
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) + hash + text.charCodeAt(i)) | 0;
  }
  return `${sessionKey}-${(hash >>> 0).toString(16)}`;
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
  composing = false;
  error;
  issues = [];
  success;
  sessionKey = requestKey();
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
      if (data.length === 0) {
        this.error = labels.noEntities;
      }
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
  get periodValid() {
    const f = this.form;
    return !f.periodStart || !f.periodEnd || f.periodEnd >= f.periodStart;
  }
  get frameComplete() {
    const f = this.form;
    return Boolean(
      f.accountId &&
      f.contractId &&
      f.counterpartyId &&
      f.seriesKey &&
      f.periodStart &&
      f.periodEnd &&
      f.currencyIso &&
      this.periodValid
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
          label: issue.detail
            ? `${reasonLabel(issue.reason)} (${labels.remainingBalance}: ${issue.detail})`
            : reasonLabel(issue.reason)
        }));
      const typeLocked =
        !selected &&
        this.selectedRows.length > 0 &&
        this.selectedRows[0].lineType !== candidate.lineType;
      return {
        ...candidate,
        selected,
        allocationKey: `${candidate.financialTransactionId}-alloc`,
        disabled: !candidate.eligible || this.busy || typeLocked,
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
  get busyLabel() {
    return this.composing ? labels.composing : labels.loading;
  }
  get draftStateText() {
    if (!this.draft) {
      return "";
    }
    return `${stateLabel(this.draft.state)} · ${stateLabel(this.draft.presentationState)}`;
  }
  /** Client-side allocation validation; returns the first problem label or undefined. */
  allocationProblem() {
    for (const row of this.selectedRows) {
      const list = this.allocations[row.financialTransactionId] || [];
      const seen = new Set();
      for (const allocation of list) {
        if (!allocation.workRecordId) {
          continue;
        }
        if (seen.has(allocation.workRecordId)) {
          return labels.duplicateWork;
        }
        seen.add(allocation.workRecordId);
        const quantity = Number(allocation.quantity);
        if (!allocation.quantity || !(quantity > 0)) {
          return labels.quantityRequired;
        }
      }
    }
    const types = new Set(this.selectedRows.map((row) => row.lineType));
    return types.size > 1 ? labels.typeMixed : undefined;
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
    if (contract && (!contract.counterpartyId || !contract.currencyIso)) {
      this.error = labels.contractIncomplete;
    }
  }
  handleField(event) {
    const { name, value } = event.target;
    this.form = { ...this.form, [name]: value };
    this.resetCandidates();
    if (!this.periodValid) {
      this.error = labels.periodInvalid;
    }
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
  buildPayload() {
    return {
      accountId: this.form.accountId,
      contractId: this.form.contractId,
      counterpartyId: this.form.counterpartyId,
      documentKind: this.form.documentKind,
      seriesKey: this.form.seriesKey,
      periodStart: this.form.periodStart,
      periodEnd: this.form.periodEnd,
      currencyIso: this.form.currencyIso,
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
  buildRequest() {
    const payload = this.buildPayload();
    return {
      ...payload,
      clientRequestId: contentKey(this.sessionKey, payload)
    };
  }
  async composeDraft() {
    if (this.selectedCount === 0) {
      this.error = labels.selectionRequired;
      return;
    }
    const problem = this.allocationProblem();
    if (problem) {
      this.error = problem;
      return;
    }
    this.composing = true;
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
      this.composing = false;
    }
  }
  startNew() {
    this.draft = undefined;
    this.sessionKey = requestKey();
    this.resetCandidates();
  }
}
