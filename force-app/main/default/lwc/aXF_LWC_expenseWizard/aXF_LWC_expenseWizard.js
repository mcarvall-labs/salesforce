import { LightningElement, api } from "lwc";
import getOptions from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.getOptions";
import createStandalone from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createStandalone";
import createCategory from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createCategory";
import createRecurring from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createRecurring";
import previewRecurring from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewRecurring";
import createInstallment from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createInstallment";
import previewInstallment from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewInstallment";
import createConsortium from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createConsortium";
import previewConsortium from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewConsortium";

const STEP_TITLES = ["Dados", "Pagamento", "Revisar"];
const TYPES = [
  {
    value: "standalone",
    label: "Despesa avulsa",
    description: "Paga uma vez, à vista ou prevista para uma data.",
    enabled: true
  },
  {
    value: "recurring",
    label: "Recorrente",
    description: "Se repete todo mês: aluguel, assinatura, conta de água.",
    enabled: true
  },
  {
    value: "installments",
    label: "Parcelada",
    description: "Compra dividida em parcelas fixas, sem juros. Inclui cartão.",
    enabled: true
  },
  {
    value: "consortium",
    label: "Consórcio",
    description: "Parcela fixa mensal; pode ser contemplado depois.",
    enabled: true
  },
  {
    value: "financing",
    label: "Financiamento",
    description: "Valor financiado com juros: SAC ou PRICE.",
    enabled: false
  }
];
const STATUS_OPTIONS = [
  { label: "Pendente", value: "Pending" },
  { label: "Realizado", value: "Realized" }
];
const VARIABLE_OPTIONS = [
  { label: "Não", value: "no" },
  { label: "Sim (corrijo antes de realizar)", value: "yes" }
];
const AMOUNT_KIND_OPTIONS = [
  { label: "Valor total", value: "total" },
  { label: "Valor da parcela", value: "installment" }
];
const PREVIEW_ROWS = 2;
const METHOD_OPTIONS = [
  { label: "Dinheiro", value: "cash" },
  { label: "Conta bancária", value: "account" },
  { label: "Cartão de crédito", value: "card" }
];

export default class AXF_LWC_expenseWizard extends LightningElement {
  // Holder of the dashboard filter; when empty the first step asks for it.
  @api holderId;
  @api holders = [];

  type;
  step = 1;
  description = "";
  amount;
  dueDate;
  categoryId;
  status = "Pending";
  paymentDate;
  method = "cash";
  sourceId;
  chosenHolderId;
  options = { categories: [], accounts: [], cards: [] };
  isSaving = false;
  errorMessage;
  focusTitle = false;
  loadSeq = 0;
  isCreatingCategory = false;
  isLoadingPreview = false;
  // Recurring only
  variable = "no";
  amountKind = "total";
  installmentCount;
  administrator = "";
  awardedOn;
  dueDay;
  endDate;
  preview = [];

  connectedCallback() {
    this.chosenHolderId = this.holderId;
    this.loadOptions();
  }

  renderedCallback() {
    if (this.focusTitle) {
      this.focusTitle = false;
      const title = this.template.querySelector(".wizard-title");
      if (title) {
        title.focus();
      }
    }
  }

  async loadOptions() {
    const seq = ++this.loadSeq;
    try {
      // The dashboard filter "Todos" is an empty string, which is not a valid Id for Apex.
      const options = await getOptions({
        holderId: this.chosenHolderId || null
      });
      if (seq !== this.loadSeq) {
        return;
      }
      this.errorMessage = undefined;
      this.options = {
        categories: options.categories || [],
        accounts: options.accounts || [],
        cards: options.cards || []
      };
    } catch (error) {
      if (seq !== this.loadSeq) {
        return;
      }
      this.errorMessage = this.messageOf(
        error,
        "Não foi possível carregar as opções."
      );
    }
  }

  messageOf(error, fallback) {
    return (error && error.body && error.body.message) || fallback;
  }

  // ---- Step 0: expense type ----
  get typeButtons() {
    return TYPES.map((type) => ({
      ...type,
      disabled: !type.enabled,
      title: type.enabled ? "" : "Disponível em breve",
      cardClass: type.enabled ? "type-card" : "type-card type-card_disabled"
    }));
  }

  get isChoosingType() {
    return !this.type;
  }

  handleTypeClick(event) {
    this.type = event.currentTarget.dataset.type;
    this.step = 1;
    this.focusTitle = true;
  }

