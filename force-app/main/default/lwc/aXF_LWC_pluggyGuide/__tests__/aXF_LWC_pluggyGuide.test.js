import { createElement } from "lwc";
import Guide from "c/aXF_LWC_pluggyGuide";
import { STEPS } from "../steps";

function build() {
  const el = createElement("c-a-x-f_-l-w-c_pluggy-guide", { is: Guide });
  document.body.appendChild(el);
  return el;
}

function flush() {
  return Promise.resolve();
}

const back = (el) => el.shadowRoot.querySelector('[data-nav="back"]');
const next = (el) => el.shadowRoot.querySelector('[data-nav="next"]');
const valueNow = (el) =>
  el.shadowRoot
    .querySelector("[role='progressbar']")
    .getAttribute("aria-valuenow");

async function advanceTo(el, predicate) {
  const target = STEPS.findIndex(predicate);
  for (let i = 0; i < target; i++) {
    next(el).click();
    // eslint-disable-next-line no-await-in-loop
    await flush();
  }
  return target;
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
});

describe("c-aXF_LWC_pluggyGuide", () => {
  it("starts on step 1 with Back disabled and a labelled progressbar", () => {
    const el = build();
    expect(
      el.shadowRoot.querySelector("[data-step-heading]").textContent.trim()
        .length
    ).toBeGreaterThan(0);

    const pb = el.shadowRoot.querySelector("[role='progressbar']");
    expect(pb.getAttribute("aria-valuenow")).toBe("1");
    expect(pb.getAttribute("aria-valuemax")).toBe(String(STEPS.length));
    expect(pb.getAttribute("aria-label")).toMatch(/\d/);

    expect(back(el).disabled).toBe(true);
  });

  it("walks forward through every step and back one", async () => {
    const el = build();
    for (let i = 2; i <= STEPS.length; i++) {
      next(el).click();
      // eslint-disable-next-line no-await-in-loop
      await flush();
      expect(valueNow(el)).toBe(String(i));
    }
    expect(next(el).dataset.last).toBe("true");

    back(el).click();
    await flush();
    expect(valueNow(el)).toBe(String(STEPS.length - 1));
    expect(next(el).dataset.last).toBe("false");
  });

  it("fires guidecomplete on Finish with an instructional-only detail", async () => {
    const el = build();
    const handler = jest.fn();
    el.addEventListener("guidecomplete", handler);

    for (let i = 1; i < STEPS.length; i++) {
      next(el).click();
      // eslint-disable-next-line no-await-in-loop
      await flush();
    }
    next(el).click();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      instructionalOnly: true
    });
  });

  it("fires opensecureform from the credentials step action", async () => {
    const el = build();
    const handler = jest.fn();
    el.addEventListener("opensecureform", handler);

    await advanceTo(el, (s) => s.action === "openSecureForm");
    const actionBtn = el.shadowRoot.querySelector(".guide__action");
    expect(actionBtn).not.toBeNull();
    actionBtn.click();
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it("toggles the on-demand help panel", async () => {
    const el = build();
    await advanceTo(el, (s) => s.help);

    const toggle = () => el.shadowRoot.querySelector(".guide__help-toggle");
    expect(toggle().getAttribute("aria-expanded")).toBe("false");
    expect(el.shadowRoot.querySelector(".guide__help-list")).toBeNull();

    toggle().click();
    await flush();
    expect(toggle().getAttribute("aria-expanded")).toBe("true");
    expect(el.shadowRoot.querySelector(".guide__help-list")).not.toBeNull();
  });

  it("does not autoplay the animation and exposes Play/Replay", async () => {
    const el = build();
    await advanceTo(el, (s) => s.animation);

    const controls = [...el.shadowRoot.querySelectorAll(".guide__anim-btn")];
    expect(controls).toHaveLength(2);
    expect(controls[0].getAttribute("aria-pressed")).toBe("false");

    controls[0].click();
    await flush();
    expect(
      el.shadowRoot
        .querySelector(".guide__anim-btn")
        .getAttribute("aria-pressed")
    ).toBe("true");
  });

  it("resets animation playing state when leaving the step", async () => {
    const el = build();
    await advanceTo(el, (s) => s.animation);
    el.shadowRoot.querySelector(".guide__anim-btn").click();
    await flush();

    back(el).click();
    await flush();
    next(el).click();
    await flush();

    expect(
      el.shadowRoot
        .querySelector(".guide__anim-btn")
        .getAttribute("aria-pressed")
    ).toBe("false");
  });

  it("renders official external links that open in a new tab safely", async () => {
    const el = build();
    next(el).click();
    await flush();

    const link = el.shadowRoot.querySelector("a.guide__link");
    expect(link.getAttribute("href")).toMatch(/^https:\/\//);
    expect(link.getAttribute("target")).toBe("_blank");
    expect(link.getAttribute("rel")).toContain("noopener");
  });
});
