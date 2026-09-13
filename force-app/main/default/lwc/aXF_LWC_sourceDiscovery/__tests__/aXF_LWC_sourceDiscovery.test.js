import { createElement } from "lwc";
import Disc from "c/aXF_LWC_sourceDiscovery";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getStatus";
import getDiscovered from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getDiscovered";
import startDiscovery from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.startDiscovery";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getStatus",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getDiscovered",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getConnections",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.startDiscovery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.registerConnection",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.updateReferences",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.createBankInstitution",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.deleteConnection",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Holder.saveHolder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

import registerConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.registerConnection";
import updateReferences from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.updateReferences";
import deleteConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.deleteConnection";
import getConnections from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getConnections";

jest.mock("@salesforce/i18n/lang", () => ({ default: "pt-BR" }), {
  virtual: true
});

const flush = () => Promise.resolve();
const button = (el, re) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
    re.test(b.label)
  );
const icon = (el, alt) =>
  [...el.shadowRoot.querySelectorAll("lightning-button-icon")].find((i) =>
    new RegExp(alt, "i").test(
      i.alternativeText || i.getAttribute("alternative-text") || ""
    )
  );
const setInput = (input, value) => {
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
};
const pick = (picker, recordId) =>
  picker.dispatchEvent(new CustomEvent("change", { detail: { recordId } }));

const connection = {
  connectionId: "a01000000000009",
  institution: "MeuPluggy",
  itemIdHint: "…def456",
  bankInstitutionId: null,
  bankInstitutionName: null,
  holderId: null,
  holderName: null,
  consentState: "ACTIVE",
  runState: null,
  accountsFound: 1,
  cardsFound: 2,
  discovered: false
};

function build() {
  const el = createElement("c-a-x-f_-l-w-c_source-discovery", { is: Disc });
  el.recordId = "a01000000000001";
  document.body.appendChild(el);
  return el;
}