  handleChangeType() {
    this.type = undefined;
    // Nothing typed for one type leaks into the next.
    this.variable = "no";
    this.dueDay = undefined;
    this.endDate = undefined;
    this.preview = [];
    this.status = "Pending";
    this.paymentDate = undefined;
    this.amountKind = "total";
    this.installmentCount = undefined;
    this.administrator = "";
    this.awardedOn = undefined;
    this.errorMessage = undefined;
    this.focusTitle = true;
  }

  // ---- Steps ----
  get title() {
    if (this.isChoosingType) {
      return "Que tipo de despesa é?";
    }
    if (this.isRecurring) {
      return "Despesa recorrente";
    }
    if (this.isConsortium) {
      return "Consórcio";
    }
    return this.isInstallments ? "Despesa parcelada" : "Despesa avulsa";
  }

  get isInstallments() {
    return this.type === "installments";
  }

  get isConsortium() {
    return this.type === "consortium";
  }

  // Both fixed-installment types ask for the number of installments.
  get hasInstallmentCount() {
    return this.isInstallments || this.isConsortium;
  }

  get maxCount() {
    return this.isConsortium ? 240 : 120;
  }

  get hasContract() {
    return this.isRecurring || this.isInstallments || this.isConsortium;
  }

  get amountKindOptions() {
    return AMOUNT_KIND_OPTIONS;
  }

  get isRecurring() {
    return this.type === "recurring";
  }

  get isStandalone() {
    return !this.isRecurring;
  }

  get amountLabel() {
    if (this.isRecurring) {
      return "Valor mensal (ou estimado)";
    }
    if (this.isConsortium) {
      return "Valor da parcela";
    }
    return this.isInstallments && this.amountKind === "installment"
      ? "Valor da parcela"
      : this.isInstallments
        ? "Valor total"
        : "Valor";
  }

  get dueDateLabel() {
    return this.hasContract ? "Primeiro vencimento" : "Vencimento";
  }

  get variableOptions() {
    return VARIABLE_OPTIONS;
  }

  get previewRows() {
    return this.preview.slice(0, PREVIEW_ROWS).map((item, index) => ({
      key: `${item.dueDate}-${index}`,
      dueDate: this.format(item.dueDate),
      amount: this.money(item.amount)
    }));
  }

  get previewMore() {
    return Math.max(this.preview.length - PREVIEW_ROWS, 0);
  }

  get recurringSummary() {
    const count = this.preview.length;
    const entries =
      count === 1 ? "1 lançamento pendente" : `${count} lançamentos pendentes`;
    return `Será criado 1 Contrato (Recorrente) e ${entries}. Os próximos meses são gerados automaticamente todo mês.`;
  }

  get recurringJson() {
    return JSON.stringify(this.recurringRequest);
  }

  get recurringRequest() {
    return {
      base: this.baseRequest,
      variableAmount: this.variable === "yes",
      dueDay: this.dueDay ? Number(this.dueDay) : null,
      endDate: this.endDate || null
    };
  }

  get installmentJson() {
    return JSON.stringify(this.installmentRequest);
  }

  // What every type shares; each type adds its own fields around it.
  get baseRequest() {
    return {
      holderId: this.chosenHolderId,
      description: this.description.trim(),
      amount: Number(this.amount),
      dueDate: this.dueDate,
      categoryId: this.categoryId || null,
      accountId: this.method === "account" ? this.sourceId : null,
      cardId: this.method === "card" ? this.sourceId : null
    };
  }

  get consortiumJson() {
    return JSON.stringify(this.consortiumRequest);
  }

  get consortiumRequest() {
    return {
      base: this.baseRequest,
      count: this.installmentCount ? Number(this.installmentCount) : null,
      administrator: this.administrator.trim() || null,
      awardedOn: this.awardedOn || null
    };
  }

  get installmentRequest() {
    return {
      base: this.baseRequest,
      amountIsTotal: this.amountKind === "total",
      count: this.installmentCount ? Number(this.installmentCount) : null
    };
  }

  get installmentsValid() {
    return this.validCount(120);
  }

  get consortiumValid() {
    return this.validCount(240);
  }

  validCount(max) {
    const count = Number(this.installmentCount);
    return (
      /^\d+$/.test(String(this.installmentCount).trim()) &&
      Number.isInteger(count) &&
      count >= 2 &&
      count <= max
    );
  }

