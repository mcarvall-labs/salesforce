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
  "HOLDERS",
  "PLUGGY_CREDENTIALS",
  "PLUGGY_DISCOVERY",
  "ACCOUNT_HOLDERS",
  "PEOPLE_ACCESS",
  "MANUAL_SOURCES",
  "CURRENCY_PREF"
];
const OPTIONAL = new Set(["HOLDERS", "PEOPLE_ACCESS", "MANUAL_SOURCES"]);
// The stepper shows the eight ordered steps plus the review page.
const STEP_KEYS = [...ORDER, "REVIEW"];
const SETTLED = new Set(["CONFIRMED", "SKIPPED"]);

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
  guideOpen: "O que você vai fazer",
  guideClose: "Fechar guia",
  currentStepMark: "etapa atual",
  statuses: {
    CONFIRMED: "Concluída",
    SKIPPED: "Pulada",
    STALE: "Desatualizada — revise",
    NOT_STARTED: "Não iniciada",
    RESULT_UNKNOWN: "Resultado desconhecido"
  },
  steps: {
    WELCOME_PREFS: "Boas-vindas",
    HOLDERS: "Titulares (opcional)",
    PLUGGY_CREDENTIALS: "Credenciais Pluggy",
    PLUGGY_DISCOVERY: "Buscar contas e cartões",
    ACCOUNT_HOLDERS: "Titulares das fontes",
    PEOPLE_ACCESS: "Pessoas e acessos (opcional)",
    MANUAL_SOURCES: "Contas e cartões sem Pluggy (opcional)",
    CURRENCY_PREF: "Moeda de exibição",
    REVIEW: "Revisão"
  },
  welcome:
    "Bem-vindo. Esta configuração é opcional e pode ser retomada a qualquer momento — o Axon já está instalado para a sua família.",
  pluggyNotConfigured:
    "Configure e salve as credenciais da Pluggy para avançar."
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
  guideOpen: "What you are going to do",
  guideClose: "Close guide",
  currentStepMark: "current step",
  statuses: {
    CONFIRMED: "Completed",
    SKIPPED: "Skipped",
    STALE: "Outdated — review",
    NOT_STARTED: "Not started",
    RESULT_UNKNOWN: "Unknown result"
  },
  steps: {
    WELCOME_PREFS: "Welcome",
    HOLDERS: "Holders (optional)",
    PLUGGY_CREDENTIALS: "Pluggy credentials",
    PLUGGY_DISCOVERY: "Find accounts and cards",
    ACCOUNT_HOLDERS: "Source holders",
    PEOPLE_ACCESS: "People and access (optional)",
    MANUAL_SOURCES: "Accounts and cards without Pluggy (optional)",
    CURRENCY_PREF: "Display currency",
    REVIEW: "Review"
  },
  welcome:
    "Welcome. This setup is optional and can be resumed at any time — Axon is already installed for your family.",
  pluggyNotConfigured:
    "Configure and save the Pluggy credentials before proceeding."
};
const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

