import { LightningElement, track } from "lwc";
import LANG from "@salesforce/i18n/lang";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.canConfigure";
import getState from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.getState";
import confirmStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.confirmStep";
import skipStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.skipStep";
import reopenStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.reopenStep";
import complete from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.complete";
import getOverview from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.getOverview";

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
    "Configure e salve as credenciais da Pluggy para avançar.",
  holdersResolved:
    "Todas as fontes descobertas já têm titular confirmado. Nada a resolver nesta etapa."
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
    "Configure and save the Pluggy credentials before proceeding.",
  holdersResolved:
    "Every discovered source already has a confirmed holder. Nothing to resolve on this step."
};
const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

/**
 * The overview payload is only a decision input when it really carries the lists the
 * verdict is made of. A null payload, a payload without them, or a refusal is an UNKNOWN:
 * it never means "there is nothing to resolve" (AXF-106).
 */
function isHolderOverview(overview) {
  return (
    !!overview &&
    typeof overview === "object" &&
    Array.isArray(overview.pending) &&
    Array.isArray(overview.divergent)
  );
}

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
  // AXF-106 — the source-holder step is only presented when it has something to resolve.
  holdersOverview = null;
  // A KNOWN, readable answer. A failed, refused or shape-less read stays false, which keeps
  // the step visible and settles nothing.
  holdersChecked = false;
  holdersSettling = false;
  // Set when a settle attempt was refused (conflict/invalid/unknown/error): the step stays
  // visible until an attempt really settles it.
  holdersUnsettled = false;
  // Bumped on every intentional move of the view: a verdict still in flight belongs to the
  // step the administrator already left and must never move the reader back (AXF-106).
  navEpoch = 0;

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
    // Read the holder truth BEFORE presenting the step, so advancing past discovery
    // never flashes the confirmation surface (AXF-106).
    await this.refreshHolderOverview();
    await this.maybeSettleHoldersStep();
    this.ensureCurrentVisible();
  }

  applyState(s) {
    this.state = s;
    if (s && s.forbidden) {
      this.allowed = false;
      return;
    }
    // resume where the server says we are (AC6)
    this.setCurrent(s.currentStep || "WELCOME_PREFS");
    this.guideOpen = false;
  }

  /** The single place `current` moves, so the view has one source of truth. */
  setCurrent(key) {
    this.current = key;
  }

  /** Any intentional move of the view (AXF-106). */
  bumpNav() {
    this.navEpoch += 1;
  }

  /**
   * The step body, the stepper and `current` are one decision (AXF-106): a step that is not
   * in the visible sequence is never the current step — the reader moves to the next visible
   * one, so "Etapa N de M" and the highlighted step keep describing what is on the screen.
   */
  ensureCurrentVisible() {
    const keys = this.visibleStepKeys;
    const at = STEP_KEYS.indexOf(this.current);
    if (at < 0 || keys.indexOf(this.current) >= 0) {
      return;
    }
    for (let i = at + 1; i < STEP_KEYS.length; i += 1) {
      if (keys.indexOf(STEP_KEYS[i]) >= 0) {
        this.setCurrent(STEP_KEYS[i]);
        return;
      }
    }
    for (let i = at - 1; i >= 0; i -= 1) {
      if (keys.indexOf(STEP_KEYS[i]) >= 0) {
        this.setCurrent(STEP_KEYS[i]);
        return;
      }
    }
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
  // ---- AXF-106: the holder step is only presented when it has something to resolve ----
  // `visibleStepKeys` is what the stepper and the navigation use. The step is dropped
  // only once discovery is settled, the server recorded the step itself as settled AND the
  // overview is KNOWN-clean: before discovery the step has no sources to look at yet, and
  // an unreadable, shape-less or forbidden read is an unknown — neither hides it, so the
  // administrator never loses the accessible way to resolve the sources. The persisted
  // catalogue (ALT_CLS_AxonOnboardingProgress) always keeps the step, so a resumed session
  // still finds it.
  get discoverySettled() {
    const row = this.stepStatusMap.PLUGGY_DISCOVERY;
    return !!row && SETTLED.has(row.status);
  }
  get holdersStepSettled() {
    const row = this.stepStatusMap.ACCOUNT_HOLDERS;
    return !!row && SETTLED.has(row.status);
  }
  get holdersStepHidden() {
    // Dropped only when discovery is settled, the answer is KNOWN-clean, the last settle
    // attempt was not refused (AXF-106) and the server really recorded the step as settled:
    // a step that is merely clean is never taken away while its catalogue row is still
    // pending, or the administrator would have no way to reach it and still be asked to
    // acknowledge it at the end.
    return (
      this.discoverySettled &&
      this.holdersChecked &&
      !this.holdersNeedsAttention &&
      !this.holdersUnsettled &&
      this.holdersStepSettled
    );
  }
  get visibleOrder() {
    return this.holdersStepHidden
      ? ORDER.filter((k) => k !== "ACCOUNT_HOLDERS")
      : ORDER;
  }
  get visibleStepKeys() {
    return this.holdersStepHidden
      ? STEP_KEYS.filter((k) => k !== "ACCOUNT_HOLDERS")
      : STEP_KEYS;
  }
  get stepIndex() {
    const i = this.visibleOrder.indexOf(this.current);
    return i < 0 ? this.visibleOrder.length : i;
  }
  // Position inside the stepper (which also carries the review page); -1 on DONE.
  get stepperIndex() {
    return this.visibleStepKeys.indexOf(this.current);
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
      .replace(
        "{0}",
        Math.min(this.stepIndex + 1, this.visibleOrder.length + 1)
      )
      .replace("{1}", this.visibleOrder.length + 1);
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
    const keys = this.visibleStepKeys;
    const lead = "wizard__step-line wizard__step-line_leading";
    const trail = "wizard__step-line wizard__step-line_trailing";
    return keys.map((k, i) => {
      const row = status[k];
      const isDone = settled(k);
      const isStale = !!row && row.status === "STALE";
      const isCurrent = i === idx;
      const label = L.steps[k] || k;
      const statusLabel =
        L.statuses[row ? row.status : "NOT_STARTED"] ||
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
          i > 0 && settled(keys[i - 1])
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
  // The truth of the step is the server-side overview, never a client guess: pending
  // sources or a holder diverging from the connection keep the step visible.
  get holdersNeedsAttention() {
    const o = this.holdersOverview || {};
    return (o.pending || []).length + (o.divergent || []).length > 0;
  }
  get holdersResolved() {
    // "Nothing to resolve" is only claimable on a KNOWN-clean answer that was not left
    // unsettled by a refused settle (AXF-106).
    return (
      this.holdersChecked &&
      !this.holdersNeedsAttention &&
      !this.holdersUnsettled
    );
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
    if (
      event.key === "Enter" ||
      event.key === " " ||
      event.key === "Spacebar"
    ) {
      event.preventDefault();
      this.navigateToStep(event.currentTarget.dataset.step);
    }
  }
  navigateToStep(key) {
    if (!key || key === this.current || this.visibleStepKeys.indexOf(key) < 0) {
      return;
    }
    this.setCurrent(key);
    this.bumpNav();
    this.message = null;
    this.guideOpen = false;
    // Re-entering the holder step re-evaluates it: what the administrator did elsewhere
    // (or another session did meanwhile) must be seen before it is settled or hidden.
    if (key === "ACCOUNT_HOLDERS") {
      this.checkHoldersStep();
    }
  }

  // ---- navigation ----
  handleAck(event) {
    this.acknowledge = event.target.checked;
  }

  // ---- source holders (AXF-106) ----
  /**
   * Reads the server-side holder overview — the only truth about whether the holder step
   * has something to resolve. A failed or forbidden read, and a payload that does not carry
   * the expected lists, stay "unknown": the step remains visible and is never settled
   * (fail-safe, AXF-106).
   */
  async refreshHolderOverview() {
    try {
      const overview = await getOverview();
      const known = isHolderOverview(overview) && overview.forbidden !== true;
      this.holdersOverview = known ? overview : null;
      this.holdersChecked = known;
    } catch {
      this.holdersOverview = null;
      this.holdersChecked = false;
    }
  }

  /**
   * `navigateToStep` is synchronous, so the settle it triggers is observed through a guard:
   * a rejected promise is surfaced as the step's message instead of escaping as an
   * unhandled rejection, and the step is never hidden on an unknown (AXF-106).
   */
  checkHoldersStep() {
    Promise.resolve(this.maybeSettleHoldersStep()).catch((e) => {
      this.holdersUnsettled = true;
      this.holdersChecked = false;
      this.holdersOverview = null;
      this.message = (e && e.body && e.body.message) || String(e);
    });
  }

  /**
   * The confirmation step only exists when there is something to resolve. Reaching it
   * with no pending source and no divergence settles it with confirmStep — never
   * skipStep, so the persisted catalogue keeps a truthful record and a resumed session
   * still finds the step.
   */
  async maybeSettleHoldersStep() {
    if (this.current !== "ACCOUNT_HOLDERS" || this.holdersSettling) {
      return;
    }
    // The verdict belongs to the step the administrator is on RIGHT NOW: every await is
    // checked against the navigation epoch, so a late response never drags the reader to
    // another step and never settles a step that was already left (AXF-106).
    const epoch = this.navEpoch;
    const superseded = () =>
      epoch !== this.navEpoch || this.current !== "ACCOUNT_HOLDERS";
    // The verdict is never taken from a payload read earlier in the session: the overview
    // is re-read from the server right before deciding, so a source confirmed, released
    // or diverging in the meantime cannot be settled away on a cached answer.
    await this.refreshHolderOverview();
    if (superseded()) {
      return;
    }
    if (!this.holdersChecked || this.holdersNeedsAttention) {
      // unknown result, forbidden, or something to resolve: the step stays
      return;
    }
    this.holdersSettling = true;
    // A fresh attempt: the step may be hidden again if this one really settles it.
    this.holdersUnsettled = false;
    try {
      const s = await confirmStep({
        stepKey: "ACCOUNT_HOLDERS",
        expectedVersion: this.version,
        evidenceRef: "wizard"
      });
      if (superseded()) {
        return;
      }
      if (s.outcome === "CONFLICT") {
        // The step is never hidden on a conflict: the message is surfaced and the
        // administrator keeps the surface where the sources are resolved.
        this.holdersUnsettled = true;
        this.message = L.conflict;
        await this.refresh();
        return;
      }
      if (s.outcome === "INVALID" || s.outcome === "BLOCKED_UNKNOWN") {
        this.holdersUnsettled = true;
        this.message = s.message;
        return;
      }
      this.applyState(s);
      this.message = s.staleDetected ? L.stale : null;
      this.ensureCurrentVisible();
    } catch (e) {
      // show the step rather than hiding it on an unknown
      this.holdersUnsettled = true;
      this.holdersChecked = false;
      this.holdersOverview = null;
      this.message = (e && e.body && e.body.message) || String(e);
    } finally {
      this.holdersSettling = false;
    }
  }

  async handleBack() {
    const keys = this.visibleStepKeys;
    const i = this.stepperIndex;
    if (i > 0) {
      this.setCurrent(keys[i - 1]);
      this.bumpNav();
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
    this.bumpNav();
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
      this.applyState(s);
      // AXF-106 — leaving discovery is what gives the holder step something to resolve:
      // the overview is read again HERE, after the discovery ran, so the visibility of the
      // step, the settle and the resulting position all come from a fresh answer instead
      // of one taken before the discovery.
      if (key === "PLUGGY_DISCOVERY") {
        await this.refreshHolderOverview();
      }
      const position = this.visibleStepKeys.indexOf(key);
      this.message = s.staleDetected ? L.stale : null;
      // Confirming a step ahead of the pending order must not yank the view
      // backwards: the server resumes at the first unsettled step, which is correct
      // for the ordered flow but would undo an intentional forward jump. The holder
      // step is skipped here when it has nothing to resolve, so it never appears.
      await this.maybeSettleHoldersStep();
      this.ensureCurrentVisible();
      const visible = this.visibleStepKeys;
      if (position >= 0 && visible.indexOf(this.current) < position) {
        this.setCurrent(visible[Math.min(position + 1, visible.length - 1)]);
      }
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
      this.setCurrent(key);
      this.bumpNav();
      // Reopening the holder step must re-read the overview too: the previous verdict was
      // taken before the administrator came back to fix the sources.
      if (key === "ACCOUNT_HOLDERS") {
        await this.maybeSettleHoldersStep();
        this.ensureCurrentVisible();
      }
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
      this.setCurrent("DONE");
      this.bumpNav();
    } catch (e) {
      this.message = (e && e.body && e.body.message) || String(e);
    }
  }
}
