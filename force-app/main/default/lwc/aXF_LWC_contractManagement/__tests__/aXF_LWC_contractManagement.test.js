import { createElement } from "lwc";
import AXF_LWC_contractManagement from "c/aXF_LWC_contractManagement";
import getAuthorizedEntities from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getAuthorizedEntities";
import getActiveRelationships from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getActiveRelationships";
import getContracts from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getContracts";
import getContractDetail from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getContractDetail";
import createDraftContract from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.createDraftContract";
import updateDraftContract from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.updateDraftContract";
import getTermVersions from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getTermVersions";
import saveDraftTermVersion from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.saveDraftTermVersion";
import calculateSchedulePreview from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.calculateSchedulePreview";
import activateTermVersion from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.activateTermVersion";

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

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getTermVersions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.saveDraftTermVersion",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.calculateSchedulePreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.activateTermVersion",
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
    title: "Prestacao de Servicos",
    lifecycle: "DRAFT",
    contractType: "EXPENSE",
    currencyIsoCode: "BRL",
    counterpartyName: "Fornecedor Beta"
  }
];

const MOCK_DETAIL = {
  contractId: "a03000000000001AAA",
  contractNumber: "CTR-000001",
  contractCode: "CTR-2026-001",
  title: "Prestacao de Servicos",
  lifecycle: "DRAFT",
  contractType: "EXPENSE",
  currencyIsoCode: "BRL",
  counterpartyName: "Fornecedor Beta",
  relationshipRole: "SUPPLIER",
  relationshipId: "a02000000000001AAA",
  startDate: "2026-09-01",
  endDate: "2027-08-31",
  version: 1,
  description: "Descricao detalhada"
};

const MOCK_TERMS = [
  {
    termVersionId: "a04000000000001AAA",
    termNumber: "CTV-00000001",
    revision: 1,
    status: "DRAFT",
    remunerationModel: "FIXED",
    currencyIsoCode: "BRL",
    contractedAmount: 100.0,
    installments: 3,
    calendarPolicy: "STANDARD_CALENDAR",
    timeZone: "America/Sao_Paulo"
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
    getTermVersions.mockResolvedValue([]);

    const element = createElement("c-axf-lwc-contract-management", {
      is: AXF_LWC_contractManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);

    await Promise.resolve();
    await Promise.resolve();

    const titleEl = element.shadowRoot.querySelector("h1");
    expect(titleEl.textContent).toContain("Gestao de Contratos");
  });

  it("selects contract and displays term versions and GF-04 schedule calculation", async () => {
    getActiveRelationships.mockResolvedValue(MOCK_RELATIONSHIPS);
    getContracts.mockResolvedValue(MOCK_CONTRACTS);
    getContractDetail.mockResolvedValue(MOCK_DETAIL);
    getTermVersions.mockResolvedValue(MOCK_TERMS);
    calculateSchedulePreview.mockResolvedValue({
      success: true,
      totalAmount: 100.0,
      totalResidual: 0.01,
      currencyIsoCode: "BRL",
      scheduleItems: [
        { installmentNumber: 1, dueDate: "2026-09-05", amount: 33.33, roundingResidual: 0.0, periodLabel: "Parcela 1/3" },
        { installmentNumber: 2, dueDate: "2026-10-05", amount: 33.33, roundingResidual: 0.0, periodLabel: "Parcela 2/3" },
        { installmentNumber: 3, dueDate: "2026-11-05", amount: 33.34, roundingResidual: 0.01, periodLabel: "Parcela 3/3 (Final com residual)" }
      ]
    });

    const element = createElement("c-axf-lwc-contract-management", {
      is: AXF_LWC_contractManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);
    await Promise.resolve();
    await Promise.resolve();

    // Clica para selecionar o contrato
    const selectRow = element.shadowRoot.querySelector("tr[data-id='a03000000000001AAA']");
    selectRow.click();

    await Promise.resolve();
    await Promise.resolve();

    // Verifica que carregou o detalhe e o termo
    expect(getContractDetail).toHaveBeenCalledWith({
      contractId: "a03000000000001AAA",
      accountId: "001000000000001AAA"
    });
    expect(getTermVersions).toHaveBeenCalledWith({
      contractId: "a03000000000001AAA",
      accountId: "001000000000001AAA"
    });

    // Abre o modal de novo termo
    const newTermBtn = element.shadowRoot.querySelector("lightning-button[data-testid='new-term-btn']");
    expect(newTermBtn).not.toBeNull();
    newTermBtn.click();
    await Promise.resolve();

    // Clica em calcular cronograma
    const calcBtn = element.shadowRoot.querySelector("lightning-button[data-testid='calculate-schedule-btn']");
    expect(calcBtn).not.toBeNull();
    calcBtn.click();
    await Promise.resolve();
    await Promise.resolve();

    expect(calculateSchedulePreview).toHaveBeenCalled();
  });

  it("handles term activation successfully", async () => {
    getActiveRelationships.mockResolvedValue(MOCK_RELATIONSHIPS);
    getContracts.mockResolvedValue(MOCK_CONTRACTS);
    getContractDetail.mockResolvedValue(MOCK_DETAIL);
    getTermVersions.mockResolvedValue(MOCK_TERMS);
    activateTermVersion.mockResolvedValue({
      success: true,
      status: "ACTIVE",
      message: "Versao de termo ativada com sucesso."
    });

    const element = createElement("c-axf-lwc-contract-management", {
      is: AXF_LWC_contractManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);
    await Promise.resolve();
    await new Promise(process.nextTick);
    await new Promise(process.nextTick);

    const selectRow = element.shadowRoot.querySelector("tr[data-id='a03000000000001AAA']");
    selectRow.click();
    await new Promise(process.nextTick);
    await new Promise(process.nextTick);
    await new Promise(process.nextTick);

    const activateBtn = element.shadowRoot.querySelector("lightning-button[data-testid='activate-term-btn']");
    expect(activateBtn).not.toBeNull();
    activateBtn.click();
    await new Promise(process.nextTick);
    await new Promise(process.nextTick);

    expect(activateTermVersion).toHaveBeenCalledWith({
      termVersionId: "a04000000000001AAA",
      accountId: "001000000000001AAA"
    });
  });
});
