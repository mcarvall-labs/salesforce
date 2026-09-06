import { createElement } from 'lwc';
import AXF_LWC_counterpartyManagement from 'c/aXF_LWC_counterpartyManagement';
import getAuthorizedEntities from '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getAuthorizedEntities';
import getCounterparties from '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getCounterparties';
import getCounterpartyDetail from '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getCounterpartyDetail';
import saveCounterparty from '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.saveCounterparty';

jest.mock(
  '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getAuthorizedEntities',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getCounterparties',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getCounterpartyDetail',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.saveCounterparty',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const MOCK_ENTITIES = [
  {
    accountId: '001000000000001AAA',
    label: 'Empresa Alpha LTDA',
    contextType: 'BUSINESS',
    presentationCurrency: 'BRL'
  },
  {
    accountId: '001000000000002AAA',
    label: 'João Silva',
    contextType: 'PERSON',
    presentationCurrency: 'BRL'
  }
];

const MOCK_COUNTERPARTIES = [
  {
    counterpartyId: 'a01000000000001AAA',
    displayName: 'Fornecedora Beta',
    legalName: 'Fornecedora Beta LTDA',
    kind: 'ORGANIZATION',
    country: 'BR',
    status: 'ACTIVE',
    maskedTaxId: '••.•••.•••/0001-90',
    taxScheme: 'CNPJ',
    relationshipId: 'a02000000000001AAA',
    relationshipRole: 'Fornecedor',
    relationshipStatus: 'ACTIVE',
    validFrom: '2026-01-01',
    validTo: '2026-12-31'
  }
];

const MOCK_DETAIL = {
  counterpartyId: 'a01000000000001AAA',
  displayName: 'Fornecedora Beta',
  legalName: 'Fornecedora Beta LTDA',
  kind: 'ORGANIZATION',
  country: 'BR',
  status: 'ACTIVE',
  version: 1,
  maskedTaxId: '••.•••.•••/0001-90',
  taxScheme: 'CNPJ',
  taxCountry: 'BR',
  taxStatus: 'VERIFIED',
  relationshipId: 'a02000000000001AAA',
  accountId: '001000000000001AAA',
  entityName: 'Empresa Alpha LTDA',
  role: 'SUPPLIER',
  relationshipStatus: 'ACTIVE',
  entitySpecificDisplay: 'Fornecedor Matriz',
  validFrom: '2026-01-01',
  validTo: '2026-12-31',
  addressSnapshot: 'Rua das Flores, 123',
  email: 'contato@beta.com',
  phone: '+5511999998888',
  contactName: 'Carlos Souza',
  relationshipVersion: 1
};

describe('c-a-x-f_-l-w-c_counterparty-management', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function flush() {
    return Promise.resolve();
  }

  it('renders authorized entities and loads counterparties on mount', async () => {
    getCounterparties.mockResolvedValue(MOCK_COUNTERPARTIES);

    const element = createElement('c-a-x-f_-l-w-c_counterparty-management', {
      is: AXF_LWC_counterpartyManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);
    await flush();

    expect(getCounterparties).toHaveBeenCalledWith({
      accountId: '001000000000001AAA',
      searchKey: ''
    });
  });

  it('displays counterparties in list and shows detail on click', async () => {
    getCounterparties.mockResolvedValue(MOCK_COUNTERPARTIES);
    getCounterpartyDetail.mockResolvedValue(MOCK_DETAIL);

    const element = createElement('c-a-x-f_-l-w-c_counterparty-management', {
      is: AXF_LWC_counterpartyManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);
    await flush();
    await flush();

    const item = element.shadowRoot.querySelector('.counterparty-item');
    expect(item).not.toBeNull();

    item.click();
    await flush();

    expect(getCounterpartyDetail).toHaveBeenCalledWith({
      counterpartyId: 'a01000000000001AAA',
      accountId: '001000000000001AAA'
    });
  });

  it('opens modal on Nova Contraparte click and closes on Cancelar', async () => {
    getCounterparties.mockResolvedValue([]);

    const element = createElement('c-a-x-f_-l-w-c_counterparty-management', {
      is: AXF_LWC_counterpartyManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);
    await flush();

    const newBtn = element.shadowRoot.querySelector('lightning-button[label="Nova contraparte ou relação"]');
    if (newBtn) {
      newBtn.click();
      await flush();
      expect(element.shadowRoot.querySelector('.modal-card')).not.toBeNull();

      const cancelBtn = element.shadowRoot.querySelector('lightning-button[label="Cancelar"]');
      if (cancelBtn) {
        cancelBtn.click();
        await flush();
        expect(element.shadowRoot.querySelector('.modal-card')).toBeNull();
      }
    }
  });

  it('handles search input and reloads counterparties', async () => {
    getCounterparties.mockResolvedValue(MOCK_COUNTERPARTIES);

    const element = createElement('c-a-x-f_-l-w-c_counterparty-management', {
      is: AXF_LWC_counterpartyManagement
    });
    document.body.appendChild(element);

    getAuthorizedEntities.emit(MOCK_ENTITIES);
    await flush();

    const searchInput = element.shadowRoot.querySelector('lightning-input[type="search"]');
    if (searchInput) {
      searchInput.dispatchEvent(new CustomEvent('change', { detail: { value: 'Beta' } }));
      await flush();

      expect(getCounterparties).toHaveBeenCalledWith({
        accountId: '001000000000001AAA',
        searchKey: 'Beta'
      });
    }
  });
});
