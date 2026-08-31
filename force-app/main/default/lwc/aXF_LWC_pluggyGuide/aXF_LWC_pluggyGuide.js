import { LightningElement, track } from "lwc";
import L from "./labels";
import { STEPS, OFFICIAL_LINKS } from "./steps";

/**
 * Pluggy setup mini-wizard (AXF-89). Instructional only — no server calls,
 * no persistence, no side effects (AC7). One action per step (AC1), compact
 * layout (AC9), accessible schematic figures with a static/text alternative
 * and an optional non-autoplaying highlight animation (AC5).
 *
 * Events:
 *  - `guidecomplete` — fired on Finish; the parent onboarding wizard (AXF-90)
 *    returns the user to the main flow. Carries no "connected/valid" claim.
 *  - `opensecureform` — fired from the credentials step; the parent routes to
 *    the AXF-11 secure credentials form.
 */
const ROW_TOP = 48;
const ROW_GAP = 30;
const FIGURE_WIDTH = 320;
const HIGHLIGHT_MS = 1400;

export default class AxfLwcPluggyGuide extends LightningElement {
  chrome = L.chrome;
  index = 0;
  @track helpOpen = false;
  animationPlaying = false;
  reducedMotion = false;
  activeControl = 0;
  _timer;

  connectedCallback() {
    this.reducedMotion = this.prefersReducedMotion();
  }

  prefersReducedMotion() {
    const mq =
      typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-reduced-motion: reduce)");
    return Boolean(mq && mq.matches);
  }

  disconnectedCallback() {
    this.animationPlaying = false;
    this.stopHighlight();
  }

  // ---- step model ----
  get step() {
    return STEPS[this.index];
  }
  get content() {
    return L.steps[this.step.id];
  }
  get total() {
    return STEPS.length;
  }
  get humanIndex() {
    return this.index + 1;
  }
  get progressLabel() {
    return this.format(this.chrome.stepOf, this.humanIndex, this.total);
  }
  get progressPercent() {
    return Math.round((this.humanIndex / this.total) * 100);
  }
  get progressStyle() {
    return `width:${this.progressPercent}%`;
  }
  get bodyParagraphs() {
    return (this.content.body || []).map((text, i) => ({ key: i, text }));
  }
  get helpParagraphs() {
    return (this.content.help || []).map((text, i) => ({ key: i, text }));
  }
  get hasHelp() {
    return Boolean(this.step.help && (this.content.help || []).length);
  }
  get hasMedia() {
    return this.step.media === true;
  }
  get hasAnimation() {
    return this.step.animation === true;
  }
  get mediaAlt() {
    return this.content.mediaAlt || this.chrome.mediaPlaceholder;
  }
  get officialLink() {
    return this.step.link ? OFFICIAL_LINKS[this.step.link] : null;
  }
  get hasAction() {
    return Boolean(this.step.action);
  }
  get actionLabel() {
    return this.content.action;
  }

  // ---- schematic figure ----
  get figure() {
    return this.step.figure || null;
  }
  get figureWindow() {
    return this.figure ? this.figure.window : "";
  }
  get isHighlighting() {
    return this.hasAnimation && this.animationPlaying && !this.reducedMotion;
  }
  get figureControls() {
    if (!this.figure) {
      return [];
    }
    return this.figure.controls.map((label, i) => ({
      key: i,
      n: i + 1,
      label,
      y: ROW_TOP + i * ROW_GAP,
      midY: ROW_TOP + i * ROW_GAP + 11,
      chipClass:
        this.isHighlighting && i === this.activeControl
          ? "guide__chip guide__chip_active"
          : "guide__chip"
    }));
  }
  get figureViewBox() {
    const rows = this.figure ? this.figure.controls.length : 0;
    return `0 0 ${FIGURE_WIDTH} ${ROW_TOP + rows * ROW_GAP + 8}`;
  }

  // ---- navigation state ----
  get isFirst() {
    return this.index === 0;
  }
  get isLast() {
    return this.index === STEPS.length - 1;
  }
  get nextLabel() {
    return this.isLast ? this.chrome.finish : this.chrome.next;
  }
  get helpToggleLabel() {
    return this.helpOpen ? this.chrome.closeHelp : this.chrome.openHelp;
  }

  // ---- animation state ----
  get playPauseLabel() {
    return this.animationPlaying ? this.chrome.pause : this.chrome.play;
  }
  get showReducedMotionNote() {
    return this.hasAnimation && this.reducedMotion;
  }

  // ---- actions ----
  handleBack() {
    if (!this.isFirst) {
      this.goTo(this.index - 1);
    }
  }

  handleNext() {
    if (this.isLast) {
      this.dispatchEvent(
        new CustomEvent("guidecomplete", {
          detail: { instructionalOnly: true }
        })
      );
      return;
    }
    this.goTo(this.index + 1);
  }

  handleAction() {
    if (this.step.action === "openSecureForm") {
      this.dispatchEvent(
        new CustomEvent("opensecureform", { detail: { source: "pluggyGuide" } })
      );
    }
  }

  toggleHelp() {
    this.helpOpen = !this.helpOpen;
  }

  togglePlay() {
    this.animationPlaying = !this.animationPlaying;
    if (this.animationPlaying) {
      this.startHighlight();
    } else {
      this.stopHighlight();
    }
  }

  replay() {
    this.stopHighlight();
    this.animationPlaying = true;
    this.startHighlight();
  }

  startHighlight() {
    this.stopHighlight();
    if (this.reducedMotion || !this.figure) {
      return;
    }
    this.activeControl = 0;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._timer = setInterval(() => {
      const count = this.figure ? this.figure.controls.length : 1;
      this.activeControl = (this.activeControl + 1) % count;
    }, HIGHLIGHT_MS);
  }

  stopHighlight() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = undefined;
    }
    this.activeControl = 0;
  }

  goTo(next) {
    this.index = next;
    this.helpOpen = false;
    this.animationPlaying = false; // leaving a step stops its animation (AC9)
    this.stopHighlight();
    this.focusHeading();
  }

  focusHeading() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const h = this.template.querySelector("[data-step-heading]");
      if (h) {
        h.focus();
      }
    });
  }

  format(template, ...args) {
    return String(template).replace(/\{(\d+)\}/g, (match, i) => {
      return args[i] === undefined ? match : args[i];
    });
  }
}
