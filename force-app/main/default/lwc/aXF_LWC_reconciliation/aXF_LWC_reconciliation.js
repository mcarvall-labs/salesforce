import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getHolders";
import getData from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getData";
import reconcile from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.reconcile";
import unreconcile from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.unreconcile";
import ignoreTransactions from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.ignoreTransactions";
import createEntries from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.createEntries";
import {
  entryKind,
  isCompatible,
  matchesEntry,
  matchesTransaction,
  monthOptions
} from "./reconciliationRules";

const KIND_LABELS = { account: "Conta", card: "Cartão", invoice: "Fatura" };

export default class AXF_LWC_reconciliation extends NavigationMixin(
  LightningElement
) {
  holders = [];
  holderId;
  month = monthOptions(new Date())[6].value;
  data = { sources: [], entries: [], transactions: [], suggestions: [] };
  filters = {
    source: "",
    text: "",
    min: "",
    max: "",
    type: "",
    dateFrom: "",
    dateTo: ""
  };
  requestId = 0;
  monthChoices = monthOptions(new Date());
  selectedEntryId;
  selectedTransactionId;
  isLoading = true;
  isWorking = false;
  errorMessage;
  infoMessage;

  async connectedCallback() {
    try {
      this.holders = await getHolders();
      if (this.holders.length) {
        this.holderId = this.holders[0].id;
        await this.load();
        return;
      }
      this.infoMessage = "Nenhum titular com conta ou cartão cadastrado.";
    } catch (error) {
      this.errorMessage = this.messageOf(error);
    }
    this.isLoading = false;
  }

  async load() {
    this.isLoading = true;
    this.errorMessage = undefined;
    const request = ++this.requestId;
    this.selectedEntryId = undefined;
    this.selectedTransactionId = undefined;
    try {
      const data = await getData({
        holderId: this.holderId,
        month: this.month
      });
      if (request === this.requestId) {
        this.data = data;
      }
    } catch (error) {
      if (request === this.requestId) {
        this.errorMessage = this.messageOf(error);
      }
    } finally {
      if (request === this.requestId) {
        this.isLoading = false;
      }
    }
  }

  messageOf(error) {
    return (
      (error && error.body && error.body.message) ||
      "Não foi possível carregar a conciliação."
    );
  }

  get holderOptions() {
    return this.holders.map((holder) => ({
      label: holder.name,
      value: holder.id
    }));
  }

  get monthOptions() {
    return this.monthChoices;
  }

  get sourceOptions() {
    return [
      { label: "Todos", value: "" },
      ...this.data.sources.map((source) => ({
        label: source.name,
        value: `${source.kind}:${source.id}`
      }))
    ];
  }

  get typeOptions() {
    return [
      { label: "Todos", value: "" },
      { label: "Despesa", value: "Expense" },
      { label: "Receita", value: "Income" }
    ];
  }

  // Suggestions whose Entry and transaction are both listed and not hidden by the filters.
  get visibleSuggestions() {
    const entries = new Set(
      this.data.entries
        .filter((entry) => matchesEntry(entry, this.filters))
        .map((entry) => entry.id)
    );
    const transactions = new Set(
      this.data.transactions
        .filter((transaction) => matchesTransaction(transaction, this.filters))
        .map((transaction) => transaction.id)
    );
    return this.data.suggestions.filter(
      (suggestion) =>
        entries.has(suggestion.entryId) &&
        transactions.has(
          suggestion.bankTransactionId || suggestion.cardTransactionId
        )
    );
  }

  get suggestedEntryIds() {
    return new Set(this.visibleSuggestions.map((s) => s.entryId));
  }

  get suggestedTransactionIds() {
    return new Set(
      this.visibleSuggestions.map(
        (s) => s.bankTransactionId || s.cardTransactionId
      )
    );
  }

  get selectedEntry() {
    return this.data.entries.find((entry) => entry.id === this.selectedEntryId);
  }

  get selectedTransaction() {
    return this.data.transactions.find(
      (transaction) => transaction.id === this.selectedTransactionId
    );
  }

  get entryRows() {
    const suggested = this.suggestedEntryIds;
    return this.data.entries
      .filter((entry) => matchesEntry(entry, this.filters))
      .map((entry) => {
        const kind = entryKind(entry);
        return {
          ...entry,
          kindLabel: KIND_LABELS[kind],
          isInvoice: kind === "invoice",
          isSelected: entry.id === this.selectedEntryId,
          signedAmount:
            (entry.type === "Expense" ? -1 : 1) * (entry.amount || 0),
          rowClass: this.rowClass(
            entry.id === this.selectedEntryId,
            suggested.has(entry.id),
            false
          )
        };
      });
  }

  get transactionRows() {
    const suggested = this.suggestedTransactionIds;
    const entry = this.selectedEntry;
    return this.data.transactions
      .filter((transaction) => matchesTransaction(transaction, this.filters))
      .map((transaction) => {
        const blocked = Boolean(entry) && !isCompatible(entry, transaction);
        return {
          ...transaction,
          sourceLabel: KIND_LABELS[transaction.source],
          hasBRL:
            Boolean(transaction.amountBRL) &&
            transaction.currencyCode !== "BRL",
          blocked,
          isSelected: transaction.id === this.selectedTransactionId,
          rowClass: this.rowClass(
            transaction.id === this.selectedTransactionId,
            suggested.has(transaction.id),
            blocked
          )
        };
      });
  }

  rowClass(selected, suggested, blocked) {
    return [
      "reconciliation-row",
      selected ? "slds-theme_shade selected-row" : "",
      suggested && !selected ? "suggested-row" : "",
      blocked ? "blocked-row slds-text-color_weak" : ""
    ]
      .filter(Boolean)
      .join(" ");
  }

  get entryCount() {
    return this.entryRows.length;
  }

  get transactionCount() {
    return this.transactionRows.length;
  }

  get suggestionCount() {
    return this.visibleSuggestions.length;
  }

  get hasSuggestions() {
    return this.suggestionCount > 0;
  }

  get suggestAllLabel() {
    return `Conciliar sugeridos (${this.suggestionCount})`;
  }

  get canReconcile() {
    return (
      !this.isWorking &&
      Boolean(this.selectedEntry) &&
      Boolean(this.selectedTransaction)
    );
  }

  get cannotReconcile() {
    return !this.canReconcile;
  }

  get cannotAct() {
    return this.isWorking || !this.selectedTransaction;
  }

  get cannotUndo() {
    return this.isWorking || !this.data.lastReconciledEntryId;
  }

  get cannotSuggestAll() {
    return this.isWorking || !this.hasSuggestions;
  }

  get hint() {
    if (!this.selectedEntry && !this.selectedTransaction) {
      return "Selecione um lançamento e/ou uma transação.";
    }
    if (this.selectedEntry && !this.selectedTransaction) {
      return "Agora escolha a transação compatível para conciliar.";
    }
    if (!this.selectedEntry) {
      return "Escolha um lançamento para conciliar, ou ignore/crie lançamento a partir da transação.";
    }
    return "Clique em Conciliar para ligar o lançamento à transação.";
  }

  handleHolder(event) {
    this.holderId = event.detail.value;
    this.filters = { ...this.filters, source: "" };
    this.load();
  }

  handleMonth(event) {
    this.month = event.detail.value;
    this.load();
  }

  handleFilter(event) {
    const name = event.target.dataset.filter;
    this.filters = { ...this.filters, [name]: event.detail.value };
    this.clearHiddenSelection();
  }

  // A selection that the new filters hide would otherwise act on something the user cannot see.
  clearHiddenSelection() {
    if (!this.entryRows.some((row) => row.id === this.selectedEntryId)) {
      this.selectedEntryId = undefined;
    }
    if (
      !this.transactionRows.some((row) => row.id === this.selectedTransactionId)
    ) {
      this.selectedTransactionId = undefined;
    }
  }

  handleEntryClick(event) {
    const id = event.currentTarget.dataset.id;
    this.selectedEntryId = id === this.selectedEntryId ? undefined : id;
    const entry = this.selectedEntry;
    const transaction = this.selectedTransaction;
    if (entry && transaction && !isCompatible(entry, transaction)) {
      this.selectedTransactionId = undefined;
    }
  }

  handleTransactionClick(event) {
    const id = event.currentTarget.dataset.id;
    const transaction = this.data.transactions.find((item) => item.id === id);
    const entry = this.selectedEntry;
    if (!transaction || (entry && !isCompatible(entry, transaction))) {
      return;
    }
    this.selectedTransactionId =
      id === this.selectedTransactionId ? undefined : id;
  }

  // Rows are keyboard operable: Enter or Space selects like a click.
  handleRowKey(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      event.currentTarget.click();
    }
  }

  handleOpenEntry(event) {
    event.preventDefault();
    event.stopPropagation();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }

  pairOf(entryId, transaction) {
    return {
      entryId,
      bankTransactionId:
        transaction.source === "account" ? transaction.id : null,
      cardTransactionId: transaction.source === "card" ? transaction.id : null
    };
  }

  handleReconcile() {
    return this.run(
      () =>
        reconcile({
          pairs: [this.pairOf(this.selectedEntryId, this.selectedTransaction)]
        }),
      "Conciliado."
    );
  }

  handleReconcileSuggested() {
    return this.run(
      () =>
        reconcile({
          pairs: this.visibleSuggestions.map((suggestion) => ({
            entryId: suggestion.entryId,
            bankTransactionId: suggestion.bankTransactionId,
            cardTransactionId: suggestion.cardTransactionId
          }))
        }),
      "Sugestões conciliadas."
    );
  }

  handleIgnore() {
    const transaction = this.selectedTransaction;
    return this.run(
      () =>
        ignoreTransactions({
          bankIds: transaction.source === "account" ? [transaction.id] : [],
          cardIds: transaction.source === "card" ? [transaction.id] : []
        }),
      "Transação ignorada."
    );
  }

  handleCreateEntry() {
    const transaction = this.selectedTransaction;
    return this.run(
      () =>
        createEntries({
          bankIds: transaction.source === "account" ? [transaction.id] : [],
          cardIds: transaction.source === "card" ? [transaction.id] : []
        }),
      "Lançamento criado e conciliado."
    );
  }

  handleUndo() {
    return this.run(
      () => unreconcile({ entryIds: [this.data.lastReconciledEntryId] }),
      "Conciliação desfeita."
    );
  }

  async run(action, successMessage) {
    this.isWorking = true;
    this.infoMessage = undefined;
    try {
      const outcomes = (await action()) || [];
      const failed = outcomes.filter((outcome) => !outcome.success);
      const done = outcomes.length - failed.length;
      this.toast(done, failed, successMessage);
      await this.load();
    } catch (error) {
      this.toast(0, [{ message: this.messageOf(error) }], successMessage);
    } finally {
      this.isWorking = false;
    }
  }

  toast(done, failed, successMessage) {
    if (done > 0) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: successMessage,
          message: done > 1 ? `${done} itens.` : undefined,
          variant: "success"
        })
      );
    }
    if (failed.length) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: `${failed.length} não ${failed.length > 1 ? "foram concluídos" : "foi concluído"}`,
          message: failed[0].message,
          variant: "error"
        })
      );
    }
  }
}
