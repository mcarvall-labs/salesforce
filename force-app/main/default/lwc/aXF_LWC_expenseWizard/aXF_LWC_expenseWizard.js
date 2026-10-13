import { LightningElement, api } from "lwc";
import getOptions from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.getOptions";
import createStandalone from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createStandalone";
import createRecurring from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createRecurring";
import previewRecurring from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewRecurring";
import createInstallment from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createInstallment";
import previewInstallment from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewInstallment";

const STEP_TITLES = ["Dados", "Pagamento", "Revisar"];
const TYPES = [
  { value: "standalone", label: "Despesa avulsa", enabled: true },
  { value: "recurring", label: "Recorrente", enabled: true },
  { value: "installments", label: "Parcelada", enabled: true },
  { value: "consortium", label: "Consórcio", enabled: false },
  { value: "financing", label: "Financiamento", enabled: false }
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
  isLoadingPreview = false;
  // Recurring only
  variable = "no";
  amountKind = "total";
  installmentCount;
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
      const options = await getOptions({ holderId: this.chosenHolderId });
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
      variant: type.enabled ? "brand" : "neutral"
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
    this.amountKind = "total";
    this.installmentCount = undefined;
    this.preview = [];
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
    return this.isInstallments ? "Despesa parcelada" : "Despesa avulsa";
  }

  get isInstallments() {
    return this.type === "installments";
  }

  get hasContract() {
    return this.isRecurring || this.isInstallments;
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
    return this.preview.slice(0, PREVIEW_ROWS).map((item) => ({
      key: item.dueDate,
      dueDate: this.format(item.dueDate),
      amount: this.money(item.amount)
    }));
  }

  get previewMore() {
    return Math.max(this.preview.length - PREVIEW_ROWS, 0);
  }

  get recurringSummary() {
    return `Será criado 1 Contrato (Recorrente) e ${this.preview.length} lançamentos pendentes (o job mensal estende).`;
  }

  get recurringRequest() {
    return {
      base: {
        holderId: this.chosenHolderId,
        description: this.description.trim(),
        amount: Number(this.amount),
        dueDate: this.dueDate,
        categoryId: this.categoryId || null,
        accountId: this.method === "account" ? this.sourceId : null,
        cardId: this.method === "card" ? this.sourceId : null
      },
      variableAmount: this.variable === "yes",
      dueDay: this.dueDay ? Number(this.dueDay) : null,
      endDate: this.endDate || null
    };
  }

  get installmentRequest() {
    return {
      base: this.recurringRequest.base,
      amountIsTotal: this.amountKind === "total",
      count: this.installmentCount ? Number(this.installmentCount) : null
    };
  }

  get installmentsValid() {
    const count = Number(this.installmentCount);
    return Number.isInteger(count) && count >= 2 && count <= 120;
  }

  get contractSummary() {
    return this.isInstallments
      ? this.installmentSummary
      : this.recurringSummary;
  }

  get installmentSummary() {
    const total =
      Math.round(
        this.preview.reduce((sum, item) => sum + item.amount, 0) * 100
      ) / 100;
    return `Será criado 1 Contrato (Parcelado) e ${this.preview.length} lançamentos pendentes. Total ${this.money(total)}.`;
  }

  get recurringValid() {
    const day = this.dueDay ? Number(this.dueDay) : null;
    return (
      (day === null || (Number.isInteger(day) && day >= 1 && day <= 31)) &&
      (!this.endDate || this.endDate >= this.dueDate)
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

  get categoryOptions() {
    return this.options.categories.map((c) => ({
      label: c.label,
      value: c.id
    }));
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

  get categoryName() {
    const found = this.categoryOptions.find((o) => o.value === this.categoryId);
    return found ? found.label : "Sem categoria";
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

  handleDueDay(event) {
    this.dueDay = event.detail.value;
  }

  handleEndDate(event) {
    this.endDate = event.detail.value;
  }

  async handleNext() {
    if (this.nextDisabled) {
      return;
    }
    this.errorMessage = undefined;
    if (this.hasContract && this.step === 2) {
      this.isLoadingPreview = true;
      try {
        this.preview = this.isInstallments
          ? await previewInstallment({ request: this.installmentRequest })
          : await previewRecurring({ request: this.recurringRequest });
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
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      if (this.hasContract) {
        if (this.isInstallments) {
          await createInstallment({ request: this.installmentRequest });
        } else {
          await createRecurring({ request: this.recurringRequest });
        }
        this.dispatchEvent(new CustomEvent("saved"));
        return;
      }
      await createStandalone({
        request: {
          holderId: this.chosenHolderId,
          description: this.description.trim(),
          amount: Number(this.amount),
          dueDate: this.dueDate,
          categoryId: this.categoryId || null,
          status: this.status,
          paymentDate: this.isRealized ? this.paymentDate : null,
          accountId: this.method === "account" ? this.sourceId : null,
          cardId: this.method === "card" ? this.sourceId : null
        }
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
