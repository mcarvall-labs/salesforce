import { LightningElement, track, wire } from "lwc";
import getAuthorizedEntities from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getAuthorizedEntities";
import getActiveRelationships from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getActiveRelationships";
import getContracts from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getContracts";
import getContractDetail from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getContractDetail";
import createDraftContract from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.createDraftContract";
import updateDraftContract from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.updateDraftContract";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class AXF_LWC_contractManagement extends LightningElement {
  @track selectedAccountId = "";
  @track entities = [];
  @track contracts = [];
  @track activeRelationships = [];
  @track selectedDetail = null;
  @track selectedContractId = null;
  @track isLoading = false;
  @track isSaving = false;
  @track errorMessage = "";
  @track isModalOpen = false;
  @track isEditing = false;

  @track form = {
    contractId: null,
    accountId: "",
    relationshipId: "",
    counterpartyId: null,
    contractCode: "",
    title: "",
    contractType: "REVENUE",
    currencyIsoCode: "BRL",
    startDate: null,
    endDate: null,
    description: "",
    version: 1
  };

  typeOptions = [
    { label: "Receita", value: "REVENUE" },
    { label: "Despesa", value: "EXPENSE" }
  ];

  @wire(getAuthorizedEntities)
  wiredEntities({ error, data }) {
    if (data) {
      this.entities = data.map((item) => ({
        label:
          item.entityName +
          (item.accountNumber ? " (" + item.accountNumber + ")" : ""),
        value: item.accountId
      }));
      if (this.entities.length > 0 && !this.selectedAccountId) {
        this.selectedAccountId = this.entities[0].value;
        this.loadContracts();
        this.loadActiveRelationships();
      }
    } else if (error) {
      this.showToast("Erro", this.extractErrorMessage(error), "error");
    }
  }

  handleEntityChange(event) {
    this.selectedAccountId = event.detail.value;
    this.selectedContractId = null;
    this.selectedDetail = null;
    this.loadContracts();
    this.loadActiveRelationships();
  }

  async loadContracts() {
    if (!this.selectedAccountId) return;
    this.isLoading = true;
    this.errorMessage = "";
    try {
      this.contracts = await getContracts({
        accountId: this.selectedAccountId
      });
    } catch (err) {
      this.errorMessage = this.extractErrorMessage(err);
      this.contracts = [];
    } finally {
      this.isLoading = false;
    }
  }

  async loadActiveRelationships() {
    if (!this.selectedAccountId) return;
    try {
      const rels = await getActiveRelationships({
        accountId: this.selectedAccountId
      });
      this.activeRelationships = rels.map((r) => ({
        label:
          r.counterpartyName +
          " (" +
          r.role +
          (r.entitySpecificDisplay ? " - " + r.entitySpecificDisplay : "") +
          ")",
        value: r.relationshipId,
        counterpartyId: r.counterpartyId
      }));
    } catch {
      this.activeRelationships = [];
    }
  }

  async handleSelectContract(event) {
    const contractId = event.currentTarget.dataset.id;
    this.selectedContractId = contractId;
    this.isLoading = true;
    try {
      this.selectedDetail = await getContractDetail({
        contractId: contractId,
        accountId: this.selectedAccountId
      });
    } catch (err) {
      this.showToast("Erro", this.extractErrorMessage(err), "error");
      this.selectedDetail = null;
    } finally {
      this.isLoading = false;
    }
  }

  handleNewContract() {
    if (!this.selectedAccountId) {
      this.showToast("Aviso", "Selecione uma entidade primeiro.", "warning");
      return;
    }
    if (this.activeRelationships.length === 0) {
      this.showToast(
        "Aviso",
        "Não há relações ativas com contrapartes cadastradas para esta entidade.",
        "warning"
      );
      return;
    }
    this.isEditing = false;
    this.form = {
      contractId: null,
      accountId: this.selectedAccountId,
      relationshipId: this.activeRelationships[0].value,
      counterpartyId: this.activeRelationships[0].counterpartyId,
      contractCode: "",
      title: "",
      contractType: "REVENUE",
      currencyIsoCode: "BRL",
      startDate: null,
      endDate: null,
      description: "",
      version: 1
    };
    this.isModalOpen = true;
  }

  handleEditDraft() {
    if (!this.selectedDetail) return;
    this.isEditing = true;
    this.form = {
      contractId: this.selectedDetail.contractId,
      accountId: this.selectedDetail.accountId,
      relationshipId: this.selectedDetail.relationshipId,
      counterpartyId: this.selectedDetail.counterpartyId,
      contractCode: this.selectedDetail.contractCode,
      title: this.selectedDetail.title,
      contractType: this.selectedDetail.contractType,
      currencyIsoCode: this.selectedDetail.currencyIsoCode || "BRL",
      startDate: this.selectedDetail.startDate,
      endDate: this.selectedDetail.endDate,
      description: this.selectedDetail.description,
      version: this.selectedDetail.version
    };
    this.isModalOpen = true;
  }

  handleCloseModal() {
    this.isModalOpen = false;
  }

  handleFormChange(event) {
    const field = event.target.name;
    const value = event.target.value;
    this.form[field] = value;
    if (field === "relationshipId") {
      const rel = this.activeRelationships.find((r) => r.value === value);
      if (rel) {
        this.form.counterpartyId = rel.counterpartyId;
      }
    }
  }

  async handleSaveContract() {
    if (!this.validateForm()) return;
    this.isSaving = true;
    try {
      if (this.isEditing) {
        await updateDraftContract({ payload: this.form });
        this.showToast(
          "Sucesso",
          "Rascunho do contrato atualizado com sucesso.",
          "success"
        );
      } else {
        await createDraftContract({ payload: this.form });
        this.showToast(
          "Sucesso",
          "Contrato em rascunho criado com sucesso.",
          "success"
        );
      }
      this.isModalOpen = false;
      await this.loadContracts();
      if (this.isEditing && this.selectedContractId) {
        this.selectedDetail = await getContractDetail({
          contractId: this.selectedContractId,
          accountId: this.selectedAccountId
        });
      }
    } catch (err) {
      this.showToast("Erro ao salvar", this.extractErrorMessage(err), "error");
    } finally {
      this.isSaving = false;
    }
  }

  handleLifecycleAttempt() {
    this.showToast(
      "Ação Bloqueada",
      "Transição de ciclo de vida bloqueada: operação canônica de término, cancelamento, ativação ou substituição ainda não disponível (AXF-52).",
      "warning"
    );
  }

  validateForm() {
    if (!this.form.contractCode || !this.form.contractCode.trim()) {
      this.showToast(
        "Validação",
        "O código do contrato é obrigatório.",
        "error"
      );
      return false;
    }
    if (!this.form.title || !this.form.title.trim()) {
      this.showToast(
        "Validação",
        "O título do contrato é obrigatório.",
        "error"
      );
      return false;
    }
    if (!this.form.relationshipId) {
      this.showToast(
        "Validação",
        "A relação com contraparte é obrigatória.",
        "error"
      );
      return false;
    }
    if (
      this.form.startDate &&
      this.form.endDate &&
      this.form.endDate < this.form.startDate
    ) {
      this.showToast(
        "Validação",
        "A data de término não pode ser anterior à data de início.",
        "error"
      );
      return false;
    }
    return true;
  }

  extractErrorMessage(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (error && error.message) {
      return error.message;
    }
    return "Ocorreu um erro desconhecido.";
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  get modalTitle() {
    return this.isEditing
      ? "Editar Rascunho do Contrato"
      : "Novo Contrato em Rascunho";
  }

  get hasContracts() {
    return this.contracts && this.contracts.length > 0;
  }
}
