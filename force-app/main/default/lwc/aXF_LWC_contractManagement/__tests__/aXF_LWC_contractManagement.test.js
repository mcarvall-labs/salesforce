import { createElement } from "lwc";
import AXF_LWC_contractManagement from "c/aXF_LWC_contractManagement";
import getAuthorizedEntities from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getAuthorizedEntities";
import getActiveRelationships from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getActiveRelationships";
import getContracts from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getContracts";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getAuthorizedEntities",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getActiveRelationships",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getContracts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getContractDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.createDraftContract",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.updateDraftContract",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const MOCK_ENTITIES = [
  {
    accountId: "001000000000001AAA",
    entityName: "Empresa Alpha LTDA",
    accountNumber: "123"
  }
];

const MOCK_RELATIONSHIPS = [
  {
    relationshipId: "a02000000000001AAA",
    counterpartyId: "a01000000000001AAA",
    counterpartyName: "Fornecedor Beta",
    role: "SUPPLIER",
    status: "ACTIVE",
    entitySpecificDisplay: "Matriz"
  }
];

const MOCK_CONTRACTS = [
  {
    contractId: "a03000000000001AAA",
    contractNumber: "CTR-000001",
    contractCode: "CTR-2026-001",
    title: "Prestação de Serviços",
    lifecycle: "DRAFT",
    contractType: "EXPENSE",
    currencyIsoCode: "BRL",
    counterpartyName: "Fornecedor Beta"
  }
];

describe("c-a-x-f-_-l-w-c_contract-management", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders authorized entities and loads contracts", async () => {
    getActiveRelationships.mockResolvedValue(MOCK_RELATIONSHIPS);
    getContracts.mockResolvedValue(MOCK_CONTRACTS);

    const element = createElement("c-axf-lwc-contract-management", {
      is: AXF_LWC_contractManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);

    await Promise.resolve();
    await Promise.resolve();

    const titleEl = element.shadowRoot.querySelector("h1");
    expect(titleEl.textContent).toContain("Gestão de Contratos");
  });

  it("displays contracts table when contracts exist", async () => {
    getActiveRelationships.mockResolvedValue(MOCK_RELATIONSHIPS);
    getContracts.mockResolvedValue(MOCK_CONTRACTS);

    const element = createElement("c-axf-lwc-contract-management", {
      is: AXF_LWC_contractManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);

    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();

    const rows = element.shadowRoot.querySelectorAll("tbody tr");
    expect(rows.length).toBe(1);
    expect(element.shadowRoot.textContent).toContain("CTR-2026-001");
  });

  it("opens modal for new draft contract", async () => {
    getActiveRelationships.mockResolvedValue(MOCK_RELATIONSHIPS);
    getContracts.mockResolvedValue(MOCK_CONTRACTS);

    const element = createElement("c-axf-lwc-contract-management", {
      is: AXF_LWC_contractManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);

    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();

    const newBtn = element.shadowRoot.querySelector(
      '[data-testid="new-contract-btn"]'
    );
    expect(newBtn).not.toBeNull();
    newBtn.click();
    await Promise.resolve();

    const modalTitle = element.shadowRoot.querySelector(".slds-modal__title");
    expect(modalTitle).not.toBeNull();
    expect(modalTitle.textContent).toContain("Novo Contrato em Rascunho");
  });
});
