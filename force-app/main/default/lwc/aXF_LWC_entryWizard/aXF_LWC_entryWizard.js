import { LightningElement, wire, track } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
import getContexts from "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts";
import getFundingSources from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getFundingSources";
import getCapabilities from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getCapabilities";
import createEntry from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.createEntry";
import realizeEntry from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.realizeEntry";
import listFactSuggestions from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.listFactSuggestions";
import searchFacts from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.searchFacts";
import confirmFact from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.confirmFact";
import L from "./labels";
import { parseFailure, format } from "./failures";

const STEP = { CONTEXT: 0, DETAILS: 1, SOURCE: 2, REVIEW: 3 };
const STAGE = { FORM: "FORM", CONFIRMING: "CONFIRMING", DONE: "DONE" };
const TYPE = {
  SINGLE: "SINGLE",
  INSTALLMENT: "INSTALLMENT",
  RECURRING: "RECURRING"
};
const KIND = {
  BANK: "BANK_ACCOUNT",
  CARD: "CREDIT_CARD",
  WALLET: "WALLET"
};
const MAX_PERIOD_DAYS = 366;

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

function parseIsoDate(value) {
  if (!value) {
    return null;
  }
  const [y, m, d] = String(value).split("-").map(Number);
  return new Date(y, m - 1, d);
}

function emptyForm(accountId) {
  return {
    accountId: accountId || null,
    direction: "DEBIT",
    entryType: TYPE.SINGLE,
    realized: false,
    magnitude: null,
    currencyIsoCode: "BRL",
    purchaseDate: todayIso(),
    dueDate: null,
    sourceKind: null,
    bankAccountId: null,
    creditCardId: null,
    trackConfirmation: false
  };
}

function emptyFacts() {
  return {
    loading: false,
    suggestions: null,
    suggestionsTruncated: false,
    results: null,
    resultsTruncated: false,
    searching: false,
    targetId: null,
    targetVersion: null,
    available: null
  };
}

