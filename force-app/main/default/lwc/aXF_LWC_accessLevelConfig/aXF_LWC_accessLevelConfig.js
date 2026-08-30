import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.canConfigure";
import getEligibleUsers from "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.getEligibleUsers";
import applyAccessLevel from "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.applyAccessLevel";

// PT-BR literals for the MVP (D-86: PT-BR only). Move to Custom Labels + Translation
// Workbench when that i18n infrastructure is set up.
const TITLE = "Níveis de acesso do Axon";
const EMPTY = "Nenhum usuário elegível encontrado.";
const FORBIDDEN = "Você não tem autorização para configurar níveis de acesso.";
const APPLY = "Aplicar";
const INVALID_LEVEL = "Selecione um nível de acesso válido.";
const GENERIC_FAIL = "Não foi possível aplicar o nível de acesso. Nada foi alterado.";
const LOAD_ERROR = "Não foi possível carregar os usuários.";
const RETRY = "Tentar novamente";
const LVL_GESTOR = "Gestor Financeiro";
const LVL_PARTICIPANTE = "Participante";
const LVL_NONE = "Sem acesso ao Axon";
const LEVEL_LABEL = "Nível de acesso";
const SELECT_PLACEHOLDER = "Selecione";
const COL_NAME = "Nome";
const COL_USERNAME = "Usuário";
const COL_CURRENT = "Nível atual";

const STATE = {
  LOADING: "LOADING",
  READY_DATA: "READY_DATA",
  READY_EMPTY: "READY_EMPTY",
  FORBIDDEN: "FORBIDDEN",
  ERROR: "ERROR"
};

export default class AxfAccessLevelConfig extends LightningElement {
  labels = {
    TITLE,
    EMPTY,
    FORBIDDEN,
    APPLY,
    LOAD_ERROR,
    RETRY,
    LEVEL_LABEL,
    SELECT_PLACEHOLDER
  };

  state = STATE.LOADING;
  users = [];
  selectedUserId;
  selectedLevel;
  applying = false;
  feedback;
  feedbackVariant = "info";

  _wired;

  levelOptions = [
    { label: LVL_GESTOR, value: "GESTOR" },
    { label: LVL_PARTICIPANTE, value: "PARTICIPANTE" }
  ];

  columns = [
    { label: COL_NAME, fieldName: "name", type: "text" },
    { label: COL_USERNAME, fieldName: "username", type: "text" },
    { label: COL_CURRENT, fieldName: "currentLevel", type: "text" }
  ];

  @wire(canConfigure)
  wiredCanConfigure({ data, error }) {
    if (error) {
      this.state = STATE.ERROR;
    } else if (data === false) {
      this.state = STATE.FORBIDDEN;
    }
  }

  @wire(getEligibleUsers)
  wiredUsers(result) {
    this._wired = result;
    const { data, error } = result;
    if (error) {
      this.state = STATE.ERROR;
      return;
    }
    if (!data) {
      return;
    }
    this.users = data.map((u) => ({
      ...u,
      currentLevel: u.currentLevel || LVL_NONE
    }));
    if (this.state === STATE.FORBIDDEN) {
      return;
    }
    this.state = this.users.length ? STATE.READY_DATA : STATE.READY_EMPTY;
  }

  get isLoading() {
    return this.state === STATE.LOADING;
  }
  get isForbidden() {
    return this.state === STATE.FORBIDDEN;
  }
  get isEmpty() {
    return this.state === STATE.READY_EMPTY;
  }
  get isError() {
    return this.state === STATE.ERROR;
  }
  get isReady() {
    return this.state === STATE.READY_DATA;
  }
  get applyDisabled() {
    return this.applying || !this.selectedUserId || !this.selectedLevel;
  }

  handleRowSelection(event) {
    const rows = event.detail.selectedRows;
    this.selectedUserId = rows.length ? rows[0].userId : undefined;
    this.feedback = undefined;
  }

  handleLevelChange(event) {
    this.selectedLevel = event.detail.value;
  }

  async handleApply() {
    if (!this.selectedUserId || !this.selectedLevel) {
      this.setFeedback(INVALID_LEVEL, "warning");
      return;
    }
    this.applying = true;
    this.feedback = undefined;
    try {
      const res = await applyAccessLevel({
        userId: this.selectedUserId,
        level: this.selectedLevel
      });
      const variant =
        res.outcome === "SUCCEEDED" || res.outcome === "ALREADY_APPLIED"
          ? "success"
          : res.outcome === "PENDING"
            ? "warning"
            : "error";
      this.setFeedback(res.message || GENERIC_FAIL, variant);
      await refreshApex(this._wired);
    } catch {
      this.setFeedback(GENERIC_FAIL, "error");
    } finally {
      this.applying = false;
    }
  }

  handleRetry() {
    this.state = STATE.LOADING;
    refreshApex(this._wired);
  }

  setFeedback(message, variant) {
    this.feedback = message;
    this.feedbackVariant = variant;
  }
}
