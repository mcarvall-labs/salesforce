import { LightningElement } from "lwc";
import LANG from "@salesforce/i18n/lang";
import access from "@salesforce/apex/AXF_CLS_CTRL_AxonConfig.access";

const PT = {
  title: "AXON - Configuration",
  subtitle:
    "Abra diretamente a área que quer manter. Cada área usa a mesma capacidade do onboarding — não é preciso refazer as etapas.",
  back: "Voltar ao menu",
  areas: {
    CURRENCY: "Preferência de moeda",
    PLUGGY: "Credenciais e consentimento Pluggy",
    HEALTH: "Saúde das fontes",
    HOLDERS: "Titulares cadastrados",
    SOURCE_HOLDERS: "Titulares das contas e cartões",
    RESPONSIBLES: "Vínculos e responsáveis por empresa",
    PEOPLE: "Pessoas e acessos",
    LEVEL: "Nível de acesso",
    MANUAL: "Contas e cartões sem Pluggy",
    RESUME: "Retomar a configuração"
  }
};
const EN = {
  title: "AXON - Configuration",
  subtitle:
    "Open the area you want to maintain. Each area reuses the same onboarding capability — no need to redo the steps.",
  back: "Back to menu",
  areas: {
    CURRENCY: "Display currency preference",
    PLUGGY: "Pluggy credentials and consent",
    HEALTH: "Source health",
    HOLDERS: "Registered holders",
    SOURCE_HOLDERS: "Account and card holders",
    RESPONSIBLES: "Company links and responsibles",
    PEOPLE: "People and access",
    LEVEL: "Access level",
    MANUAL: "Accounts and cards without Pluggy",
    RESUME: "Resume setup"
  }
};
const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

const ADMIN_AREAS = [
  "PLUGGY",
  "HEALTH",
  "HOLDERS",
  "SOURCE_HOLDERS",
  "RESPONSIBLES",
  "PEOPLE",
  "LEVEL",
  "MANUAL",
  "RESUME"
];

export default class AxfLwcAxonConfiguration extends LightningElement {
  labels = L;
  loading = true;
  canConfigure = false;
  open = null;

  async connectedCallback() {
    const a = await access().catch(() => null);
    this.canConfigure = !!(a && a.canConfigure);
    this.loading = false;
  }

  get areas() {
    const keys = this.canConfigure
      ? ["CURRENCY", ...ADMIN_AREAS]
      : ["CURRENCY"];
    return keys.map((k) => ({ key: k, label: L.areas[k] }));
  }
  get inMenu() {
    return !this.open;
  }
  get showCurrency() {
    return this.open === "CURRENCY";
  }
  get showPluggy() {
    return this.open === "PLUGGY";
  }
  get showHealth() {
    return this.open === "HEALTH";
  }
  get showHolders() {
    return this.open === "HOLDERS";
  }
  get showSourceHolders() {
    return this.open === "SOURCE_HOLDERS";
  }
  get showResponsibles() {
    return this.open === "RESPONSIBLES";
  }
  get showPeople() {
    return this.open === "PEOPLE";
  }
  get showLevel() {
    return this.open === "LEVEL";
  }
  get showManual() {
    return this.open === "MANUAL";
  }
  get showResume() {
    return this.open === "RESUME";
  }
  get openLabel() {
    return this.open ? L.areas[this.open] : "";
  }

  handleOpen(event) {
    this.open = event.currentTarget.dataset.area;
    this.moveFocus();
  }
  handleBack() {
    this.open = null;
    this.moveFocus();
  }
  moveFocus() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const el = this.template.querySelector("[data-focus]");
      if (el) {
        el.focus();
      }
    });
  }
}
