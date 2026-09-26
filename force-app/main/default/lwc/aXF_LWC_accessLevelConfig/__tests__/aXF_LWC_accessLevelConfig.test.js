import { createElement } from "lwc";
import AccessLevelConfig from "c/aXF_LWC_accessLevelConfig";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.canConfigure";
import getEligibleUsers from "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.getEligibleUsers";
import applyAccessLevel from "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.applyAccessLevel";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.canConfigure",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.getEligibleUsers",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_AccessLevelConfig.applyAccessLevel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const USERS = [
  {
    userId: "005000000000001",
    name: "Ana Gestora",
    username: "ana@axon.test",
    isActive: true,
    currentLevel: "Gestor Financeiro"
  },
  {
    userId: "005000000000002",
    name: "Bruno Sem Acesso",
    username: "bruno@axon.test",
    isActive: true,
    currentLevel: null
  }
];

function flush() {
  return Promise.resolve();
}

function build() {
  const el = createElement("c-a-x-f_-l-w-c_access-level-config", {
    is: AccessLevelConfig
  });
  document.body.appendChild(el);
  return el;
}

const datatable = (el) => el.shadowRoot.querySelector("lightning-datatable");
const combobox = (el) => el.shadowRoot.querySelector("lightning-combobox");
const feedbackText = (el) => {
  const wrapper = el.shadowRoot.querySelector("[aria-live='polite']");
  if (!wrapper) {
    return null;
  }
  const formatted = wrapper.querySelector("lightning-formatted-text");
  return formatted ? formatted.value : wrapper.textContent;
};
const applyButton = (el) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
    /Aplicar/.test(b.label)
  );

async function selectUserAndLevel(el, userId, level) {
  datatable(el).dispatchEvent(
    new CustomEvent("rowselection", {
      detail: { selectedRows: [{ userId }] }
    })
  );
  await flush();
  combobox(el).dispatchEvent(
    new CustomEvent("change", { detail: { value: level } })
  );
  await flush();
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_accessLevelConfig", () => {
  it("shows a spinner before any wire resolves", () => {
    const el = build();
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();
  });

  it("renders the FORBIDDEN message when the caller cannot configure", async () => {
    const el = build();
    canConfigure.emit(false);
    getEligibleUsers.emit([]);
    await flush();

    const status = el.shadowRoot.querySelector("[role='status']");
    expect(status).not.toBeNull();
    expect(status.textContent).toMatch(/não tem autorização/i);
    expect(datatable(el)).toBeNull();
  });

  it("stays FORBIDDEN even if a user list also arrives", async () => {
    const el = build();
    canConfigure.emit(false);
    getEligibleUsers.emit(USERS);
    await flush();

    expect(datatable(el)).toBeNull();
    expect(el.shadowRoot.querySelector("[role='status']").textContent).toMatch(
      /não tem autorização/i
    );
  });

  it("renders the empty state when authorized with no eligible users", async () => {
    const el = build();
    canConfigure.emit(true);
    getEligibleUsers.emit([]);
    await flush();

    expect(datatable(el)).toBeNull();
    expect(el.shadowRoot.querySelector("[role='status']").textContent).toMatch(
      /Nenhum usuário elegível/i
    );
  });

  it("lists the eligible users when authorized", async () => {
    const el = build();
    canConfigure.emit(true);
    getEligibleUsers.emit(USERS);
    await flush();

    const table = datatable(el);
    expect(table).not.toBeNull();
    expect(table.data).toHaveLength(2);
    // null currentLevel is normalised to the "no access" label
    expect(table.data[1].currentLevel).toBe("Sem acesso ao Axon");
  });

  it("keeps Apply disabled until both a user and a level are chosen", async () => {
    const el = build();
    canConfigure.emit(true);
    getEligibleUsers.emit(USERS);
    await flush();

    expect(applyButton(el).disabled).toBe(true);

    await selectUserAndLevel(el, USERS[1].userId, "GESTOR");
    expect(applyButton(el).disabled).toBe(false);
  });

  it("applies the chosen level and shows a success feedback", async () => {
    applyAccessLevel.mockResolvedValue({
      outcome: "SUCCEEDED",
      message: "Nível de acesso aplicado.",
      currentLevel: "Gestor Financeiro"
    });
    const el = build();
    canConfigure.emit(true);
    getEligibleUsers.emit(USERS);
    await flush();

    await selectUserAndLevel(el, USERS[1].userId, "GESTOR");
    applyButton(el).click();
    await flush();
    await flush();

    expect(applyAccessLevel).toHaveBeenCalledWith({
      userId: USERS[1].userId,
      level: "GESTOR"
    });
    expect(el.shadowRoot.querySelector("[aria-live='polite']")).not.toBeNull();
    expect(feedbackText(el)).toMatch(/aplicado/i);
  });

  it("surfaces a PENDING outcome as a non-success message", async () => {
    applyAccessLevel.mockResolvedValue({
      outcome: "PENDING",
      message: "O grupo ainda está sendo recalculado."
    });
    const el = build();
    canConfigure.emit(true);
    getEligibleUsers.emit(USERS);
    await flush();

    await selectUserAndLevel(el, USERS[0].userId, "PARTICIPANTE");
    applyButton(el).click();
    await flush();
    await flush();

    expect(feedbackText(el)).toMatch(/recalculado/i);
  });

  it("shows a generic failure message when the apply call rejects", async () => {
    applyAccessLevel.mockRejectedValue(new Error("boom"));
    const el = build();
    canConfigure.emit(true);
    getEligibleUsers.emit(USERS);
    await flush();

    await selectUserAndLevel(el, USERS[0].userId, "GESTOR");
    applyButton(el).click();
    await flush();
    await flush();

    expect(feedbackText(el)).toMatch(/Não foi possível aplicar/i);
  });

  it("renders an error state with a retry button when the wire fails", async () => {
    const el = build();
    canConfigure.emit(true);
    getEligibleUsers.error();
    await flush();

    const alert = el.shadowRoot.querySelector("[role='alert']");
    expect(alert).not.toBeNull();
    expect(alert.textContent).toMatch(/Não foi possível carregar/i);
    expect(
      [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
        /Tentar novamente/.test(b.label)
      )
    ).toBeDefined();
  });
});
