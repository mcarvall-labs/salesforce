import { LightningElement, track, wire } from "lwc";
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
import getTermVersionReview from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getTermVersionReview";
import getWorkRecords from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.getWorkRecords";
import registerWorkRecord from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.registerWorkRecord";
import submitWorkRecord from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.submitWorkRecord";
import decideWorkRecord from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.decideWorkRecord";
import correctApprovedWorkRecord from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.correctApprovedWorkRecord";
import assessContractWorkRecords from "@salesforce/apex/AXF_CLS_CTRL_ContractManagement.assessContractWorkRecords";

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

  // Estados para Termos e Remuneracao (AXF-54)
  @track termVersions = [];
  @track isTermModalOpen = false;
  @track schedulePreview = null;
  @track isReviewModalOpen = false;
  @track reviewData = null;
  @track termForm = {
    termVersionId: null,
    contractId: null,
    accountId: "",
    remunerationModel: "MONTHLY",
    currencyIsoCode: "BRL",
    effectiveFrom: null,
    effectiveTo: null,
    rate: null,
    hoursQuantity: null,
    contractedAmount: null,
    installments: null,
    proportionalityPolicy: "CALENDAR_DAYS",
    timeZone: "America/Sao_Paulo",
    calendarPolicy: "STANDARD_CALENDAR",
    version: 0
  };

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

  modelOptions = [
    { label: "Mensal (MONTHLY)", value: "MONTHLY" },
    { label: "Por Hora (HOURLY)", value: "HOURLY" },
    { label: "Fixo por Marcos/Parcelas (FIXED)", value: "FIXED" }
  ];

  prorationOptions = [
    { label: "Dias Corridos (CALENDAR_DAYS)", value: "CALENDAR_DAYS" },
    { label: "Dias Uteis (BUSINESS_DAYS)", value: "BUSINESS_DAYS" },
    { label: "Base 30 Dias (FIXED_30)", value: "FIXED_30" },
    { label: "Sem Proporcionalidade (NONE)", value: "NONE" }
  ];

  calendarOptions = [
    { label: "Calendario Padrao Contratado (STANDARD_CALENDAR)", value: "STANDARD_CALENDAR" },
    { label: "Dias Corridos (CALENDAR_DAYS)", value: "CALENDAR_DAYS" },
    { label: "Dias Uteis Brasil (BUSINESS_DAYS_BRAZIL)", value: "BUSINESS_DAYS_BRAZIL" },
    { label: "Regra Nao Contratada / Feriado Local (LOCAL_CUSTOM_HOLIDAYS)", value: "LOCAL_CUSTOM_HOLIDAYS" }
  ];

  get isModelMonthly() {
    return this.termForm.remunerationModel === "MONTHLY";
  }

  get isModelHourly() {
    return this.termForm.remunerationModel === "HOURLY";
  }

  get isModelFixed() {
    return this.termForm.remunerationModel === "FIXED";
  }

  get hasContracts() {
    return this.contracts && this.contracts.length > 0;
  }

  get hasTermVersions() {
    return this.termVersions && this.termVersions.length > 0;
  }

  get modalTitle() {
    return this.isEditing
      ? "Editar Rascunho de Contrato"
      : "Novo Contrato em Rascunho";
  }

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
    this.termVersions = [];
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
      await this.loadTermVersions(contractId);
      await this.loadWorkRecords(contractId);
    } catch (err) {
      this.showToast("Erro", this.extractErrorMessage(err), "error");
      this.selectedDetail = null;
    } finally {
      this.isLoading = false;
    }
  }

  async loadTermVersions(contractId) {
    try {
      const terms = await getTermVersions({
        contractId: contractId,
        accountId: this.selectedAccountId
      });
      this.termVersions = terms.map((tv) => ({
        ...tv,
        isActive: tv.status === "ACTIVE",
        isBlocked: tv.status === "BLOCKED",
        canActivate: tv.status !== "ACTIVE"
      }));
    } catch (err) {
      this.termVersions = [];
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
        "Nao ha relacoes ativas com contrapartes cadastradas para esta entidade.",
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

  // --- METODOS DE TERMO E REMUNERACAO (AXF-54) ---

  handleOpenTermModal() {
    if (!this.selectedDetail) return;
    this.schedulePreview = null;
    this.termForm = {
      termVersionId: null,
      contractId: this.selectedDetail.contractId,
      accountId: this.selectedAccountId,
      remunerationModel: "MONTHLY",
      currencyIsoCode: this.selectedDetail.currencyIsoCode || "BRL",
      effectiveFrom: this.selectedDetail.startDate || new Date().toISOString().split("T")[0],
      effectiveTo: this.selectedDetail.endDate,
      rate: 5000,
      hoursQuantity: null,
      contractedAmount: null,
      installments: null,
      proportionalityPolicy: "CALENDAR_DAYS",
      timeZone: "America/Sao_Paulo",
      calendarPolicy: "STANDARD_CALENDAR",
      version: 0
    };
    this.isTermModalOpen = true;
  }

  handleCloseTermModal() {
    this.isTermModalOpen = false;
    this.schedulePreview = null;
  }

  handleTermFormChange(event) {
    const field = event.target.name;
    const value = event.target.value;
    this.termForm[field] = value;

    if (field === "remunerationModel") {
      this.schedulePreview = null;
      if (value === "MONTHLY") {
        this.termForm.rate = 5000;
        this.termForm.proportionalityPolicy = "CALENDAR_DAYS";
        this.termForm.hoursQuantity = null;
        this.termForm.installments = null;
        this.termForm.contractedAmount = null;
      } else if (value === "HOURLY") {
        this.termForm.rate = 50;
        this.termForm.hoursQuantity = 160;
        this.termForm.proportionalityPolicy = null;
        this.termForm.installments = null;
        this.termForm.contractedAmount = null;
      } else if (value === "FIXED") {
        this.termForm.contractedAmount = 100;
        this.termForm.installments = 3;
        this.termForm.rate = null;
        this.termForm.hoursQuantity = null;
        this.termForm.proportionalityPolicy = null;
      }
    }
  }

  async handleCalculateSchedule() {
    this.isSaving = true;
    try {
      const payload = { ...this.termForm };
      this.schedulePreview = await calculateSchedulePreview({ payload });
      this.showToast(
        "Calculo Concluido",
        "Cronograma calculado com conservacao estrita e residual explicito (GF-04).",
        "success"
      );
    } catch (err) {
      this.showToast("Erro no Calculo", this.extractErrorMessage(err), "error");
    } finally {
      this.isSaving = false;
    }
  }

  async handleSaveTerm() {
    this.isSaving = true;
    try {
      const payload = { ...this.termForm };
      await saveDraftTermVersion({ payload });
      this.showToast("Sucesso", "Rascunho do termo contratual salvo com sucesso.", "success");
      this.isTermModalOpen = false;
      await this.loadTermVersions(this.selectedDetail.contractId);
    } catch (err) {
      this.showToast("Erro ao Salvar Termo", this.extractErrorMessage(err), "error");
    } finally {
      this.isSaving = false;
    }
  }

  async handleActivateTerm(event) {
    const termId = event.target.dataset.id;
    this.isLoading = true;
    try {
      const res = await activateTermVersion({
        termVersionId: termId,
        accountId: this.selectedAccountId
      });
      if (res.success) {
        this.showToast("Ativado", "Versao de termo ativada com sucesso.", "success");
      } else {
        this.showToast("Bloqueado (BLOCKED)", res.message, "error");
      }
      await this.loadTermVersions(this.selectedDetail.contractId);
    } catch (err) {
      this.showToast("Erro na Ativacao", this.extractErrorMessage(err), "error");
      await this.loadTermVersions(this.selectedDetail.contractId);
    } finally {
      this.isLoading = false;
    }
  }

  handleLifecycleAttempt() {
    this.showToast(
      "Acao Bloqueada",
      "Transicao de ciclo de vida bloqueada: operacao canonica de termino, cancelamento, ativacao ou substituicao ainda nao disponivel (AXF-52).",
      "warning"
    );
  }

  validateForm() {
    if (!this.form.contractCode || !this.form.contractCode.trim()) {
      this.showToast(
        "Validacao",
        "O codigo do contrato e obrigatorio.",
        "error"
      );
      return false;
    }
    if (!this.form.title || !this.form.title.trim()) {
      this.showToast(
        "Validacao",
        "O titulo do contrato e obrigatorio.",
        "error"
      );
      return false;
    }
    if (!this.form.relationshipId) {
      this.showToast(
        "Validacao",
        "A relacao contratual com contraparte e obrigatoria.",
        "error"
      );
      return false;
    }
    return true;
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }

  extractErrorMessage(error) {
    if (!error) return "Erro desconhecido";
    if (typeof error === "string") return error;
    if (error.body && error.body.message) return error.body.message;
    if (error.message) return error.message;
    return JSON.stringify(error);
  }
  // --- METODOS DE REVISAO FORMAL E ATIVACAO (AXF-53) ---

  async handleOpenReviewModal(event) {
    const termVersionId = event.target.dataset.id;
    if (!termVersionId) return;

    this.isLoading = true;
    try {
      const data = await getTermVersionReview({
        termVersionId: termVersionId,
        accountId: this.selectedAccountId
      });
      this.reviewData = data;
      this.isReviewModalOpen = true;
    } catch (error) {
      const msg = error.body ? error.body.message : error.message;
      this.showToast("Erro ao carregar revisao", msg, "error");
    } finally {
      this.isLoading = false;
    }
  }

  handleCloseReviewModal() {
    this.isReviewModalOpen = false;
    this.reviewData = null;
  }

  async handleConfirmReviewActivation() {
    if (!this.reviewData) return;

    this.isLoading = true;
    try {
      const result = await activateTermVersion({
        termVersionId: this.reviewData.termVersionId,
        accountId: this.selectedAccountId,
        expectedContractVersion: this.reviewData.contractVersion,
        expectedTermVersion: this.reviewData.version
      });

      if (result.success) {
        this.showToast("Sucesso", result.message, "success");
        this.handleCloseReviewModal();
        await this.loadTermVersions(this.selectedContractId);
        await this.loadContractDetail(this.selectedContractId);
      } else {
        this.showToast("Ativacao Bloqueada", result.message, "warning");
        this.handleCloseReviewModal();
        await this.loadTermVersions(this.selectedContractId);
      }
    } catch (error) {
      const msg = error.body ? error.body.message : error.message;
      this.showToast("Erro na ativacao", msg, "error");
    } finally {
      this.isLoading = false;
    }
  }

  // Estados para Registros de Trabalho (AXF-56)
  @track workRecords = [];
  @track isWorkRecordModalOpen = false;
  @track isCorrectionMode = false;
  @track correctionTargetId = null;
  @track correctionReason = "";
  @track wrForm = {
    workRecordId: null,
    contractId: null,
    termVersionId: null,
    startDate: null,
    endDate: null,
    quantity: null,
    rate: null,
    currencyIsoCode: "BRL",
    source: "MANUAL",
    description: ""
  };

  get hasWorkRecords() {
    return this.workRecords && this.workRecords.length > 0;
  }

  async loadWorkRecords(contractId) {
    const cId = contractId || this.selectedContractId;
    if (!cId) {
      this.workRecords = [];
      return;
    }
    try {
      const data = await getWorkRecords({ contractId: cId });
      this.workRecords = (data || []).map((wr) => ({
        ...wr,
        isDraft: wr.status === "DRAFT",
        isSubmitted: wr.status === "SUBMITTED",
        isApproved: wr.status === "APPROVED",
        isRejected: wr.status === "REJECTED",
        isSuperseded: wr.status === "SUPERSEDED",
        canSubmit: wr.status === "DRAFT" || wr.status === "REJECTED",
        canReview: wr.status === "SUBMITTED",
        canCorrect: wr.status === "APPROVED"
      }));
    } catch (error) {
      this.workRecords = [];
      this.errorMessage = error.body ? error.body.message : error.message;
    }
  }

  handleOpenWorkRecordModal() {
    this.isCorrectionMode = false;
    this.correctionTargetId = null;
    this.correctionReason = "";
    this.wrForm = {
      workRecordId: null,
      contractId: this.selectedContractId,
      termVersionId: null,
      startDate: new Date().toISOString().slice(0, 10),
      endDate: new Date().toISOString().slice(0, 10),
      quantity: 8,
      rate: 100,
      currencyIsoCode: this.selectedDetail ? this.selectedDetail.currencyIsoCode : "BRL",
      source: "MANUAL",
      description: ""
    };
    this.isWorkRecordModalOpen = true;
  }

  handleCloseWorkRecordModal() {
    this.isWorkRecordModalOpen = false;
  }

  handleWrStartDateChange(e) {
    this.wrForm.startDate = e.target.value;
  }

  handleWrEndDateChange(e) {
    this.wrForm.endDate = e.target.value;
  }

  handleWrQuantityChange(e) {
    this.wrForm.quantity = parseFloat(e.target.value);
  }

  handleWrRateChange(e) {
    this.wrForm.rate = parseFloat(e.target.value);
  }

  handleWrDescriptionChange(e) {
    this.wrForm.description = e.target.value;
  }

  handleCorrectionReasonChange(e) {
    this.correctionReason = e.target.value;
  }

  handleSaveWorkRecord() {
    if (!this.wrForm.startDate || !this.wrForm.endDate || !this.wrForm.quantity || !this.wrForm.rate) {
      this.errorMessage = "Preencha todos os campos obrigatorios do registro de trabalho.";
      return;
    }

    this.isLoading = true;
    if (this.isCorrectionMode) {
      if (!this.correctionReason) {
        this.errorMessage = "Motivo da correcao e obrigatorio.";
        this.isLoading = false;
        return;
      }
      correctApprovedWorkRecord({
        approvedWorkRecordId: this.correctionTargetId,
        replacementPayload: this.wrForm,
        correctionReason: this.correctionReason
      })
        .then(() => {
          this.isWorkRecordModalOpen = false;
          this.loadWorkRecords();
          this.dispatchEvent(new ShowToastEvent({ title: "Sucesso", message: "Registro de trabalho corrigido por substituicao.", variant: "success" }));
        })
        .catch((error) => {
          this.errorMessage = error.body ? error.body.message : error.message;
        })
        .finally(() => {
          this.isLoading = false;
        });
    } else {
      registerWorkRecord({ payload: this.wrForm })
        .then(() => {
          this.isWorkRecordModalOpen = false;
          this.loadWorkRecords();
          this.dispatchEvent(new ShowToastEvent({ title: "Sucesso", message: "Registro de trabalho salvo com sucesso.", variant: "success" }));
        })
        .catch((error) => {
          this.errorMessage = error.body ? error.body.message : error.message;
        })
        .finally(() => {
          this.isLoading = false;
        });
    }
  }

  handleSubmitWorkRecord(e) {
    const wrId = e.target.dataset.id;
    this.isLoading = true;
    submitWorkRecord({ workRecordId: wrId })
      .then(() => {
        this.loadWorkRecords();
        this.dispatchEvent(new ShowToastEvent({ title: "Sucesso", message: "Registro submetido para aprovacao.", variant: "info" }));
      })
      .catch((error) => {
        this.errorMessage = error.body ? error.body.message : error.message;
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  handleApproveWorkRecord(e) {
    const wrId = e.target.dataset.id;
    this.isLoading = true;
    decideWorkRecord({ workRecordId: wrId, approved: true, reason: "Aprovado pelo gestor" })
      .then(() => {
        this.loadWorkRecords();
        this.dispatchEvent(new ShowToastEvent({ title: "Aprovado", message: "Registro de trabalho aprovado.", variant: "success" }));
      })
      .catch((error) => {
        this.errorMessage = error.body ? error.body.message : error.message;
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  handleRejectWorkRecord(e) {
    const wrId = e.target.dataset.id;
    this.isLoading = true;
    decideWorkRecord({ workRecordId: wrId, approved: false, reason: "Rejeitado para revisao" })
      .then(() => {
        this.loadWorkRecords();
        this.dispatchEvent(new ShowToastEvent({ title: "Rejeitado", message: "Registro de trabalho rejeitado.", variant: "warning" }));
      })
      .catch((error) => {
        this.errorMessage = error.body ? error.body.message : error.message;
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  handleOpenCorrectionModal(e) {
    const wrId = e.target.dataset.id;
    const wr = this.workRecords.find((r) => r.workRecordId === wrId);
    if (!wr) return;

    this.isCorrectionMode = true;
    this.correctionTargetId = wrId;
    this.correctionReason = "";
    this.wrForm = {
      workRecordId: null,
      contractId: this.selectedContractId,
      termVersionId: wr.termVersionId,
      startDate: wr.startDate,
      endDate: wr.endDate,
      quantity: wr.quantity,
      rate: wr.rate,
      currencyIsoCode: wr.currencyIsoCode,
      source: "MANUAL",
      description: wr.description
    };
    this.isWorkRecordModalOpen = true;
  }

}