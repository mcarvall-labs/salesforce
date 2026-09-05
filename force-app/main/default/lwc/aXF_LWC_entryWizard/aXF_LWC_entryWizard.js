import { LightningElement, wire, track } from "lwc";
import getContexts from "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts";
import getFundingSources from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getFundingSources";
import createEntry from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.createEntry";
import L from "./labels";

const STEP = { CONTEXT: 0, DETAILS: 1, SOURCE: 2, REVIEW: 3 };
const STAGE = { FORM: "FORM", CONFIRMING: "CONFIRMING", DONE: "DONE" };

function uuidv4() {
  // RFC4122 v4 — Math.random is fine here, this is a client dedup token, not a secret.
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function todayIso() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export default class AxfLwcEntryWizard extends LightningElement {
  labels = L;
  stepIndex = STEP.CONTEXT;
  stage = STAGE.FORM;

  contexts = [];
  contextsLoaded = false;
  fundingSources = [];

  @track form = {
    accountId: null,
    direction: "DEBIT",
    magnitude: null,
    currencyIsoCode: "BRL",
    purchaseDate: todayIso(),
    dueDate: null,
    sourceKind: "CASH",
    bankAccountId: null,
    creditCardId: null
  };

  clientRequestId = uuidv4();
  feedback;
  lastResult;

  @wire(getContexts)
  wiredContexts({ data, error }) {
    if (data) {
      this.contexts = data;
      this.contextsLoaded = true;
      if (data.length === 1 && !this.form.accountId) {
        this.form = { ...this.form, accountId: data[0].accountId };
      }
    } else if (error) {
      this.contexts = [];
      this.contextsLoaded = true;
    }
  }

  @wire(getFundingSources, { accountId: "$form.accountId" })
  wiredSources({ data }) {
    this.fundingSources = data || [];
  }

  // ---- labels/getters ----
  get isForm() {
    return this.stage === STAGE.FORM;
  }
  get isConfirming() {
    return this.stage === STAGE.CONFIRMING;
  }
  get isDone() {
    return this.stage === STAGE.DONE;
  }
  get onContext() {
    return this.stepIndex === STEP.CONTEXT;
  }
  get onDetails() {
    return this.stepIndex === STEP.DETAILS;
  }
  get onSource() {
    return this.stepIndex === STEP.SOURCE;
  }
  get onReview() {
    return this.stepIndex === STEP.REVIEW;
  }
  get isFirstStep() {
    return this.stepIndex === STEP.CONTEXT;
  }
  get stepTitle() {
    return [L.stepContext, L.stepDetails, L.stepSource, L.stepReview][
      this.stepIndex
    ];
  }
  get stepOfLabel() {
    return String(L.stepOf)
      .replace("{0}", this.stepIndex + 1)
      .replace("{1}", "4");
  }
  get hasNoContext() {
    return this.contextsLoaded && this.contexts.length === 0;
  }
  get contextOptions() {
    return this.contexts.map((c) => ({ label: c.label, value: c.accountId }));
  }
  get natureOptions() {
    return [
      { label: L.natureExpense, value: "DEBIT" },
      { label: L.natureIncome, value: "CREDIT" }
    ];
  }
  get sourceKindOptions() {
    return [
      { label: L.sourceCash, value: "CASH" },
      { label: L.sourceBank, value: "BANK_ACCOUNT" },
      { label: L.sourceCard, value: "CREDIT_CARD" }
    ];
  }
  get isSourceCash() {
    return this.form.sourceKind === "CASH";
  }
  get isSourceBank() {
    return this.form.sourceKind === "BANK_ACCOUNT";
  }
  get isSourceCard() {
    return this.form.sourceKind === "CREDIT_CARD";
  }
  get bankAccountOptions() {
    return this.fundingSources
      .filter((s) => s.kind === "BANK_ACCOUNT")
      .map((s) => ({ label: s.label, value: s.bankAccountId }));
  }
  get creditCardOptions() {
    return this.fundingSources
      .filter((s) => s.kind === "CREDIT_CARD")
      .map((s) => ({ label: s.label, value: s.creditCardId }));
  }
  get hasNoSources() {
    return (
      (this.isSourceBank && this.bankAccountOptions.length === 0) ||
      (this.isSourceCard && this.creditCardOptions.length === 0)
    );
  }
  get natureText() {
    return this.form.direction === "CREDIT" ? L.natureIncome : L.natureExpense;
  }
  get sourceText() {
    if (this.isSourceCash) return L.sourceCash;
    const opts = this.isSourceBank
      ? this.bankAccountOptions
      : this.creditCardOptions;
    const id = this.isSourceBank
      ? this.form.bankAccountId
      : this.form.creditCardId;
    const found = opts.find((o) => o.value === id);
    return found ? found.label : "";
  }

  get canAdvance() {
    if (this.stepIndex === STEP.CONTEXT) {
      return Boolean(this.form.accountId);
    }
    if (this.stepIndex === STEP.DETAILS) {
      return (
        Boolean(this.form.direction) &&
        Number(this.form.magnitude) > 0 &&
        String(this.form.currencyIsoCode || "").trim().length === 3 &&
        Boolean(this.form.purchaseDate)
      );
    }
    if (this.stepIndex === STEP.SOURCE) {
      if (this.isSourceBank) return Boolean(this.form.bankAccountId);
      if (this.isSourceCard) return Boolean(this.form.creditCardId);
      return true;
    }
    return true;
  }
  get canAdvanceDisabled() {
    return !this.canAdvance;
  }

  moveFocus(selector) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const el = this.template.querySelector(selector);
      if (el) el.focus();
    });
  }

  // ---- handlers ----
  handleField(event) {
    const field = event.target.dataset.field;
    const value = event.detail ? event.detail.value : event.target.value;
    this.form = { ...this.form, [field]: value };
  }
  handleSourceKind(event) {
    this.form = {
      ...this.form,
      sourceKind: event.detail.value,
      bankAccountId: null,
      creditCardId: null
    };
  }
  handleBack() {
    if (this.stepIndex > STEP.CONTEXT) {
      this.stepIndex -= 1;
      this.moveFocus("[data-step-heading]");
    }
  }
  handleNext() {
    if (this.stepIndex < STEP.REVIEW) {
      this.stepIndex += 1;
      this.moveFocus("[data-step-heading]");
    }
  }
  handleCancel() {
    this.reset();
    this.moveFocus("[data-step-heading]");
  }
  handleNewEntry() {
    this.reset();
    this.moveFocus("[data-step-heading]");
  }

  async handleConfirm() {
    this.stage = STAGE.CONFIRMING;
    this.feedback = undefined;
    try {
      const result = await createEntry({
        input: {
          accountId: this.form.accountId,
          direction: this.form.direction,
          magnitude: Number(this.form.magnitude),
          currencyIsoCode: this.form.currencyIsoCode,
          purchaseDate: this.form.purchaseDate,
          dueDate: this.form.dueDate || null,
          bankAccountId: this.isSourceBank ? this.form.bankAccountId : null,
          creditCardId: this.isSourceCard ? this.form.creditCardId : null,
          clientRequestId: this.clientRequestId
        }
      });
      this.applyResult(result);
    } catch (e) {
      this.stage = STAGE.FORM;
      this.feedback = (e && e.body && e.body.message) || L.invalid;
      this.moveFocus("[data-feedback]");
    }
  }

  applyResult(result) {
    this.lastResult = result;
    if (result.outcome === "CREATED" || result.outcome === "ALREADY") {
      this.stage = STAGE.DONE;
      this.feedback = result.outcome === "CREATED" ? L.done : L.alreadyDone;
      this.moveFocus("[data-feedback]");
      return;
    }
    this.stage = STAGE.FORM;
    if (result.outcome === "CONFLICT") {
      this.feedback = L.conflict;
    } else if (result.outcome === "FORBIDDEN") {
      this.feedback = L.forbidden;
    } else {
      this.feedback = result.message || L.invalid;
    }
    this.moveFocus("[data-feedback]");
  }

  reset() {
    this.stage = STAGE.FORM;
    this.stepIndex = STEP.CONTEXT;
    this.feedback = undefined;
    this.lastResult = undefined;
    this.clientRequestId = uuidv4();
    this.form = {
      accountId: this.contexts.length === 1 ? this.contexts[0].accountId : null,
      direction: "DEBIT",
      magnitude: null,
      currencyIsoCode: "BRL",
      purchaseDate: todayIso(),
      dueDate: null,
      sourceKind: "CASH",
      bankAccountId: null,
      creditCardId: null
    };
  }
}
