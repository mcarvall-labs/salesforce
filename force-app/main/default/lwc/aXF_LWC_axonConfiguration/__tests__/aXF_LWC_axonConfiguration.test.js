import { createElement } from "lwc";
import Cmp from "c/aXF_LWC_axonConfiguration";
import access from "@salesforce/apex/AXF_CLS_CTRL_AxonConfig.access";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_AxonConfig.access",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function build() {
  const el = createElement("c-config", { is: Cmp });
  document.body.appendChild(el);
  return el;
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_axonConfiguration", () => {
  it("shows only the currency area for a standard user", async () => {
    access.mockResolvedValue({ canConfigure: false, canSetCurrency: true });
    const el = build();
    await flush();
    const tiles = el.shadowRoot.querySelectorAll("button[data-area]");
    expect(tiles.length).toBe(1);
    expect(tiles[0].dataset.area).toBe("CURRENCY");
  });

  it("shows every area for a configurator and opens one", async () => {
    access.mockResolvedValue({ canConfigure: true, canSetCurrency: true });
    const el = build();
    await flush();
    const tiles = el.shadowRoot.querySelectorAll("button[data-area]");
    expect(tiles.length).toBe(10);

    [...tiles].find((t) => t.dataset.area === "PLUGGY").click();
    await flush();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_pluggy-integration-config")
    ).not.toBeNull();

    el.shadowRoot
      .querySelector("lightning-button")
      .dispatchEvent(new CustomEvent("click"));
    // back button is a lightning-button; simulate via handler
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(el.shadowRoot.querySelectorAll("button[data-area]").length).toBe(10);
  });
});
