import { LightningElement, api } from "lwc";
import save from "@salesforce/apex/AXF_CLS_CTRL_ManualFinancialSource.save";

const COPY = {
  "pt-BR": {
    title: "Fonte financeira manual",
    kind: "Tipo de fonte",
    holder: "Titular",
    currency: "Moeda (ISO)",
    institution: "Instituição",
    masked: "Número mascarado",
    type: "Tipo da conta",
    brand: "Bandeira",
    save: "Salvar",
    skip: "Pular por enquanto",
    saving: "Salvando",
    bank: "Conta bancária",
    card: "Cartão de crédito",
    invalid: "Revise os campos destacados.",
    created: "Fonte financeira criada.",
    updated: "Fonte financeira atualizada.",
    already: "Esta operação já foi concluída.",
    conflict: "Os dados mudaram. Recarregue e revise.",
    forbidden: "Você não tem autorização para esta ação.",
    failed: "Não foi possível salvar. Nada foi alterado."
  },
  en: {
    title: "Manual financial source",
    kind: "Source type",
    holder: "Holder",
    currency: "Currency (ISO)",
    institution: "Institution",
    masked: "Masked number",
    type: "Account type",
    brand: "Card brand",
    save: "Save",
    skip: "Skip for now",
    saving: "Saving",
    bank: "Bank account",
    card: "Credit card",
    invalid: "Review the highlighted fields.",
    created: "Financial source created.",
    updated: "Financial source updated.",
    already: "This operation was already completed.",
    conflict: "The data changed. Reload and review.",
    forbidden: "You are not authorized for this action.",
    failed: "Unable to save. Nothing was changed."
  }
};

export default class AXF_LWC_manualFinancialSource extends LightningElement {
  @api locale = "pt-BR";
  @api allowSkip = false;
  _sourceId;
  _expectedVersion;
  _shouldFocusMessage = false;
  @api
  get sourceId() {
    return this._sourceId;
  }
  set sourceId(value) {
    this._sourceId = value;
  }
  @api
  get expectedVersion() {
    return this._expectedVersion;
  }
  set expectedVersion(value) {
    this._expectedVersion = value;
  }
  form = {
    kind: "BANK",
    holderId: null,
    currencyIsoCode: "BRL",
    institutionName: "",
    maskedNumber: "",
    sourceType: "",
    brand: ""
  };
  saving = false;
  message = "";
  outcome = "";
  pendingManualKey;
  get labels() {
    return COPY[this.locale] || COPY.en;
  }
  get kindOptions() {
    return [
      { label: this.labels.bank, value: "BANK" },
      { label: this.labels.card, value: "CARD" }
    ];
  }
  get isBank() {
    return this.form.kind === "BANK";
  }
  get isCard() {
    return this.form.kind === "CARD";
  }
  get isEdit() {
    return Boolean(this.sourceId);
  }
  get messageClass() {
    return this.outcome === "CREATED" ||
      this.outcome === "UPDATED" ||
      this.outcome === "ALREADY"
      ? "slds-notify slds-notify_alert slds-alert_success"
      : "slds-notify slds-notify_alert slds-alert_error";
  }
  handleChange(e) {
    this.form = {
      ...this.form,
      [e.target.name]: e.detail?.value ?? e.target.value
    };
  }
  handleHolder(e) {
    this.form = { ...this.form, holderId: e.detail.recordId };
  }
  async handleSave() {
    const fields = [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-combobox, lightning-record-picker"
      )
    ];
    if (
      !fields.reduce((ok, f) => {
        f.reportValidity();
        return f.checkValidity() && ok;
      }, true)
    ) {
      this.message = this.labels.invalid;
      this.outcome = "INVALID";
      this.focusMessage();
      return;
    }
    this.saving = true;
    try {
      if (!this.sourceId && !this.pendingManualKey) {
        this.pendingManualKey = crypto.randomUUID();
      }
      const result = await save({
        input: {
          ...this.form,
          sourceId: this.sourceId,
          expectedVersion: this.expectedVersion,
          manualKey: this.sourceId ? null : this.pendingManualKey
        }
      });
      this.outcome = result.outcome;
      const successful = ["CREATED", "UPDATED", "ALREADY"].includes(
        result.outcome
      );
      const messageKey = result.outcome.toLowerCase();
      this.message =
        result.outcome === "INVALID"
          ? this.labels.invalid
          : this.labels[messageKey] || this.labels.failed;
      if (successful) {
        this._sourceId = result.sourceId || this.sourceId;
        this._expectedVersion = result.version ?? this.expectedVersion;
        if (["CREATED", "ALREADY"].includes(result.outcome)) {
          this.pendingManualKey = undefined;
        }
        this.dispatchEvent(new CustomEvent("sourcesaved", { detail: result }));
      }
    } catch {
      this.message = this.labels.failed;
      this.outcome = "FAILED";
    } finally {
      this.saving = false;
      this.focusMessage();
    }
  }
  handleSkip() {
    this.dispatchEvent(new CustomEvent("skip"));
  }
  focusMessage() {
    this._shouldFocusMessage = true;
  }
  renderedCallback() {
    if (this._shouldFocusMessage) {
      this._shouldFocusMessage = false;
      this.template.querySelector("[data-message]")?.focus();
    }
  }
}