function visualState(isCurrent, isDone, isStale) {
  if (isCurrent) {
    return "current";
  }
  if (isDone) {
    return "done";
  }
  if (isStale) {
    return "stale";
  }
  return "upcoming";
}

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
  guideOpen = false;
  pluggyReady = false;

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
    this.guideOpen = false;
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
  // Position inside the stepper (which also carries the review page); -1 on DONE.
  get stepperIndex() {
    return STEP_KEYS.indexOf(this.current);
  }
  get stepStatusMap() {
    const map = {};
    const rows = (this.state && this.state.steps) || [];
    rows.forEach((row) => {
      map[row.stepKey] = row;
    });
    return map;
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
  get pluggyBlocked() {
    return this.current === "PLUGGY_CREDENTIALS" && !this.pluggyReady;
  }
  get nextDisabled() {
    if (this.busy) {
      return true;
    }
    if (this.pluggyBlocked) {
      return true;
    }
    return false;
  }
  get nextTitle() {
    if (this.pluggyBlocked) {
      return L.pluggyNotConfigured;
    }
    return "";
  }
  handlePluggyStatusChange(event) {
    this.pluggyReady = !!(event.detail && event.detail.hasActiveCredential);
  }
  get stepperItems() {
    const status = this.stepStatusMap;
    const settled = (key) => {
      const row = status[key];
      return !!row && SETTLED.has(row.status);
    };
    const idx = this.stepperIndex;
    const lead = "wizard__step-line wizard__step-line_leading";
    const trail = "wizard__step-line wizard__step-line_trailing";
    return STEP_KEYS.map((k, i) => {
      const row = status[k];
      const isDone = settled(k);
      const isStale = !!row && row.status === "STALE";
      const isCurrent = i === idx;
      const label = L.steps[k] || k;
      const statusLabel = L.statuses[row ? row.status : "NOT_STARTED"] ||
        (row ? row.status : "NOT_STARTED");
      return {
        key: k,
        label,
        num: i + 1,
        // The tick means "the server recorded this step as settled" (confirmed or
        // skipped) — never merely "we walked past it".
        isDone,
        isStale,
        statusLabel,
        tabIndex: "0",
        ariaCurrent: isCurrent ? "step" : null,
        ariaLabel: isCurrent
          ? `${i + 1}. ${label} — ${statusLabel} (${L.currentStepMark})`
          : `${i + 1}. ${label} — ${statusLabel}`,
        cssClass: `wizard__step wizard__step_${visualState(
          isCurrent,
          isDone,
          isStale
        )} wizard__step_navigable`,
        leadingClass:
          i > 0 && settled(STEP_KEYS[i - 1])
            ? `${lead} wizard__step-line_done`
            : lead,
        trailingClass: isDone ? `${trail} wizard__step-line_done` : trail
      };
    });
  }
  get isOptional() {
    return OPTIONAL.has(this.current);
  }
  get isFirst() {
    return this.stepperIndex <= 0;
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
  get showHoldersRegistration() {
    return this.current === "HOLDERS";
  }
  get showPluggyGuide() {
    return this.current === "PLUGGY_CREDENTIALS";
  }
  get showDiscovery() {
    return this.current === "PLUGGY_DISCOVERY";
  }
  get showGuideBar() {
    return (
      this.current === "PLUGGY_CREDENTIALS" ||
      this.current === "PLUGGY_DISCOVERY"
    );
  }
  get guidePhase() {
    return this.current === "PLUGGY_DISCOVERY" ? "discovery" : "credentials";
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

  // ---- pluggy guide dialog ----
  openGuide() {
    this.guideOpen = true;
  }
  closeGuide() {
    this.guideOpen = false;
    const btn = this.template.querySelector("[data-guide-open]");
    if (btn) {
      btn.focus();
    }
  }
  handleGuideBackdrop(event) {
    if (event.target === event.currentTarget) {
      this.closeGuide();
    }
  }
  handleGuideKeydown(event) {
    if (event.key === "Escape") {
      this.closeGuide();
    }
  }

  // ---- stepper navigation ----
  // Every step is clickable, forwards and backwards, so the administrator can look
  // ahead or go back without pressing Next/Back repeatedly. Jumping to a step only
  // moves the view: nothing is marked as done. A step shows the tick solely when the
  // server recorded it as settled (confirmed or skipped), so browsing ahead never
  // fakes progress, and "Finish setup" still validates the pending items.
  handleStepClick(event) {
    this.navigateToStep(event.currentTarget.dataset.step);
  }
  handleStepKeydown(event) {
    if (event.key === "Enter" || event.key === " " || event.key === "Spacebar") {
      event.preventDefault();
      this.navigateToStep(event.currentTarget.dataset.step);
    }
  }
  navigateToStep(key) {
    if (!key || key === this.current || STEP_KEYS.indexOf(key) < 0) {
      return;
    }
    this.current = key;
    this.message = null;
    this.guideOpen = false;
  }

  // ---- navigation ----
  handleAck(event) {
    this.acknowledge = event.target.checked;
  }

  async handleBack() {
    const i = this.stepperIndex;
    if (i > 0) {
      this.current = STEP_KEYS[i - 1];
    }
    this.message = null;
    this.guideOpen = false;
  }

  async handleNext() {
    if (this.nextDisabled) {
      return;
    }
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
              stepKey: key,
              expectedVersion: this.version,
              evidenceRef: "wizard"
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
      const position = STEP_KEYS.indexOf(key);
      this.applyState(s);
      // Confirming a step ahead of the pending order must not yank the view
      // backwards: the server resumes at the first unsettled step, which is correct
      // for the ordered flow but would undo an intentional forward jump.
      if (position >= 0 && STEP_KEYS.indexOf(this.current) < position) {
        this.current = STEP_KEYS[Math.min(position + 1, STEP_KEYS.length - 1)];
      }
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
