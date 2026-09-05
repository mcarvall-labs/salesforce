import { LightningElement, track } from "lwc";
import LANG from "@salesforce/i18n/lang";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.canConfigure";
import getState from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.getState";
import confirmStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.confirmStep";
import skipStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.skipStep";
import reopenStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.reopenStep";
import complete from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.complete";

const ORDER = [
  "WELCOME_PREFS",
  "PLUGGY_CREDENTIALS",
  "PLUGGY_DISCOVERY",
  "ACCOUNT_HOLDERS",
  "PEOPLE_ACCESS",
  "MANUAL_SOURCES",
  "CURRENCY_PREF"
];
const OPTIONAL = new Set(["PEOPLE_ACCESS", "MANUAL_SOURCES"]);

const PT = {
  title: "Configuração do Axon",
  forbidden: "Você não tem autorização para conduzir a configuração do Axon.",
  stepOf: "Etapa {0} de {1}",
  back: "Voltar",
  next: "Próximo",
  working: "Salvando...",
  skip: "Pular esta etapa",
  reopen: "Reabrir para editar",
  review: "Revisão",
  finish: "Concluir configuração",
  ackPending:
    "Há etapas obrigatórias ou fontes ainda sem titular. Reconheço as pendências e quero concluir mesmo assim.",
  done: "Configuração concluída.",
  doneHint: "Você pode ajustar qualquer área depois em AXON - Configuration.",
  stale:
    "Uma etapa anterior foi reaberta — revise as etapas marcadas como desatualizadas.",
  conflict:
    "A configuração mudou em outra sessão. Recarregamos o estado atual.",
  steps: {
    WELCOME_PREFS: "Boas-vindas",
    PLUGGY_CREDENTIALS: "Credenciais Pluggy",
    PLUGGY_DISCOVERY: "Buscar contas e cartões",
    ACCOUNT_HOLDERS: "Titulares das fontes",
    PEOPLE_ACCESS: "Pessoas e acessos (opcional)",
    MANUAL_SOURCES: "Contas e cartões sem Pluggy (opcional)",
    CURRENCY_PREF: "Moeda de exibição",
    REVIEW: "Revisão"
  },
  welcome:
    "Bem-vindo. Esta configuração é opcional e pode ser retomada a qualquer momento — o Axon já está instalado para a sua família."
};
const EN = {
  title: "Axon setup",
  forbidden: "You are not authorized to run the Axon setup.",
  stepOf: "Step {0} of {1}",
  back: "Back",
  next: "Next",
  working: "Saving...",
  skip: "Skip this step",
  reopen: "Reopen to edit",
  review: "Review",
  finish: "Finish setup",
  ackPending:
    "There are required steps or sources still without a holder. I acknowledge the pending items and want to finish anyway.",
  done: "Setup finished.",
  doneHint: "You can adjust any area later in AXON - Configuration.",
  stale: "A previous step was reopened — review the steps marked as outdated.",
  conflict:
    "The setup changed in another session. We reloaded the current state.",
  steps: {
    WELCOME_PREFS: "Welcome",
    PLUGGY_CREDENTIALS: "Pluggy credentials",
    PLUGGY_DISCOVERY: "Find accounts and cards",
    ACCOUNT_HOLDERS: "Source holders",
    PEOPLE_ACCESS: "People and access (optional)",
    MANUAL_SOURCES: "Accounts and cards without Pluggy (optional)",
    CURRENCY_PREF: "Display currency",
    REVIEW: "Review"
  },
  welcome:
    "Welcome. This setup is optional and can be resumed at any time — Axon is already installed for your family."
};
const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

export default class AxfLwcOnboardingWizard extends LightningElement {
  labels = L;
  authChecked = false;
  allowed = false;
  loading = true;
  @track state;
  current = "WELCOME_PREFS";
  message = null;
  acknowledge = false;
  busy = false;

  async connectedCallback() {
    this.allowed = (await canConfigure().catch(() => false)) === true;
    this.authChecked = true;
    if (this.allowed) {
      await this.refresh().catch((e) => {
        this.message = (e && e.body && e.body.message) || String(e);
      });
    }
    this.loading = false;
  }

  async refresh() {
    const s = await getState();
    this.applyState(s);
  }

  applyState(s) {
    this.state = s;
    if (s && s.forbidden) {
      this.allowed = false;
      return;
    }
    // resume where the server says we are (AC6)
    this.current = s.currentStep || "WELCOME_PREFS";
  }

