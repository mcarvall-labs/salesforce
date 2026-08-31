import { LightningElement, track } from "lwc";
import GUIDE_MEDIA from "@salesforce/resourceUrl/AXF_pluggyGuideMedia";
import L from "./labels";
import { STEPS, OFFICIAL_LINKS } from "./steps";

/**
 * Pluggy setup mini-wizard (AXF-89). Instructional only — no server calls,
 * no persistence, no side effects (AC7). One action per step (AC1), compact
 * layout (AC9).
 *
 * Media (AC5): each tutorial step shows an anonymised MP4 demonstration
 * (muted, looping, native controls, poster frame as the static alternative,
 * written steps as the textual alternative). It never autoplays under
 * `prefers-reduced-motion`, and leaving a step unmounts and stops it.
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

  renderedCallback() {
    const video = this.template.querySelector("video.guide__video");
    if (!video) {
      return;
    }
    if (this.reducedMotion) {
      video.pause();
    } else if (video.paused && !video.dataset.userPaused) {
      video.play().catch(() => {
        /* autoplay blocked — the user can start it with the controls */
      });
    }
  }

  disconnectedCallback() {
    const video = this.template.querySelector("video.guide__video");
    if (video) {
      video.pause();
    }
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
    return Boolean(this.step.media);
  }
  get videoSrc() {
    return this.step.media ? `${GUIDE_MEDIA}/${this.step.media}.mp4` : null;
  }
  get posterSrc() {
    return this.step.media
      ? `${GUIDE_MEDIA}/${this.step.media}-poster.png`
      : null;
  }
  get mediaAlt() {
    return this.content.mediaAlt || "";
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
  get showReducedMotionNote() {
    return this.hasMedia && this.reducedMotion;
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

  handleVideoPause(event) {
    // Remember an explicit pause so we don't fight the user on re-render.
    if (event.target.currentTime > 0 && !event.target.ended) {
      event.target.dataset.userPaused = "true";
    }
  }

  handleVideoPlay(event) {
    delete event.target.dataset.userPaused;
  }

  toggleHelp() {
    this.helpOpen = !this.helpOpen;
  }

  goTo(next) {
    const video = this.template.querySelector("video.guide__video");
    if (video) {
      video.pause();
    }
    this.index = next;
    this.helpOpen = false;
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
