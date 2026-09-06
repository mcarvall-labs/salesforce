import { LightningElement } from "lwc";
import planSchedule from "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.planSchedule";
import saveSchedule from "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.saveSchedule";
import authorizedContexts from "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.authorizedContexts";

const MODALITY_OPTIONS = [
  { label: "PRICE (parcela constante)", value: "PRICE" },
  { label: "SAC (amortização constante)", value: "SAC" },
  { label: "Parcelado sem juros", value: "INSTALLMENT" },
  { label: "Recorrente (valor fixo)", value: "RECURRING" }
];

const DIRECTION_OPTIONS = [
  { label: "Despesa (pago)", value: "DEBIT" },
  { label: "Receita (recebido)", value: "CREDIT" }
];

const OUTCOME_LABELS = {
  SAVED: "Cronograma salvo como rascunho.",
  ALREADY: "Cronograma já salvo — nada foi duplicado.",
  CONFLICT: "Já existe um cronograma diferente com esta chave.",
  BLOCKED: "Modalidade sem policy canônica.",
  INVALID: "Dados do cronograma inválidos.",
  FORBIDDEN: "Você não tem acesso a esta entidade titular."
};

export default class AXF_LWC_scheduleWizard extends LightningElement {
  modalityOptions = MODALITY_OPTIONS;
  directionOptions = DIRECTION_OPTIONS;
  contextOptions = [];

  modality = "PRICE";
  accountId;
  direction = "DEBIT";
  currencyIsoCode = "BRL";
  principal;
  installments;
  periodRate;
  firstDueDate;
  fixedValue;
  flatFeePerInstallment;
  upfrontFee;

  schedule;
  saveResult;
  errorMessage;
  loading = false;

  connectedCallback() {
    authorizedContexts()
      .then((rows) => {
        this.contextOptions = (rows || []).map((c) => ({
          label: c.label,
          value: c.accountId
        }));
      })
      .catch(() => {
        this.contextOptions = [];
        this.errorMessage = "Não foi possível carregar as entidades titulares.";
      });
  }

  get showRate() {
    return this.modality === "PRICE" || this.modality === "SAC";
  }

  get showPrincipal() {
    return this.modality !== "RECURRING";
  }

  get showFixedValue() {
    return this.modality === "RECURRING";
  }

  get hasSchedule() {
    return !!(this.schedule && this.schedule.outcome === "OK");
  }

  get scheduleRows() {
    if (!this.hasSchedule) return [];
    return this.schedule.occurrences.map((o) => ({
      ...o,
      key: o.sequence
    }));
  }

  get saveOutcomeLabel() {
    if (!this.saveResult) return "";
    return (
      OUTCOME_LABELS[this.saveResult.outcome] ||
      this.saveResult.message ||
      this.saveResult.outcome
    );
  }

  get planDisabled() {
    return this.loading;
  }

  get saveDisabled() {
    return this.loading || !this.hasSchedule || !this.accountId;
  }

  handleChange(event) {
    const field = event.target.dataset.field;
    let value = event.target.value;
    if (event.target.type === "number") {
      value = value === "" ? undefined : Number(value);
    }
    this[field] = value;
  }

  buildPlanInput() {
    return {
      modality: this.modality,
      principal: this.showPrincipal ? this.principal : undefined,
      installments: this.installments,
      periodRate: this.showRate ? this.periodRate : undefined,
      firstDueDate: this.firstDueDate,
      fixedValue: this.showFixedValue ? this.fixedValue : undefined,
      flatFeePerInstallment: this.flatFeePerInstallment,
      upfrontFee: this.upfrontFee
    };
  }

  async handlePlan() {
    this.errorMessage = undefined;
    this.saveResult = undefined;
    this.loading = true;
    try {
      const result = await planSchedule({ input: this.buildPlanInput() });
      this.schedule = result;
      if (result.outcome !== "OK") {
        this.errorMessage = result.message;
      }
    } catch (e) {
      this.errorMessage =
        (e.body && e.body.message) || "Não foi possível gerar a prévia.";
    } finally {
      this.loading = false;
    }
  }

  async handleSave() {
    this.errorMessage = undefined;
    this.loading = true;
    try {
      const groupKey = this.newGroupKey();
      const result = await saveSchedule({
        input: {
          plan: this.buildPlanInput(),
          accountId: this.accountId,
          direction: this.direction,
          currencyIsoCode: this.currencyIsoCode,
          groupKey
        }
      });
      this.saveResult = result;
      if (result.outcome !== "SAVED" && result.outcome !== "ALREADY") {
        this.errorMessage = result.message;
      }
    } catch (e) {
      this.errorMessage =
        (e.body && e.body.message) || "Não foi possível salvar o cronograma.";
    } finally {
      this.loading = false;
    }
  }

  newGroupKey() {
    const rnd =
      (globalThis.crypto && globalThis.crypto.randomUUID
        ? globalThis.crypto.randomUUID()
        : `${Date.now()}-${Math.random()}`) || "";
    return ("sch-" + rnd.replace(/[^a-zA-Z0-9]/g, "")).substring(0, 24);
  }
}