  // ---- derived view ----
  get forbidden() {
    return this.authChecked && !this.allowed;
  }
  get version() {
    return this.state ? this.state.version : 0;
  }
  get onReview() {
    return this.current === "REVIEW";
  }
  get onDone() {
    return (
      this.current === "DONE" ||
      (this.state && this.state.status === "COMPLETED")
    );
  }
  get stepIndex() {
    const i = ORDER.indexOf(this.current);
    return i < 0 ? ORDER.length : i;
  }
  get stepNumberLabel() {
    return String(L.stepOf)
      .replace("{0}", Math.min(this.stepIndex + 1, ORDER.length + 1))
      .replace("{1}", ORDER.length + 1);
  }
  get stepTitle() {
    return L.steps[this.current] || this.current;
  }
  get nextLabel() {
    return this.busy ? L.working : L.next;
  }
  get stepperItems() {
    const keys = [...ORDER, "REVIEW"];
    const idx = this.stepIndex;
    return keys.map((k, i) => {
      const state = i < idx ? "done" : i === idx ? "current" : "upcoming";
      return {
        key: k,
        label: L.steps[k] || k,
        num: i + 1,
        isDone: state === "done",
        cssClass: `wizard__step wizard__step_${state}`
      };
    });
  }
  get isOptional() {
    return OPTIONAL.has(this.current);
  }
  get isFirst() {
    return this.stepIndex <= 0;
  }
  get staleDetected() {
    return this.state && this.state.staleDetected === true;
  }
  get stepRows() {
    if (!this.state || !this.state.steps) {
      return [];
    }
    return this.state.steps.map((st) => ({
      ...st,
      label: L.steps[st.stepKey] || st.stepKey,
      done: st.status === "CONFIRMED" || st.status === "SKIPPED",
      stale: st.status === "STALE",
      pending: st.status === "NOT_STARTED" || st.status === "RESULT_UNKNOWN"
    }));
  }
  get requiredPending() {
    return this.stepRows.some((r) => !r.optional && !r.done);
  }
  get showWelcome() {
    return this.current === "WELCOME_PREFS";
  }
  get showPluggyGuide() {
    return this.current === "PLUGGY_CREDENTIALS";
  }
  get showDiscovery() {
    return this.current === "PLUGGY_DISCOVERY";
  }
  get showHolders() {
    return this.current === "ACCOUNT_HOLDERS";
  }
  get showPeopleAccess() {
    return this.current === "PEOPLE_ACCESS";
  }
  get showManualSources() {
    return this.current === "MANUAL_SOURCES";
  }
  get showCurrency() {
    return this.current === "CURRENCY_PREF";
  }
  get finishDisabled() {
    return this.requiredPending && !this.acknowledge;
  }

  // ---- navigation ----
  handleAck(event) {
    this.acknowledge = event.target.checked;
  }

  async handleBack() {
    const i = this.stepIndex;
    if (i > 0) {
      this.current = ORDER[i - 1];
    } else if (this.onReview) {
      this.current = ORDER[ORDER.length - 1];
    }
    this.message = null;
  }

  async handleNext() {
    await this.advance("confirm");
  }

  async handleSkip() {
    await this.advance("skip");
  }

  async advance(mode) {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const key = this.current;
    try {
      const s =
        mode === "skip"
          ? await skipStep({ stepKey: key, expectedVersion: this.version })
          : await confirmStep({
              input: {
                stepKey: key,
                expectedVersion: this.version,
                evidenceRef: "wizard"
              }
            });
      if (s.outcome === "CONFLICT") {
        this.message = L.conflict;
        await this.refresh();
        return;
      }
      if (s.outcome === "INVALID" || s.outcome === "BLOCKED_UNKNOWN") {
        // minimal error DTO: no version/steps to apply, keep current state intact
        this.message = s.message;
        return;
      }
      this.applyState(s);
      this.message = s.staleDetected ? L.stale : null;
    } catch (e) {
      this.message = (e && e.body && e.body.message) || String(e);
    } finally {
      this.busy = false;
    }
  }

  async handleReopen(event) {
    const key = event.target.dataset.step;
    try {
      const s = await reopenStep({
        stepKey: key,
        expectedVersion: this.version
      });
      this.applyState(s);
      this.current = key;
    } catch (e) {
      this.message = (e && e.body && e.body.message) || String(e);
    }
  }

  async handleFinish() {
    try {
      const s = await complete({
        expectedVersion: this.version,
        acknowledgePending: this.acknowledge
      });
      if (s.outcome === "INVALID") {
        this.message = s.message;
        return;
      }
      this.applyState(s);
      this.current = "DONE";
    } catch (e) {
      this.message = (e && e.body && e.body.message) || String(e);
    }
  }
}