  // What the review shows besides the schedule, so the user confirms the whole Contract.
  get consortiumDetails() {
    const parts = [];
    if (this.administrator.trim()) {
      parts.push(`Administradora: ${this.administrator.trim()}`);
    }
    if (this.awardedOn) {
      parts.push(`Contemplado em ${this.format(this.awardedOn)}`);
    }
    return parts.join(" · ");
  }

  get hasConsortiumDetails() {
    return this.isConsortium && !!this.consortiumDetails;
  }

  get contractSummary() {
    return this.isInstallments || this.isConsortium
      ? this.installmentSummary
      : this.recurringSummary;
  }

  get installmentSummary() {
    const total =
      Math.round(
        this.preview.reduce((sum, item) => sum + item.amount, 0) * 100
      ) / 100;
    return `Será criado 1 Contrato (${this.isConsortium ? "Consórcio" : "Parcelado"}) e ${this.preview.length} lançamentos pendentes. Total ${this.money(total)}.`;
  }

  get recurringValid() {
    const day = this.dueDay ? Number(this.dueDay) : null;
    return (
      (day === null || (Number.isInteger(day) && day >= 1 && day <= 31)) &&
      (!this.endDate || (!!this.dueDate && this.endDate >= this.dueDate))
    );
  }

  get stepLabel() {
    return `Etapa ${this.step} de 3 — ${STEP_TITLES[this.step - 1]}`;
  }

  get progress() {
    return Math.round((this.step / 3) * 100);
  }

  get isStep1() {
    return this.step === 1;
  }

  get isStep2() {
    return this.step === 2;
  }

  get isLast() {
    return this.step === 3;
  }

  get hasHolderContext() {
    return !!this.holderId;
  }

  get holderOptions() {
    return (this.holders || []).map((holder) => ({
      label: holder.name,
      value: holder.id
    }));
  }

  get statusOptions() {
    return STATUS_OPTIONS;
  }

  get methodOptions() {
    return METHOD_OPTIONS;
  }

  get isRealized() {
    return this.status === "Realized";
  }

  get needsSource() {
    return this.method !== "cash";
  }

  get sourceLabel() {
    return this.method === "card" ? "Cartão" : "Conta";
  }

  get sourceOptions() {
    const list =
      this.method === "card" ? this.options.cards : this.options.accounts;
    return list.map((s) => ({ label: s.label, value: s.id }));
  }

  get step1Valid() {
    return (
      !!this.chosenHolderId &&
      !!this.description.trim() &&
      Number(this.amount) > 0 &&
      !!this.dueDate &&
      (this.isRecurring
        ? this.recurringValid
        : this.isConsortium
          ? this.consortiumValid
          : this.isInstallments
            ? this.installmentsValid
            : !this.isRealized || !!this.paymentDate)
    );
  }

  get step2Valid() {
    return !this.needsSource || !!this.sourceId;
  }

  get nextDisabled() {
    if (this.isLoadingPreview) {
      return true;
    }
    if (this.isStep1) {
      return !this.step1Valid;
    }
    return this.isStep2 ? !this.step2Valid : false;
  }

  // "Moradia › Energia": the category with its parents.
  get categoryName() {
    const byId = new Map(this.options.categories.map((c) => [c.id, c]));
    const names = [];
    const seen = new Set();
    let current = byId.get(this.categoryId);
    while (current && !seen.has(current.id)) {
      seen.add(current.id);
      names.unshift(current.label);
      current = current.parentId ? byId.get(current.parentId) : undefined;
    }
    return names.length ? names.join(" › ") : "Sem categoria";
  }

  get methodName() {
    const found = METHOD_OPTIONS.find((o) => o.value === this.method);
    const source = this.sourceOptions.find((o) => o.value === this.sourceId);
    return source ? `${found.label} (${source.label})` : found.label;
  }

  get reviewLine() {
    return `${this.description.trim()} · ${this.categoryName} · ${this.methodName}`;
  }

  get reviewSummary() {
    const situation = this.isRealized ? "realizado" : "pendente";
    return `Será criado 1 lançamento ${situation} · Vencimento ${this.format(
      this.dueDate
    )} · ${this.money(this.amount)}`;
  }

  format(isoDate) {
    if (!isoDate) {
      return "";
    }
    const [year, month, day] = isoDate.split("-");
    return `${day}/${month}/${year}`;
  }

  money(value) {
    return new Intl.NumberFormat("pt-BR", {
      style: "currency",
      currency: "BRL"
    }).format(Number(value) || 0);
  }

