import { createElement } from "lwc";
import FinancialEntities from "c/aXF_LWC_financialEntities";
import listEntities from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.listEntities";
import createEntity from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.createEntity";
import updateEntity from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.updateEntity";
import readEntity from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.readEntity";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.listEntities",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.createEntity",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.updateEntity",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.readEntity",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

describe("c-a-x-f_-l-w-c_financial-entities", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });
  it("does not render denied entity data", async () => {
    listEntities.mockResolvedValue({
      state: "FORBIDDEN",
      entities: [{ displayName: "Secret" }]
    });
    const element = createElement("c-a-x-f_-l-w-c_financial-entities", {
      is: FinancialEntities
    });
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "Não foi possível acessar"
    );
    expect(element.shadowRoot.textContent).not.toContain("Secret");
  });
  it("renders an explicit empty state", async () => {
    listEntities.mockResolvedValue({ state: "READY_EMPTY", entities: [] });
    const element = createElement("c-a-x-f_-l-w-c_financial-entities", {
      is: FinancialEntities
    });
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.textContent).toContain("Nenhuma entidade");
  });
  it("creates an entity with independent legal and display names", async () => {
    listEntities.mockResolvedValue({ state: "READY_EMPTY", entities: [] });
    createEntity.mockResolvedValue({ entityRef: "ref" });
    const element = createElement("c-a-x-f_-l-w-c_financial-entities", {
      is: FinancialEntities
    });
    element.householdId = "a00000000000001";
    document.body.appendChild(element);
    await flush();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    const form = element.shadowRoot.querySelector(
      'form[aria-label="Criar entidade financeira"]'
    );
    const fields = form.querySelectorAll("lightning-input");
    fields[0].dispatchEvent(
      new CustomEvent("change", { detail: { value: "Legal Name" } })
    );
    fields[1].dispatchEvent(
      new CustomEvent("change", { detail: { value: "Display Name" } })
    );
    form.dispatchEvent(new CustomEvent("submit"));
    await flush();
    expect(createEntity).toHaveBeenCalledWith(
      expect.objectContaining({
        request: expect.objectContaining({
          legalName: "Legal Name",
          displayName: "Display Name"
        })
      })
    );
  });
  it("sends legalName and activeTo when closing", async () => {
    listEntities.mockResolvedValue({
      state: "READY_DATA",
      entities: [{ entityRef: "ref", displayName: "Display" }]
    });
    readEntity.mockResolvedValue({
      state: "READY_DATA",
      detail: {
        entityRef: "ref",
        displayName: "Display",
        legalName: "Legal",
        lifecycle: "CLOSED",
        activeTo: "2026-08-25",
        version: 1
      }
    });
    updateEntity.mockResolvedValue({
      entityRef: "ref",
      lifecycle: "CLOSED",
      version: 2
    });
    const element = createElement("c-a-x-f_-l-w-c_financial-entities", {
      is: FinancialEntities
    });
    document.body.appendChild(element);
    await flush();
    element.shadowRoot.querySelector("button.entity").click();
    await flush();
    const inputs = element.shadowRoot.querySelectorAll("lightning-input");
    inputs[0].dispatchEvent(
      new CustomEvent("change", { detail: { value: "Legal Updated" } })
    );
    const date = element.shadowRoot.querySelectorAll("lightning-input")[2];
    expect(date).not.toBeNull();
    date.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "2026-08-26" },
        bubbles: true,
        composed: true
      })
    );
    element.shadowRoot
      .querySelector("form")
      .dispatchEvent(new CustomEvent("submit"));
    await flush();
    expect(updateEntity).toHaveBeenCalledWith(
      expect.objectContaining({
        request: expect.objectContaining({
          legalName: "Legal Updated",
          lifecycle: "CLOSED",
          activeTo: "2026-08-26"
        })
      })
    );
  });
  it("does not expose a legal-name editor when detail policy omits it", async () => {
    listEntities.mockResolvedValue({
      state: "READY_DATA",
      entities: [{ entityRef: "ref", displayName: "Display" }]
    });
    readEntity.mockResolvedValue({
      state: "READY_DATA",
      detail: {
        entityRef: "ref",
        displayName: "Display",
        lifecycle: "ACTIVE",
        version: 1
      }
    });
    const element = createElement("c-a-x-f_-l-w-c_financial-entities", {
      is: FinancialEntities
    });
    document.body.appendChild(element);
    await flush();
    element.shadowRoot.querySelector("button.entity").click();
    await flush();
    expect(element.shadowRoot.querySelectorAll("lightning-input")).toHaveLength(
      1
    );
    expect(element.shadowRoot.textContent).not.toContain("Nome legal");
  });
  it("renders terminal errors explicitly", async () => {
    listEntities.mockResolvedValue({ state: "ERROR_TERMINAL", entities: [] });
    const element = createElement("c-a-x-f_-l-w-c_financial-entities", {
      is: FinancialEntities
    });
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.textContent).toContain("erro terminal");
  });
});