function buildWizard() {
  const el = createElement("c-a-x-f_-l-w-c_source-discovery", { is: Disc });
  document.body.appendChild(el);
  return el;
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_sourceDiscovery", () => {
  it("shows a spinner before the status wire resolves", () => {
    const el = build();
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();
  });

  it("wizard mode: keeps the Item ID off the screen and only opens it in the modal", async () => {
    const el = buildWizard();
    getConnections.emit([]);
    await flush();

    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(el.shadowRoot.querySelector("lightning-input")).toBeNull();
    expect(el.shadowRoot.querySelector("[role='dialog']")).toBeNull();
    expect(button(el, /^Registrar conexão$/)).toBeDefined();
    expect(el.shadowRoot.textContent).toMatch(/Nenhuma conexão cadastrada/i);

    button(el, /^Registrar conexão$/).click();
    await flush();
    expect(el.shadowRoot.querySelector("lightning-input")).not.toBeNull();
    expect(el.shadowRoot.querySelector("[role='dialog']")).not.toBeNull();
  });

  it("wizard mode: registers the Item ID typed inside the modal", async () => {
    registerConnection.mockResolvedValue({
      connectionId: "a01000000000009",
      institution: "Banco X",
      created: true,
      message: "Conexão registrada."
    });
    const el = buildWizard();
    getConnections.emit([]);
    await flush();

    button(el, /^Registrar conexão$/).click();
    await flush();
    setInput(el.shadowRoot.querySelector("lightning-input"), "abc123def456");
    await flush();
    button(el, /^Registrar$/).click();
    await flush();
    await flush();

    expect(registerConnection).toHaveBeenCalledWith({
      pluggyItemId: "abc123def456"
    });
    // Nothing was selected: the references are a genuinely optional step.
    expect(updateReferences).not.toHaveBeenCalled();
  });

  it("wizard mode: registers the bank and the suggested holder chosen in the modal", async () => {
    registerConnection.mockResolvedValue({
      connectionId: "a01000000000009",
      institution: "MeuPluggy",
      created: true,
      message: "Conexão registrada."
    });
    updateReferences.mockResolvedValue({ outcome: "UPDATED" });
    const el = buildWizard();
    getConnections.emit([]);
    await flush();

    button(el, /^Registrar conexão$/).click();
    await flush();
    setInput(el.shadowRoot.querySelector("lightning-input"), "abc123def456");
    const pickers = el.shadowRoot.querySelectorAll("lightning-record-picker");
    expect(pickers).toHaveLength(2);
    pick(pickers[0], "a0100000000000B");
    pick(pickers[1], "00100000000000A");
    await flush();
    button(el, /^Registrar$/).click();
    await flush();
    await flush();
    await flush();

    expect(updateReferences).toHaveBeenCalledWith({
      connectionId: "a01000000000009",
      bankInstitutionId: "a0100000000000B",
      holderId: "00100000000000A"
    });
  });

  it("wizard mode: the list is read-only and shows the pending bank/holder", async () => {
    const el = buildWizard();
    getConnections.emit([connection]);
    await flush();

    expect(
      el.shadowRoot.querySelectorAll("tbody lightning-record-picker")
    ).toHaveLength(0);
    expect(el.shadowRoot.textContent).toMatch(/MeuPluggy/);
    expect(el.shadowRoot.textContent).toMatch(/Não vinculado/);
    expect(icon(el, "Editar conexão")).toBeDefined();
    expect(icon(el, "Excluir conexão")).toBeDefined();
  });

  it("wizard mode: the bare edit_form icon opens the details and the pickers", async () => {
    const el = buildWizard();
    getConnections.emit([connection]);
    await flush();

    const editIcon = icon(el, "Editar conexão");
    expect(editIcon.iconName || editIcon.getAttribute("icon-name")).toBe(
      "utility:edit_form"
    );
    expect(editIcon.variant || editIcon.getAttribute("variant")).toBe("bare");

    editIcon.click();
    await flush();
    expect(el.shadowRoot.querySelector("[role='dialog']")).not.toBeNull();
    expect(el.shadowRoot.textContent).toMatch(/…def456/);
    expect(el.shadowRoot.textContent).toMatch(
      /Descoberta|Aguardando descoberta/
    );
    expect(el.shadowRoot.textContent).toMatch(
      /1 conta e 2 cartões de crédito encontrados/
    );
    // The details modal is where an existing connection can be re-linked.
    expect(
      el.shadowRoot.querySelectorAll("[role='dialog'] lightning-record-picker")
    ).toHaveLength(2);
  });

  it("wizard mode: spells out what was found per kind instead of a bare count", async () => {
    const el = buildWizard();
    getConnections.emit([
      { ...connection, connectionId: "c1", accountsFound: 2, cardsFound: 0 },
      { ...connection, connectionId: "c2", accountsFound: 1, cardsFound: 1 },
      { ...connection, connectionId: "c3", accountsFound: 0, cardsFound: 1 },
      { ...connection, connectionId: "c4", accountsFound: 0, cardsFound: 0 }
    ]);
    await flush();

    const text = el.shadowRoot.textContent;
    expect(text).toMatch(/2 contas encontradas/);
    expect(text).toMatch(/1 conta e 1 cartão de crédito encontrados/);
    expect(text).toMatch(/1 cartão de crédito encontrado(?!s)/);
    expect(text).toMatch(/Aguardando descoberta/);
    expect(text).not.toMatch(/\d \+ \d/);
  });

  it("wizard mode: reports nothing found once discovery finished empty", async () => {
    const el = buildWizard();
    getConnections.emit([
      { ...connection, accountsFound: 0, cardsFound: 0, discovered: true }
    ]);
    await flush();

    expect(el.shadowRoot.textContent).toMatch(/Nada encontrado/);
  });

  it("wizard mode: the trash icon confirms before deleting a connection", async () => {
    deleteConnection.mockResolvedValue({
      outcome: "DELETED",
      message: "Conexão excluída."
    });
    const el = buildWizard();
    getConnections.emit([connection]);
    await flush();

    expect(deleteConnection).not.toHaveBeenCalled();
    icon(el, "Excluir conexão").click();
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/não pode ser desfeita/i);
    button(el, /^Excluir conexão$/).click();
    await flush();
    await flush();

    expect(deleteConnection).toHaveBeenCalledWith({
      connectionId: "a01000000000009"
    });
  });

  it("wizard mode: keeps the connection and explains why deletion was blocked", async () => {
    deleteConnection.mockResolvedValue({
      outcome: "BLOCKED",
      message: "A conexão tem contas em uso financeiro."
    });
    const el = buildWizard();
    getConnections.emit([connection]);
    await flush();

    icon(el, "Excluir conexão").click();
    await flush();
    button(el, /^Excluir conexão$/).click();
    await flush();
    await flush();

    expect(el.shadowRoot.textContent).toMatch(/uso financeiro/i);
  });

  it("wizard mode: 'Descobrir agora' runs discovery for every connection", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 1,
      cardsFound: 0
    });
    const el = buildWizard();
    getConnections.emit([
      {
        connectionId: "c1",
        institution: "Banco A",
        itemIdHint: "…1",
        consentState: "ACTIVE"
      },
      {
        connectionId: "c2",
        institution: "Banco B",
        itemIdHint: "…2",
        consentState: "ACTIVE"
      }
    ]);
    await flush();

    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();

    expect(startDiscovery).toHaveBeenCalledWith({ connectionId: "c1" });
    expect(startDiscovery).toHaveBeenCalledWith({ connectionId: "c2" });
  });

  it("wizard mode: reports what the connection references did to the sources", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 1,
      cardsFound: 1,
      applied: 2,
      released: 1,
      pending: 1,
      divergent: 0
    });
    const el = buildWizard();
    getConnections.emit([
      {
        connectionId: "c1",
        institution: "Banco A",
        itemIdHint: "…1",
        consentState: "ACTIVE"
      }
    ]);
    await flush();

    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();
    await flush();
    await flush();

    const text = el.shadowRoot.querySelector(
      "[aria-live='polite'] lightning-formatted-text"
    ).value;
    expect(text).toMatch(/1 liberada\(s\) com titular/);
    expect(text).toMatch(/1 pendente\(s\)/);
    expect(text).toMatch(/0 divergente\(s\)/);
    expect(text).toMatch(/Confirmar titulares/);
  });

  it("explains that the connection bank and holder are applied on discovery", async () => {
    const el = buildWizard();
    getConnections.emit([]);
    await flush();

    expect(el.shadowRoot.textContent).toMatch(
      /banco e o titular escolhidos aqui são aplicados/i
    );
    button(el, /^Registrar conexão$/).click();
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/nunca é sobrescrito/i);
    expect(el.shadowRoot.textContent).toMatch(/Confirmar titulares/);
  });

  it("offers 'Descobrir agora' and explains that history is not imported", async () => {
    const el = build();
    getStatus.emit({ state: null, complete: false });
    getDiscovered.emit([]);
    await flush();
    expect(button(el, /Descobrir agora/)).toBeDefined();
    expect(el.shadowRoot.textContent).toMatch(/Não importa o histórico/i);
  });

  it("shows the 'none found' message when discovery completes with zero sources", async () => {
    const el = build();
    getStatus.emit({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 0,
      cardsFound: 0,
      message: "Nenhuma conta ou cartão encontrado nas conexões informadas."
    });
    getDiscovered.emit([]);
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/Nenhuma conta ou cartão/i);
  });

  it("lists discovered sources with custody status (AC3/AC7)", async () => {
    const el = build();
    getStatus.emit({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 1,
      cardsFound: 1
    });
    getDiscovered.emit([
      {
        recordId: "b1",
        kind: "BANK",
        institution: "Banco X",
        currencyIsoCode: "BRL",
        availability: "CUSTODY"
      },
      {
        recordId: "c1",
        kind: "CARD",
        institution: "Banco X",
        currencyIsoCode: "BRL",
        availability: "CUSTODY"
      }
    ]);
    await flush();

    const rows = el.shadowRoot.querySelectorAll("tbody tr");
    expect(rows).toHaveLength(2);
    expect(el.shadowRoot.textContent).toMatch(/Em custódia/i);
  });

  it("flags an incomplete run as not the full catalogue (AC5)", async () => {
    const el = build();
    getStatus.emit({ state: "FAILED_RETRYABLE", complete: false });
    getDiscovered.emit([]);
    await flush();
    expect(el.shadowRoot.querySelector("[role='note']").textContent).toMatch(
      /não representa o catálogo completo/i
    );
    expect(button(el, /Continuar descoberta/)).toBeDefined();
  });

  it("runs discovery and surfaces the result message", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      message: "1 conta(s) e 1 cartão(ões) em custódia."
    });
    const el = build();
    getStatus.emit({ state: null, complete: false });
    getDiscovered.emit([]);
    await flush();

    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();

    expect(startDiscovery).toHaveBeenCalledWith({
      connectionId: "a01000000000001"
    });
    expect(
      el.shadowRoot.querySelector(
        "[aria-live='polite'] lightning-formatted-text"
      ).value
    ).toMatch(/custódia/i);
  });

  it("renders an error state with retry when the status wire fails", async () => {
    const el = build();
    getStatus.error();
    await flush();
    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toMatch(
      /Não foi possível carregar/i
    );
  });

  // ---- AXF-106: the summary never erases the cause nor claims a false success ----

  const feedbackText = (el) =>
    el.shadowRoot.querySelector("[aria-live='polite'] lightning-formatted-text")
      .value;
  // the style really rendered for the summary (AXF-106)
  const feedbackVariant = (el) =>
    el.shadowRoot
      .querySelector("[data-feedback-variant]")
      .getAttribute("data-feedback-variant");

  const discoverAll = async (el) => {
    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();
    await flush();
    await flush();
  };

  it("does not claim success when nothing was released", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 2,
      cardsFound: 0,
      applied: 0,
      released: 0,
      pending: 2,
      divergent: 0,
      message: "2 conta(s) descobertos."
    });
    const el = buildWizard();
    getConnections.emit([
      { connectionId: "c1", institution: "Banco A", consentState: "ACTIVE" }
    ]);
    await flush();
    await discoverAll(el);

    expect(feedbackText(el)).toMatch(/Nenhuma fonte foi liberada/i);
    expect(feedbackVariant(el)).toBe("warning");
  });

  it("styles a fully released discovery as a success", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 1,
      cardsFound: 1,
      applied: 2,
      released: 2,
      pending: 0,
      divergent: 0,
      message: "ok"
    });
    const el = buildWizard();
    getConnections.emit([
      { connectionId: "c1", institution: "Banco A", consentState: "ACTIVE" }
    ]);
    await flush();
    await discoverAll(el);

    expect(feedbackVariant(el)).toBe("success");
    expect(feedbackText(el)).toMatch(/2 liberada\(s\) com titular/);
  });

  it("preserves the service cause of a terminal failure and styles it as an error", async () => {
    startDiscovery.mockResolvedValue({
      state: "FAILED_TERMINAL",
      complete: false,
      accountsFound: 0,
      cardsFound: 0,
      released: 0,
      pending: 0,
      divergent: 0,
      message:
        "A aplicacao nao tem autorizacao para listar as contas desta conexao. Reautorize."
    });
    const el = buildWizard();
    getConnections.emit([
      { connectionId: "c1", institution: "Banco A", consentState: "ACTIVE" }
    ]);
    await flush();
    await discoverAll(el);

    expect(feedbackText(el)).toMatch(/Reautorize/);
    expect(feedbackText(el)).toMatch(/não concluíram/i);
    expect(feedbackVariant(el)).toBe("error");
  });

  it("keeps a thrown error as the cause instead of the generic summary", async () => {
    startDiscovery.mockRejectedValue({
      body: { message: "Você não tem autorização para descobrir fontes." }
    });
    const el = buildWizard();
    getConnections.emit([
      { connectionId: "c1", institution: "Banco A", consentState: "ACTIVE" }
    ]);
    await flush();
    await discoverAll(el);

    expect(feedbackText(el)).toMatch(/não tem autorização para descobrir/i);
    expect(feedbackVariant(el)).toBe("error");
  });

  // ---- AXF-106 AC6: the single-connection view never reports a false success either ----

  // The connection view renders the run status AND the summary; the summary is the one
  // carrying the variant, exactly as the multi-connection summary does.
  const singleFeedbackText = (el) =>
    el.shadowRoot.querySelector(
      "[data-feedback-variant] lightning-formatted-text"
    ).value;

  it("reports an error on the connection view when the run failed a source", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 2,
      cardsFound: 0,
      applied: 1,
      released: 1,
      pending: 1,
      divergent: 0,
      bankDivergent: 0,
      conflicts: 0,
      failed: 1,
      message: "2 conta(s) e 0 cartao(oes) descobertos."
    });
    const el = build();
    getStatus.emit({ state: null, complete: false });
    getDiscovered.emit([]);
    await flush();

    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();

    expect(feedbackVariant(el)).toBe("error");
    expect(singleFeedbackText(el)).toMatch(/não puderam ser gravadas/i);
    expect(singleFeedbackText(el)).toMatch(/nada foi liberado nelas/i);
  });

  it("warns on the connection view when a source was found and none released", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 1,
      cardsFound: 0,
      released: 0,
      pending: 0,
      divergent: 0,
      bankDivergent: 0,
      conflicts: 0,
      failed: 0,
      message: "1 conta(s) e 0 cartao(oes) descobertos."
    });
    const el = build();
    getStatus.emit({ state: null, complete: false });
    getDiscovered.emit([]);
    await flush();

    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();

    expect(feedbackVariant(el)).toBe("warning");
  });

  it("styles a fully released connection run as a success", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 1,
      cardsFound: 0,
      applied: 1,
      released: 1,
      pending: 0,
      divergent: 0,
      bankDivergent: 0,
      conflicts: 0,
      failed: 0,
      message: "1 conta(s) e 0 cartao(oes) descobertos."
    });
    const el = build();
    getStatus.emit({ state: null, complete: false });
    getDiscovered.emit([]);
    await flush();

    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();

    expect(feedbackVariant(el)).toBe("success");
  });
});
