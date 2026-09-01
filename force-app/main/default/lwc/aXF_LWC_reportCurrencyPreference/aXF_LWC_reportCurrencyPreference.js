import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getState from "@salesforce/apex/AXF_CLS_CTRL_ReportCurrencyPref.getState";
import setPreference from "@salesforce/apex/AXF_CLS_CTRL_ReportCurrencyPref.setPreference";

// PT-BR literals for the MVP (D-86). Move to Custom Labels + Translation Workbench when
// that i18n infrastructure exists (same convention as aXF_LWC_accessLevelConfig).
const L = {
  TITLE: "Moeda de apresentação",
  HELP: "Define apenas como os valores são exibidos. Não converte nem altera suas contas, transações, saldos ou histórico.",
  LABEL: "Moeda preferida",
  PLACEHOLDER: "Selecione",
  SUGGESTED: "Sugerida",
  SAVE: "Salvar",
  LOAD_ERROR: "Não foi possível carregar as moedas.",
  RETRY: "Tentar novamente",
  SAVED: "Preferência de moeda salva.",
  GENERIC_FAIL: "Não foi possível salvar. Nada foi alterado.",
  CONFIRM_PREFIX: "Já existe uma preferência. ",
  CONFIRM_SUFFIX: " Confirmar a troca?",
  CONFIRM_YES: "Confirmar troca",
  CONFIRM_NO: "Cancelar"
};

const STATE = { LOADING: "LOADING", READY: "READY", ERROR: "ERROR" };

export default class AxfReportCurrencyPreference extends LightningElement {
  labels = L;
  state = STATE.LOADING;
  options = [];
  currentIsoCode;
  suggestedIsoCode;
  selected;
  saving = false;
  feedback;
  feedbackVariant = "info";
  pendingConfirmIso;
  confirmMessage;
  _wired;

  @wire(getState)
  wiredState(result) {
    this._wired = result;
    const { data, error } = result;
    if (error) {
      this.state = STATE.ERROR;
      return;
    }
    if (!data) {
      return;
    }
    this.options = (data.options || []).map((o) => ({
      label: o.suggestedDefault ? `${o.label} — ${L.SUGGESTED}` : o.label,
      value: o.isoCode
    }));
    this.currentIsoCode = data.currentIsoCode;
    this.suggestedIsoCode = data.suggestedIsoCode;
    this.selected = data.currentIsoCode || data.suggestedIsoCode || undefined;
    this.state = STATE.READY;
  }

  get isLoading() {
    return this.state === STATE.LOADING;
  }
  get isError() {
    return this.state === STATE.ERROR;
  }
  get isReady() {
    return this.state === STATE.READY;
  }
  get saveDisabled() {
    return (
      this.saving || !this.selected || this.selected === this.currentIsoCode
    );
  }
  get showConfirm() {
    return !!this.pendingConfirmIso;
  }

  handleChange(event) {
    this.selected = event.detail.value;
    this.feedback = undefined;
    this.pendingConfirmIso = undefined;
  }

  handleSave() {
    this.persist(this.selected, false);
  }
  handleConfirmYes() {
    this.persist(this.pendingConfirmIso, true);
  }
  handleConfirmNo() {
    this.pendingConfirmIso = undefined;
    this.confirmMessage = undefined;
  }

  async persist(iso, overwrite) {
    this.saving = true;
    this.feedback = undefined;
    try {
      const res = await setPreference({
        isoCode: iso,
        overwriteExisting: overwrite
      });
      if (res.confirmRequired) {
        this.pendingConfirmIso = iso;
        this.confirmMessage =
          L.CONFIRM_PREFIX + (res.message || "") + L.CONFIRM_SUFFIX;
      } else if (res.applied) {
        this.currentIsoCode = res.currentIsoCode;
        this.pendingConfirmIso = undefined;
        this.confirmMessage = undefined;
        this.setFeedback(res.message || L.SAVED, "success");
        this.refresh();
      } else {
        this.setFeedback(res.message || L.GENERIC_FAIL, "error");
      }
    } catch (e) {
      this.setFeedback(this.extractMessage(e), "error");
    } finally {
      this.saving = false;
    }
  }

  refresh() {
    if (this._wired) {
      Promise.resolve(refreshApex(this._wired)).catch(() => {});
    }
  }
  handleRetry() {
    this.state = STATE.LOADING;
    refreshApex(this._wired);
  }
  extractMessage(e) {
    return e?.body?.message || e?.message || L.GENERIC_FAIL;
  }
  setFeedback(message, variant) {
    this.feedback = message;
    this.feedbackVariant = variant;
  }
}
