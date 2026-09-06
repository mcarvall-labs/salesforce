import { LightningElement, track, wire } from 'lwc';
import getAuthorizedEntities from '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getAuthorizedEntities';
import getCounterparties from '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getCounterparties';
import getCounterpartyDetail from '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.getCounterpartyDetail';
import saveCounterparty from '@salesforce/apex/AXF_CLS_CTRL_CounterpartyManagement.saveCounterparty';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AXF_LWC_counterpartyManagement extends LightningElement {
  @track selectedAccountId = '';
  @track entities = [];
  @track counterparties = [];
  @track selectedDetail = null;
  @track selectedCounterpartyId = null;
  @track searchKey = '';
  @track isLoading = false;
  @track isSaving = false;
  @track errorMessage = '';
  @track isModalOpen = false;

  @track form = {
    counterpartyId: null,
    legalName: '',
    displayName: '',
    kind: 'ORGANIZATION',
    country: 'BR',
    status: 'ACTIVE',
    version: null,
    relationshipId: null,
    role: 'SERVICE_PROVIDER',
    relationshipStatus: 'ACTIVE',
    entitySpecificDisplay: '',
    validFrom: null,
    validTo: null,
    addressSnapshot: '',
    email: '',
    phone: '',
    contactName: '',
    relationshipVersion: null,
    taxScheme: 'CNPJ',
    taxCountry: 'BR',
    taxRawDocument: ''
  };

  kindOptions = [
    { label: 'Pessoa jurídica', value: 'ORGANIZATION' },
    { label: 'Pessoa física', value: 'PERSON' }
  ];

  statusOptions = [
    { label: 'Ativo', value: 'ACTIVE' },
    { label: 'Inativo', value: 'INACTIVE' }
  ];

  taxSchemeOptions = [
    { label: 'CNPJ (Brasil)', value: 'CNPJ' },
    { label: 'CPF (Brasil)', value: 'CPF' },
    { label: 'NIF (Portugal / UE)', value: 'NIF' },
    { label: 'Outro', value: 'OTHER' }
  ];

  roleOptions = [
    { label: 'Prestador de serviços', value: 'SERVICE_PROVIDER' },
    { label: 'Cliente', value: 'CLIENT' },
    { label: 'Fornecedor', value: 'SUPPLIER' },
    { label: 'Parceiro', value: 'PARTNER' },
    { label: 'Locatário', value: 'TENANT' },
    { label: 'Locador', value: 'LANDLORD' },
    { label: 'Outro', value: 'OTHER' }
  ];

  @wire(getAuthorizedEntities)
  wiredEntities({ error, data }) {
    if (data) {
      this.entities = data;
      if (data.length > 0 && !this.selectedAccountId) {
        this.selectedAccountId = data[0].accountId;
        this.loadCounterparties();
      }
    } else if (error) {
      this.showErrorToast('Erro ao carregar entidades autorizadas', error.body ? error.body.message : error);
    }
  }

  get hasEntities() {
    return this.entities && this.entities.length > 0;
  }

  get entityOptions() {
    return this.entities.map(e => ({
      label: `${e.label} (${e.contextType === 'PERSON' ? 'Pessoa Física' : 'Pessoa Jurídica'})`,
      value: e.accountId
    }));
  }

  get currentEntityName() {
    const found = this.entities.find(e => e.accountId === this.selectedAccountId);
    return found ? found.label : '';
  }

  get isNewDisabled() {
    return !this.selectedAccountId || this.isLoading;
  }

  get hasCounterparties() {
    return this.counterparties && this.counterparties.length > 0;
  }

  get modalTitle() {
    return this.form.relationshipId ? 'Editar Relação com Contraparte' : 'Nova Contraparte ou Relação';
  }

  handleEntityChange(event) {
    this.selectedAccountId = event.detail.value;
    this.selectedCounterpartyId = null;
    this.selectedDetail = null;
    this.loadCounterparties();
  }

  handleSearchChange(event) {
    this.searchKey = event.detail.value;
    this.loadCounterparties();
  }

  handleClearError() {
    this.errorMessage = '';
  }

  async loadCounterparties() {
    if (!this.selectedAccountId) {
      this.counterparties = [];
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const data = await getCounterparties({ accountId: this.selectedAccountId, searchKey: this.searchKey });
      this.counterparties = data.map(c => ({
        ...c,
        isActive: c.status === 'ACTIVE',
        cssClass: (c.counterpartyId === this.selectedCounterpartyId)
          ? 'counterparty-item active'
          : 'counterparty-item'
      }));

      // Mantém ou reseta seleção
      if (this.selectedCounterpartyId) {
        const found = this.counterparties.find(c => c.counterpartyId === this.selectedCounterpartyId);
        if (found) {
          await this.loadDetail(this.selectedCounterpartyId);
        } else if (this.counterparties.length > 0) {
          await this.selectFirstCounterparty();
        } else {
          this.selectedDetail = null;
          this.selectedCounterpartyId = null;
        }
      } else if (this.counterparties.length > 0) {
        await this.selectFirstCounterparty();
      } else {
        this.selectedDetail = null;
      }
    } catch (error) {
      this.errorMessage = error.body ? error.body.message : (error.message || 'Erro ao carregar contrapartes.');
    } finally {
      this.isLoading = false;
    }
  }

  async selectFirstCounterparty() {
    this.selectedCounterpartyId = this.counterparties[0].counterpartyId;
    this.updateActiveItemCss();
    await this.loadDetail(this.selectedCounterpartyId);
  }

  handleSelectCounterparty(event) {
    const id = event.currentTarget.dataset.id;
    this.selectedCounterpartyId = id;
    this.updateActiveItemCss();
    this.loadDetail(id);
  }

  updateActiveItemCss() {
    this.counterparties = this.counterparties.map(c => ({
      ...c,
      cssClass: (c.counterpartyId === this.selectedCounterpartyId)
        ? 'counterparty-item active'
        : 'counterparty-item'
    }));
  }

  async loadDetail(counterpartyId) {
    if (!counterpartyId || !this.selectedAccountId) return;
    try {
      const detail = await getCounterpartyDetail({ counterpartyId: counterpartyId, accountId: this.selectedAccountId });
      this.selectedDetail = {
        ...detail,
        kindLabel: detail.kind === 'PERSON' ? 'Pessoa física' : 'Pessoa jurídica',
        roleLabel: this.getRoleLabel(detail.role),
        validityText: this.formatValidity(detail.validFrom, detail.validTo),
        addressDisplay: detail.addressSnapshot ? detail.addressSnapshot : 'Nenhum endereço informado',
        contactName: detail.contactName ? detail.contactName : 'Sem contato nominal'
      };
    } catch (error) {
      this.showErrorToast('Erro ao carregar detalhes da contraparte', error.body ? error.body.message : error);
    }
  }

  getRoleLabel(role) {
    const opt = this.roleOptions.find(r => r.value === role);
    return opt ? opt.label : (role || 'Não especificado');
  }

  formatValidity(validFrom, validTo) {
    if (!validFrom && !validTo) return 'Vigência indeterminada';
    if (validFrom && !validTo) return `Desde ${validFrom} (sem término)`;
    if (!validFrom && validTo) return `Até ${validTo}`;
    return `${validFrom} → ${validTo}`;
  }

  handleOpenNewModal() {
    this.form = {
      counterpartyId: null,
      legalName: '',
      displayName: '',
      kind: 'ORGANIZATION',
      country: 'BR',
      status: 'ACTIVE',
      version: null,
      relationshipId: null,
      role: 'SERVICE_PROVIDER',
      relationshipStatus: 'ACTIVE',
      entitySpecificDisplay: '',
      validFrom: null,
      validTo: null,
      addressSnapshot: '',
      email: '',
      phone: '',
      contactName: '',
      relationshipVersion: null,
      taxScheme: 'CNPJ',
      taxCountry: 'BR',
      taxRawDocument: ''
    };
    this.isModalOpen = true;
  }

  handleOpenEditModal() {
    if (!this.selectedDetail) return;
    this.form = {
      counterpartyId: this.selectedDetail.counterpartyId,
      legalName: this.selectedDetail.legalName,
      displayName: this.selectedDetail.displayName,
      kind: this.selectedDetail.kind,
      country: this.selectedDetail.country,
      status: this.selectedDetail.status,
      version: this.selectedDetail.version,
      relationshipId: this.selectedDetail.relationshipId,
      role: this.selectedDetail.role,
      relationshipStatus: this.selectedDetail.relationshipStatus,
      entitySpecificDisplay: this.selectedDetail.entitySpecificDisplay,
      validFrom: this.selectedDetail.validFrom,
      validTo: this.selectedDetail.validTo,
      addressSnapshot: this.selectedDetail.addressSnapshot,
      email: this.selectedDetail.email,
      phone: this.selectedDetail.phone,
      contactName: this.selectedDetail.contactName,
      relationshipVersion: this.selectedDetail.relationshipVersion,
      taxScheme: this.selectedDetail.taxScheme || 'CNPJ',
      taxCountry: this.selectedDetail.taxCountry || this.selectedDetail.country,
      taxRawDocument: ''
    };
    this.isModalOpen = true;
  }

  handleCloseModal() {
    this.isModalOpen = false;
  }

  handleFormChange(event) {
    const field = event.target.dataset.field;
    if (field) {
      this.form[field] = event.target.value;
    }
  }

  async handleSaveForm() {
    // Validação dos campos do formulário
    const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea')];
    const allValid = inputs.reduce((validSoFar, input) => {
      input.reportValidity();
      return validSoFar && input.checkValidity();
    }, true);

    if (!allValid) {
      this.showErrorToast('Atenção', 'Preencha todos os campos obrigatórios corretamente.');
      return;
    }

    if (this.form.validFrom && this.form.validTo && this.form.validTo < this.form.validFrom) {
      this.showErrorToast('Atenção', 'A data de término não pode ser anterior à data de início.');
      return;
    }

    this.isSaving = true;
    try {
      const payload = {
        ...this.form,
        accountId: this.selectedAccountId
      };

      const result = await saveCounterparty({ payload: payload });
      this.showSuccessToast('Sucesso', result.message || 'Contraparte e relação salvas com sucesso.');
      this.isModalOpen = false;
      this.selectedCounterpartyId = result.counterpartyId;
      await this.loadCounterparties();
    } catch (error) {
      this.showErrorToast('Erro ao salvar', error.body ? error.body.message : (error.message || 'Erro inesperado'));
    } finally {
      this.isSaving = false;
    }
  }

  showSuccessToast(title, message) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'success' }));
  }

  showErrorToast(title, message) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error', mode: 'sticky' }));
  }
}