  // ---- Field handlers ----
  handleDescription(event) {
    this.description = event.detail.value || "";
  }

  handleAmount(event) {
    this.amount = event.detail.value;
  }

  handleDueDate(event) {
    this.dueDate = event.detail.value;
  }

  handleCategory(event) {
    this.categoryId = event.detail.value;
  }

  // "+ Nova categoria": creates it (top level) and selects it.
  async handleCreateCategory(event) {
    if (this.isCreatingCategory) {
      return;
    }
    this.isCreatingCategory = true;
    this.errorMessage = undefined;
    try {
      const created = await createCategory({
        name: event.detail.name,
        parentId: null
      });
      // A holder change may still have a load in flight; its list would not have this one.
      this.loadSeq += 1;
      const known = this.options.categories.some((c) => c.id === created.id);
      this.options = {
        ...this.options,
        categories: known
          ? this.options.categories
          : [...this.options.categories, created]
      };
      this.categoryId = created.id;
    } catch (error) {
      this.errorMessage = this.messageOf(
        error,
        "Não foi possível criar a categoria."
      );
    } finally {
      this.isCreatingCategory = false;
    }
  }

  handleStatus(event) {
    this.status = event.detail.value;
    if (!this.isRealized) {
      this.paymentDate = undefined;
    }
  }

  handlePaymentDate(event) {
    this.paymentDate = event.detail.value;
  }

  handleHolder(event) {
    this.chosenHolderId = event.detail.value;
    this.sourceId = undefined;
    this.loadOptions();
  }

  handleMethod(event) {
    this.method = event.detail.value;
    this.sourceId = undefined;
  }

  handleSource(event) {
    this.sourceId = event.detail.value;
  }

  // ---- Navigation ----
  handleVariable(event) {
    this.variable = event.detail.value;
  }

  handleAmountKind(event) {
    this.amountKind = event.detail.value;
  }

  handleInstallmentCount(event) {
    this.installmentCount = event.detail.value;
  }

  handleAdministrator(event) {
    this.administrator = event.detail.value || "";
  }

  handleAwardedOn(event) {
    this.awardedOn = event.detail.value;
  }

  handleDueDay(event) {
    this.dueDay = event.detail.value;
  }

  handleEndDate(event) {
    this.endDate = event.detail.value;
  }

  fetchPreview() {
    if (this.isConsortium) {
      return previewConsortium({ requestJson: this.consortiumJson });
    }
    return this.isInstallments
      ? previewInstallment({ requestJson: this.installmentJson })
      : previewRecurring({ requestJson: this.recurringJson });
  }

  async handleNext() {
    if (this.nextDisabled) {
      return;
    }
    this.errorMessage = undefined;
    if (this.hasContract && this.step === 2) {
      this.isLoadingPreview = true;
      try {
        this.preview = [];
        this.preview = await this.fetchPreview();
      } catch (error) {
        this.errorMessage = this.messageOf(
          error,
          "Não foi possível calcular os lançamentos."
        );
        return;
      } finally {
        this.isLoadingPreview = false;
      }
    }
    this.step += 1;
    this.focusTitle = true;
  }

  handleBack() {
    this.step -= 1;
    this.errorMessage = undefined;
    this.focusTitle = true;
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  async handleConclude() {
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      if (this.hasContract) {
        if (this.isConsortium) {
          await createConsortium({ requestJson: this.consortiumJson });
        } else if (this.isInstallments) {
          await createInstallment({ requestJson: this.installmentJson });
        } else {
          await createRecurring({ requestJson: this.recurringJson });
        }
        this.dispatchEvent(new CustomEvent("saved"));
        return;
      }
      // A JSON string: Aura does not fill the fields of an Apex object parameter reliably.
      await createStandalone({
        requestJson: JSON.stringify({
          holderId: this.chosenHolderId,
          description: this.description.trim(),
          amount: Number(this.amount),
          dueDate: this.dueDate,
          categoryId: this.categoryId || null,
          status: this.status,
          paymentDate: this.isRealized ? this.paymentDate : null,
          accountId: this.method === "account" ? this.sourceId : null,
          cardId: this.method === "card" ? this.sourceId : null
        })
      });
      this.dispatchEvent(new CustomEvent("saved"));
    } catch (error) {
      this.errorMessage = this.messageOf(
        error,
        "Não foi possível criar a despesa."
      );
    } finally {
      this.isSaving = false;
    }
  }
}