export default class AxfLwcEntryWizard extends NavigationMixin(
  LightningElement
) {
  labels = L;
  stepIndex = STEP.CONTEXT;
  stage = STAGE.FORM;

  contexts = [];
  contextsLoaded = false;
  fundingSources = [];
  capabilities = { canReconcile: false, canRealize: false };

  @track form = emptyForm();

  clientRequestId = uuidv4();
  feedback;
  lastResult;
  // AXF-153: Pluggy facts offered for the entry (select before saving / reconcile after saving).
  facts = emptyFacts();
  selectedFact;
  search = { fromDate: null, toDate: null, term: "" };
  factMessage;
  busyFactId;
  reconciled = false;
  factSeq = 0;
  // AXF-151: account handed over by the current-account screen (state.c__bankAccountId).
  // AXF-152: card handed over by the credit-card screen (state.c__creditCardId).
  preselectBankAccountId;
  preselectCreditCardId;
  preselectAccountId;
  preselectDone = false;
  preselectDirection;

  @wire(CurrentPageReference)
  wiredPageReference(pageRef) {
    const state = (pageRef && pageRef.state) || {};
    // Home dashboard: "Nova Despesa" / "Nova Receita" open the wizard with the nature (and the
    // filtered holder) chosen; applied once per hand-over so the user can still change them.
    const direction = ["DEBIT", "CREDIT"].includes(state.c__direction)
      ? state.c__direction
      : null;
    if (direction && direction !== this.preselectDirection) {
      this.preselectDirection = direction;
      this.form = {
        ...this.form,
        direction,
        accountId: state.c__accountId || this.form.accountId
      };
    }
    const creditCardId = state.c__creditCardId || null;
    const bankAccountId = creditCardId ? null : state.c__bankAccountId || null;
    if (
      (bankAccountId && bankAccountId !== this.preselectBankAccountId) ||
      (creditCardId && creditCardId !== this.preselectCreditCardId)
    ) {
      this.preselectBankAccountId = bankAccountId;
      this.preselectCreditCardId = creditCardId;
      this.preselectAccountId = state.c__accountId || null;
      this.preselectDone = false;
      this.applyPreselection();
    }
  }

  @wire(getContexts)
  wiredContexts({ data, error }) {
    if (data) {
      this.contexts = data;
      this.contextsLoaded = true;
      if (data.length === 1 && !this.form.accountId) {
        this.form = { ...this.form, accountId: data[0].accountId };
      }
      this.applyPreselection();
    } else if (error) {
      this.contexts = [];
      this.contextsLoaded = true;
    }
  }

  @wire(getFundingSources, { accountId: "$form.accountId" })
  wiredSources({ data }) {
    this.fundingSources = data || [];
    this.applyPreselection();
  }

  @wire(getCapabilities)
  wiredCapabilities({ data }) {
    if (data) {
      this.capabilities = data;
    }
  }

  /**
   * Pre-selects the handed-over account or card as the entry's origin, once, and only when it is
   * one of the holder's own available sources; an unknown or foreign id is silently ignored.
   */
  applyPreselection() {
    if (
      (!this.preselectBankAccountId && !this.preselectCreditCardId) ||
      this.preselectDone
    ) {
      return;
    }
    if (
      this.preselectAccountId &&
      this.form.accountId !== this.preselectAccountId &&
      this.contexts.some((c) => c.accountId === this.preselectAccountId)
    ) {
      // A reused (console) tab may still show another holder: follow the handed-over one.
      this.form = {
        ...this.form,
        accountId: this.preselectAccountId,
        sourceKind: null,
        bankAccountId: null,
        creditCardId: null
      };
      this.fundingSources = [];
      return; // the funding sources of this holder are loaded next
    }
    if (this.preselectCreditCardId) {
      const card = this.fundingSources.find(
        (s) =>
          s.kind === "CREDIT_CARD" &&
          s.creditCardId === this.preselectCreditCardId
      );
      if (card) {
        this.preselectDone = true;
        this.form = {
          ...this.form,
          sourceKind: KIND.CARD,
          bankAccountId: null,
          creditCardId: card.creditCardId
        };
      }
      return;
    }
    const match = this.fundingSources.find(
      (s) =>
        s.kind === "BANK_ACCOUNT" &&
        s.bankAccountId === this.preselectBankAccountId
    );
    if (match) {
      this.preselectDone = true;
      this.form = {
        ...this.form,
        sourceKind: match.wallet ? KIND.WALLET : KIND.BANK,
        bankAccountId: match.bankAccountId,
        creditCardId: null
      };
    }
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
  get typeOptions() {
    return [
      { label: L.typeSingle, value: TYPE.SINGLE },
      { label: L.typeInstallment, value: TYPE.INSTALLMENT },
      { label: L.typeRecurring, value: TYPE.RECURRING }
    ].map((o) => ({
      ...o,
      id: `entry-type-${o.value}`,
      checked: this.form.entryType === o.value
    }));
  }
  get isSingle() {
    return this.form.entryType === TYPE.SINGLE;
  }
  get isScheduled() {
    return !this.isSingle;
  }
  get isRecurring() {
    return this.form.entryType === TYPE.RECURRING;
  }
  get scheduleRedirectText() {
    return this.isRecurring ? L.recurringRedirect : L.scheduleRedirect;
  }
  get continueScheduleLabel() {
    return this.isRecurring ? L.continueRecurring : L.continueSchedule;
  }
  get showRealizedToggle() {
    return this.isSingle && this.capabilities.canRealize === true;
  }
  get isRealized() {
    return this.isSingle && this.form.realized === true;
  }
  get showDueDate() {
    return !this.isRealized;
  }
  get sourceKindOptions() {
    return [
      { label: L.sourceCurrentAccount, value: KIND.BANK },
      { label: L.sourceCard, value: KIND.CARD },
      { label: L.sourceWallet, value: KIND.WALLET }
    ];
  }
  get isSourceBank() {
    return this.form.sourceKind === KIND.BANK;
  }
  get isSourceCard() {
    return this.form.sourceKind === KIND.CARD;
  }
  get isSourceWallet() {
    return this.form.sourceKind === KIND.WALLET;
  }
  get hasSourceKind() {
    return Boolean(this.form.sourceKind);
  }
  get showOriginRequired() {
    return this.isSingle && !this.hasSourceKind;
  }
  optionOf(source) {
    return {
      label: source.connected
        ? `${source.label} (${L.connectedHint})`
        : source.label,
      value:
        source.kind === "CREDIT_CARD"
          ? source.creditCardId
          : source.bankAccountId
    };
  }
  get sourceOptions() {
    const kind = this.form.sourceKind;
    return this.fundingSources
      .filter((s) => {
        if (kind === KIND.CARD) {
          return s.kind === "CREDIT_CARD";
        }
        return (
          s.kind === "BANK_ACCOUNT" &&
          Boolean(s.wallet) === (kind === KIND.WALLET)
        );
      })
      .map((s) => this.optionOf(s));
  }
  get sourceOptionLabel() {
    if (this.isSourceCard) return L.cardOptionLabel;
    if (this.isSourceWallet) return L.walletOptionLabel;
    return L.accountOptionLabel;
  }
  get sourceValue() {
    return this.isSourceCard ? this.form.creditCardId : this.form.bankAccountId;
  }
  get hasNoSources() {
    return this.hasSourceKind && this.sourceOptions.length === 0;
  }
  get selectedSource() {
    if (this.isSourceCard) {
      return this.fundingSources.find(
        (s) =>
          s.kind === "CREDIT_CARD" && s.creditCardId === this.form.creditCardId
      );
    }
    if (!this.hasSourceKind) {
      return undefined;
    }
    return this.fundingSources.find(
      (s) =>
        s.kind === "BANK_ACCOUNT" && s.bankAccountId === this.form.bankAccountId
    );
  }
  get isConnected() {
    const source = this.selectedSource;
    return Boolean(source && source.connected);
  }
  get natureText() {
    return this.form.direction === "CREDIT" ? L.natureIncome : L.natureExpense;
  }
  get typeText() {
    return {
      [TYPE.SINGLE]: L.typeSingle,
      [TYPE.INSTALLMENT]: L.typeInstallment,
      [TYPE.RECURRING]: L.typeRecurring
    }[this.form.entryType];
  }
  get situationText() {
    return this.isRealized ? L.situationRealized : L.situationPlanned;
  }
  get sourceText() {
    const source = this.selectedSource;
    return source ? source.label : "";
  }

  // ---- facts (AXF-153) ----
  /** Realized on a Pluggy-connected origin: saving waits for an explicit fact choice. */
  get needsFact() {
    return this.isRealized && this.isConnected;
  }
  get cannotReconcile() {
    return this.needsFact && this.capabilities.canReconcile !== true;
  }
  get showFactPicker() {
    return (
      this.isForm &&
      this.onReview &&
      this.needsFact &&
      this.capabilities.canReconcile === true
    );
  }
  get showReconcilePanel() {
    return (
      this.isDone &&
      Boolean(this.facts.targetId) &&
      !this.reconciled &&
      this.capabilities.canReconcile === true
    );
  }
  get showFactPanel() {
    return this.showFactPicker || this.showReconcilePanel;
  }
  get factPanelTitle() {
    return this.showReconcilePanel ? L.reconcileNowTitle : L.factPanelTitle;
  }
  get showFactRequired() {
    return this.showFactPicker && !this.selectedFact;
  }
  get confirmDisabled() {
    return (
      this.isScheduled ||
      this.cannotReconcile ||
      (this.needsFact && !this.selectedFact)
    );
  }
  factRows(items) {
    const selecting = this.showFactPicker;
    return (items || []).map((f) => {
      const text = format(
        L.factText,
        f.description || "",
        this.formatMoney(f.amount, f.currencyIso),
        this.formatDate(f.factDate)
      );
      const selected = Boolean(
        this.selectedFact && this.selectedFact.sourceId === f.sourceId
      );
      return {
        ...f,
        key: f.sourceId,
        text,
        tied: Boolean(f.tied),
        actionLabel: selecting
          ? selected
            ? L.selected
            : L.select
          : L.reconcileAction,
        actionTitle: format(selecting ? L.selectFor : L.reconcileFor, text),
        variant: selected ? "brand" : "neutral",
        ariaPressed: selecting ? String(selected) : undefined,
        busy: this.busyFactId === f.sourceId
      };
    });
  }
  get suggestionRows() {
    return this.factRows(this.facts.suggestions);
  }
  get resultRows() {
    return this.factRows(this.facts.results);
  }
  get noSuggestions() {
    return (
      !this.facts.loading &&
      Array.isArray(this.facts.suggestions) &&
      this.facts.suggestions.length === 0
    );
  }
  get noResults() {
    return (
      !this.facts.searching &&
      Array.isArray(this.facts.results) &&
      this.facts.results.length === 0
    );
  }

  formatDate(value) {
    const date = parseIsoDate(value);
    return date ? new Intl.DateTimeFormat(LOCALE).format(date) : "";
  }

  formatMoney(value, iso) {
    if (value === null || value === undefined) {
      return "";
    }
    try {
      return new Intl.NumberFormat(LOCALE, {
        style: "currency",
        currency: iso || "BRL"
      }).format(value);
    } catch {
      return String(value);
    }
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
      // AXF-153: a one-off entry needs its origin — a current account, a card or a wallet;
      // installments and recurrences are handed to the schedule planner, which does not take one.
      return this.isScheduled || Boolean(this.selectedSource);
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
    if (field === "accountId") {
      // A manual holder choice ends any pending hand-over: it never takes the source later.
      this.preselectDone = true;
      this.form = {
        ...this.form,
        sourceKind: null,
        bankAccountId: null,
        creditCardId: null
      };
    }
    const value = event.detail ? event.detail.value : event.target.value;
    this.form = { ...this.form, [field]: value };
    this.clearFacts();
  }
  handleType(event) {
    const value = event.target.value;
    this.form = {
      ...this.form,
      entryType: value,
      realized: value === TYPE.SINGLE ? this.form.realized : false
    };
    this.clearFacts();
  }
  handleRealized(event) {
    this.form = {
      ...this.form,
      realized: event.target.checked,
      trackConfirmation: false
    };
    this.clearFacts();
  }
  handleTracking(event) {
    this.form = { ...this.form, trackConfirmation: event.target.checked };
  }
  handleSourceKind(event) {
    this.form = {
      ...this.form,
      sourceKind: event.detail.value,
      bankAccountId: null,
      creditCardId: null,
      trackConfirmation: false
    };
    this.clearFacts();
  }
  handleSource(event) {
    const value = event.detail.value;
    this.form = this.isSourceCard
      ? { ...this.form, creditCardId: value, bankAccountId: null }
      : { ...this.form, bankAccountId: value, creditCardId: null };
    this.clearFacts();
  }
  handleBack() {
    if (this.stepIndex > STEP.CONTEXT) {
      this.stepIndex -= 1;
      this.moveFocus("[data-step-heading]");
    }
  }
  handleNext() {
    if (this.stepIndex < STEP.REVIEW && this.canAdvance) {
      this.stepIndex += 1;
      this.moveFocus("[data-step-heading]");
      if (
        this.stepIndex === STEP.REVIEW &&
        this.needsFact &&
        this.capabilities.canReconcile === true
      ) {
        this.loadSuggestions();
      }
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

  /**
   * Installments are planned by the schedule planner (AXF-153); recurring entries with no end
   * are managed on the Recurring screen (AXF-155). Both open pre-filled.
   */
  handleContinueSchedule() {
    if (this.isRecurring) {
      this.navigateToRecurrences();
      return;
    }
    // AXF-156: origin and description travel too; the planner applies them to the installments.
    const card = this.isSourceCard;
    const state = {
      c__modality: this.form.entryType,
      c__direction: this.form.direction,
      c__accountId: this.form.accountId,
      c__amount: String(this.form.magnitude),
      c__firstDueDate: this.form.dueDate || this.form.purchaseDate,
      c__currencyIsoCode: this.form.currencyIsoCode,
      c__description: this.form.description || null,
      c__bankAccountId: card ? null : this.form.bankAccountId,
      c__creditCardId: card ? this.form.creditCardId : null
    };
    Object.keys(state).forEach((key) => {
      if (state[key] === null || state[key] === undefined) {
        delete state[key];
      }
    });
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_ScheduleWizard" },
      state
    });
  }

  navigateToRecurrences() {
    const card = this.isSourceCard;
    const firstDueDate = this.form.dueDate || this.form.purchaseDate;
    const state = {
      c__direction: this.form.direction,
      c__accountId: this.form.accountId,
      c__amount: String(this.form.magnitude),
      // A recurrence never backfills: a past date is not handed over.
      c__firstDueDate:
        firstDueDate && firstDueDate >= todayIso() ? firstDueDate : null,
      c__currencyIsoCode: this.form.currencyIsoCode,
      c__description: this.form.description || null,
      c__bankAccountId: card ? null : this.form.bankAccountId,
      c__creditCardId: card ? this.form.creditCardId : null
    };
    Object.keys(state).forEach((key) => {
      if (state[key] === null || state[key] === undefined) {
        delete state[key];
      }
    });
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_CT_Recurrences" },
      state
    });
  }

  draft() {
    const card = this.isSourceCard;
    return {
      accountId: this.form.accountId,
      bankAccountId: card ? null : this.form.bankAccountId,
      creditCardId: card ? this.form.creditCardId : null,
      direction: this.form.direction,
      amount: Number(this.form.magnitude),
      currencyIsoCode: this.form.currencyIsoCode,
      entryDate: this.form.purchaseDate
    };
  }

  /** The entry the facts are looked up for: the saved one after saving, the draft before. */
  factEntry() {
    return this.facts.targetId
      ? { targetId: this.facts.targetId }
      : this.draft();
  }

  clearFacts() {
    this.factSeq += 1;
    this.facts = emptyFacts();
    this.selectedFact = undefined;
    this.factMessage = undefined;
  }

  async loadSuggestions() {
    const seq = ++this.factSeq;
    this.facts = { ...this.facts, loading: true, suggestions: null };
    try {
      const page = await listFactSuggestions({
        request: JSON.stringify(this.factEntry())
      });
      if (seq !== this.factSeq) {
        return;
      }
      this.facts = {
        ...this.facts,
        loading: false,
        suggestions: page.items || [],
        suggestionsTruncated: Boolean(page.truncated),
        targetVersion: page.targetVersion,
        available: page.available
      };
    } catch (e) {
      if (seq === this.factSeq) {
        this.facts = { ...this.facts, loading: false, suggestions: [] };
        this.factMessage = parseFailure(e);
      }
    }
  }

  handleSearchField(event) {
    this.search = {
      ...this.search,
      [event.target.dataset.field]: event.detail.value
    };
  }

  searchError() {
    const { fromDate, toDate } = this.search;
    if (!fromDate && !toDate) {
      return "";
    }
    if (!fromDate || !toDate) {
      return L.periodInvalid;
    }
    const days = Math.round(
      (parseIsoDate(toDate) - parseIsoDate(fromDate)) / 86400000
    );
    return days < 0 || days >= MAX_PERIOD_DAYS ? L.periodInvalid : "";
  }

  async handleSearch() {
    const toInput = this.template.querySelector(
      "lightning-input[data-field='toDate']"
    );
    const message = this.searchError();
    if (toInput) {
      toInput.setCustomValidity(message);
      toInput.reportValidity();
    }
    if (message) {
      return;
    }
    const seq = this.factSeq;
    this.facts = { ...this.facts, searching: true };
    try {
      const page = await searchFacts({
        request: JSON.stringify({
          entry: this.factEntry(),
          fromDate: this.search.fromDate || null,
          toDate: this.search.toDate || null,
          term: this.search.term ? this.search.term : null
        })
      });
      if (seq !== this.factSeq) {
        // A newer lookup replaced this one: only its spinner is cleared.
        this.facts = { ...this.facts, searching: false };
        return;
      }
      this.facts = {
        ...this.facts,
        searching: false,
        results: page.items || [],
        resultsTruncated: Boolean(page.truncated),
        targetVersion:
          page.targetVersion === undefined
            ? this.facts.targetVersion
            : page.targetVersion
      };
    } catch (e) {
      if (seq === this.factSeq) {
        this.facts = { ...this.facts, searching: false, results: [] };
        this.factMessage = parseFailure(e);
      } else {
        this.facts = { ...this.facts, searching: false };
      }
    }
  }

  findFact(sourceId) {
    return [
      ...(this.facts.suggestions || []),
      ...(this.facts.results || [])
    ].find((f) => f.sourceId === sourceId);
  }

  /** Before saving: choose the fact; after saving: one explicit click reconciles it. */
  async handleFactAction(event) {
    const fact = this.findFact(event.currentTarget.dataset.id);
    if (!fact) {
      return;
    }
    if (this.showFactPicker) {
      this.selectedFact = fact;
      this.factMessage = undefined;
      return;
    }
    if (this.busyFactId) {
      return;
    }
    this.busyFactId = fact.sourceId;
    try {
      const result = await confirmFact({
        request: JSON.stringify({
          targetId: this.facts.targetId,
          targetVersion: this.facts.targetVersion,
          sourceId: fact.sourceId,
          sourceVersion: fact.sourceVersion,
          operationKey: uuidv4()
        })
      });
      this.factMessage = undefined;
      const available = this.facts.available;
      if (
        typeof available === "number" &&
        result &&
        typeof result.amount === "number" &&
        result.amount < available
      ) {
        // Only part of the entry was settled: it stays open for another fact.
        this.feedback = L.partiallyReconciled;
        this.facts = { ...this.facts, results: null };
        this.loadSuggestions();
      } else {
        this.reconciled = true;
        this.feedback = L.reconciled;
      }
      this.moveFocus("[data-feedback]");
    } catch (e) {
      this.factMessage = parseFailure(e);
      // The entry may have changed: offer the current suggestions again.
      this.loadSuggestions();
    } finally {
      this.busyFactId = undefined;
    }
  }

  async handleConfirm() {
    if (this.confirmDisabled) {
      return;
    }
    if (this.isRealized) {
      await this.confirmRealized();
      return;
    }
    this.stage = STAGE.CONFIRMING;
    this.feedback = undefined;
    try {
      const result = await createEntry({
        accountId: this.form.accountId,
        direction: this.form.direction,
        magnitude: Number(this.form.magnitude),
        currencyIsoCode: this.form.currencyIsoCode,
        purchaseDate: this.form.purchaseDate,
        dueDate: this.form.dueDate || null,
        bankAccountId: this.isSourceCard ? null : this.form.bankAccountId,
        creditCardId: this.isSourceCard ? this.form.creditCardId : null,
        trackConfirmation: this.form.trackConfirmation,
        clientRequestId: this.clientRequestId
      });
      this.applyResult(result);
    } catch (e) {
      this.stage = STAGE.FORM;
      this.feedback = (e && e.body && e.body.message) || L.invalid;
      this.moveFocus("[data-feedback]");
    }
  }

  async confirmRealized() {
    this.stage = STAGE.CONFIRMING;
    this.feedback = undefined;
    try {
      const result = await realizeEntry({
        request: JSON.stringify({
          entry: this.draft(),
          factId: this.selectedFact ? this.selectedFact.sourceId : null,
          factVersion: this.selectedFact
            ? this.selectedFact.sourceVersion
            : null,
          operationKey: this.clientRequestId
        })
      });
      this.lastResult = result;
      this.stage = STAGE.DONE;
      this.feedback = result.linkedToFact
        ? L.realizedLinkedDone
        : L.realizedDone;
      this.moveFocus("[data-feedback]");
    } catch (e) {
      this.stage = STAGE.FORM;
      this.feedback = parseFailure(e);
      this.moveFocus("[data-feedback]");
    }
  }

  applyResult(result) {
    this.lastResult = result;
    if (result.outcome === "CREATED" || result.outcome === "ALREADY") {
      this.stage = STAGE.DONE;
      this.feedback = result.outcome === "CREATED" ? L.done : L.alreadyDone;
      this.moveFocus("[data-feedback]");
      if (
        this.isConnected &&
        this.capabilities.canReconcile === true &&
        result.financialTransactionId
      ) {
        // A planned entry on a connected origin is offered its Pluggy facts right away.
        this.facts = {
          ...emptyFacts(),
          targetId: result.financialTransactionId
        };
        this.loadSuggestions();
      }
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
    this.reconciled = false;
    this.clientRequestId = uuidv4();
    this.search = { fromDate: null, toDate: null, term: "" };
    this.clearFacts();
    this.form = emptyForm(
      this.contexts.length === 1 ? this.contexts[0].accountId : null
    );
  }
}
