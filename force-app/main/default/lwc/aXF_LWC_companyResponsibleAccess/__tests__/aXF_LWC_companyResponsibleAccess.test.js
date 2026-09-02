import { createElement } from "lwc";
import Cmp from "c/aXF_LWC_companyResponsibleAccess";
import L from "../labels";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.canConfigure";
import getResponsibilities from "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.getResponsibilities";
import revokeResponsibility from "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.revokeResponsibility";
import confirmResponsibility from "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.confirmResponsibility";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.canConfigure",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.getResponsibilities",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.revokeResponsibility",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.confirmResponsibility",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ROWS = [
  {
    craId: "a01000000000001",
    version: 3,
    personId: "001000000000101",
    personName: "Ana Sócia",
    role: "PARTNER",
    status: "GRANTED",
    grantedAt: "2026-08-01T12:00:00.000Z",
    revokedAt: null,
    lastError: null
  },
  {
    craId: "a01000000000002",
    version: 1,
    personId: "001000000000102",
    personName: "Bruno Sem Usuário",
    role: "MANAGER",
    status: "RELATIONSHIP_ONLY",
    grantedAt: null,
    revokedAt: null,
    lastError: null
  },
  {
    craId: "a01000000000003",
    version: 4,
    personId: "001000000000103",
    personName: "Carla Falhou",
    role: "PARTNER",
    status: "FAILED",
    grantedAt: null,
    revokedAt: null,
    lastError: "O papel de equipe Responsável Financeiro não está configurado."
  },
  {
    craId: "a01000000000004",
    version: 6,
    personId: "001000000000104",
    personName: "Diego Retirado",
    role: "MANAGER",
    status: "REVOKED",
    grantedAt: "2026-07-01T12:00:00.000Z",
    revokedAt: "2026-08-20T09:00:00.000Z",
    lastError: null
  }
];

function build(recordId = "001000000000999") {
  const el = createElement("c-a-x-f_-l-w-c_company-responsible-access", {
    is: Cmp
  });
  if (recordId) {
    el.recordId = recordId;
  }
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();
const settle = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_companyResponsibleAccess", () => {
  it("shows a forbidden message when the caller cannot configure", async () => {
    const el = build();
    canConfigure.emit(false);
    await flush();
    expect(el.shadowRoot.textContent).toContain(L.forbidden);
    expect(el.shadowRoot.querySelector("table")).toBeNull();
  });

  it("asks for a business when opened without a record", async () => {
    const el = build(null);
    canConfigure.emit(true);
    await flush();
    expect(el.shadowRoot.textContent).toContain(L.noBusiness);
  });

  it("lists each responsible with a distinct textual status", async () => {
    const el = build();
    canConfigure.emit(true);
    getResponsibilities.emit(ROWS);
    await flush();

    const bodyRows = el.shadowRoot.querySelectorAll("tbody tr");
    expect(bodyRows).toHaveLength(4);
    const text = el.shadowRoot.textContent;
    expect(text).toContain(L.statusGranted);
    expect(text).toContain(L.statusPending);
    expect(text).toContain(L.statusFailed);
    expect(text).toContain(L.statusRevoked);
    // failed row surfaces the sanitized reason
    expect(text).toMatch(/Responsável Financeiro não está configurado/);
    // revoked row shows the revoked-on instant (not a grant instant)
    expect(text).toContain(L.revokedOn.split("{0}")[0].trim());
  });

  it("only offers revoke on GRANTED and retry on FAILED", async () => {
    const el = build();
    canConfigure.emit(true);
    getResponsibilities.emit(ROWS);
    await flush();
    const labels = [...el.shadowRoot.querySelectorAll("lightning-button")].map(
      (b) => b.label
    );
    expect(labels).toContain(L.actionRevoke);
    expect(labels).toContain(L.actionRetry);
    expect(labels.filter((l) => l === L.actionRevoke)).toHaveLength(1);
  });

  it("confirms before revoking and reports the verified result", async () => {
    revokeResponsibility.mockResolvedValue({
      outcome: "REVOKED",
      status: "REVOKED"
    });
    const el = build();
    canConfigure.emit(true);
    getResponsibilities.emit(ROWS);
    await flush();

    el.shadowRoot
      .querySelector('lightning-button[data-action-id="a01000000000001"]')
      .click();
    await flush();

    const dialog = el.shadowRoot.querySelector("[role='alertdialog']");
    expect(dialog).not.toBeNull();
    dialog.querySelectorAll("lightning-button")[1].click(); // confirm
    await settle();

    expect(revokeResponsibility).toHaveBeenCalledWith({
      craId: "a01000000000001",
      expectedVersion: 3
    });
    expect(
      el.shadowRoot.querySelector("[data-feedback]").textContent
    ).toContain(L.revokeDone);
  });

  it("surfaces a concurrent-change conflict as a reload notice", async () => {
    revokeResponsibility.mockResolvedValue({ outcome: "CONFLICT" });
    const el = build();
    canConfigure.emit(true);
    getResponsibilities.emit(ROWS);
    await flush();

    el.shadowRoot
      .querySelector('lightning-button[data-action-id="a01000000000001"]')
      .click();
    await flush();
    el.shadowRoot
      .querySelector("[role='alertdialog']")
      .querySelectorAll("lightning-button")[1]
      .click();
    await settle();

    expect(
      el.shadowRoot.querySelector("[data-feedback]").textContent
    ).toContain(L.conflictReload);
  });

  it("retries a failed grant through confirmResponsibility", async () => {
    confirmResponsibility.mockResolvedValue({ outcome: "GRANTED" });
    const el = build();
    canConfigure.emit(true);
    getResponsibilities.emit(ROWS);
    await flush();

    el.shadowRoot
      .querySelector('lightning-button[data-action-id="a01000000000003"]')
      .click();
    await settle();

    expect(confirmResponsibility).toHaveBeenCalledWith({
      input: {
        businessId: "001000000000999",
        personId: "001000000000103",
        role: "PARTNER",
        expectedVersion: 4
      }
    });
  });

  it("renders a sanitized error when the wire fails", async () => {
    const el = build();
    canConfigure.emit(true);
    getResponsibilities.error();
    await flush();
    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toContain(
      L.error
    );
  });
});
