import { LightningElement, track } from "lwc";
import L from "./labels";
import { STEPS, OFFICIAL_LINKS } from "./steps";

/**
 * Pluggy setup mini-wizard (AXF-89). Instructional only — no server calls,
 * no persistence, no side effects (AC7). One action per step (AC1), compact
 * layout (AC9), accessible animation with a static/text alternative (AC5).
 *
 * Events:
 *  - `guidecomplete` — fired on Finish; the parent onboarding wizard (AXF-90)
 *    returns the user to the main flow. Carries no "connected/valid" claim.
 *  - `opensecureform` — fired from the credentials step; the parent routes to
 *    the AXF-11 secure credentials form.
 */
export default class AxfLwcPluggyGuide extends LightningElement {
  chrome = L.chrome;
  index = 0;
  @track helpOpen = false;
  animationPlaying = false;
  reducedMotion = false;

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
  }

  replay() {
    this.animationPlaying = false;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      this.animationPlaying = true;
    });
  }

  goTo(next) {
    this.index = next;
    this.helpOpen = false;
    this.animationPlaying = false; // leaving a step stops its animation (AC9)
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
