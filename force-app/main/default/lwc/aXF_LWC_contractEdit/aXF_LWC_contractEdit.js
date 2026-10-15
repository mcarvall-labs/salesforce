import { LightningElement, api, wire } from "lwc";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import preview from "@salesforce/apex/AXF_CLS_CTRL_ContractScope.preview";
import save from "@salesforce/apex/AXF_CLS_CTRL_ContractScope.save";

const OBJECT = "AXF_OBJ_Contract__c";
const RECORD_FIELDS = [
  "Name",
  "AXF_CTR_CUR_Amount__c",
  "AXF_CTR_CUR_FinancedAmount__c",
  "AXF_CTR_NUM_DueDay__c",
  "AXF_CTR_DAT_FirstDueDate__c",
  "AXF_CTR_NUM_InstallmentCount__c",
  "AXF_CTR_LKP_Category__c",
  "AXF_CTR_LKP_BankAccount__c",
  "AXF_CTR_LKP_CreditCard__c",
  "AXF_CTR_TXT_Counterparty__c",
  "RecordType.DeveloperName"
].map((field) => `${OBJECT}.${field}`);

const FIELD = {
  name: {
    api: "Name",
    label: "Nome",
    kind: "text",
    scopeField: "NAME",
    required: true
  },
  amount: {
    api: "AXF_CTR_CUR_Amount__c",
    label: "Valor da parcela",
    kind: "number",
    money: true,
    scopeField: "AMOUNT",
    required: true
  },
  financed: {
    api: "AXF_CTR_CUR_FinancedAmount__c",
    label: "Valor financiado",
    kind: "number",
    money: true,
    scopeField: "AMOUNT",
    required: true
  },
  dueDay: {
    api: "AXF_CTR_NUM_DueDay__c",
    label: "Dia de vencimento",
    kind: "number",
    scopeField: "DUE"
  },
  firstDue: {
    api: "AXF_CTR_DAT_FirstDueDate__c",
    label: "Primeiro vencimento",
    kind: "date",
    scopeField: "DUE",
    required: true
  },
  count: {
    api: "AXF_CTR_NUM_InstallmentCount__c",
    label: "Nº de parcelas",
    kind: "number",
    required: true
  },
  category: {
    api: "AXF_CTR_LKP_Category__c",
    label: "Categoria",
    kind: "lookup",
    object: "AXF_OBJ_Category__c",
    scopeField: "CATEGORY"
  },
  bank: {
    api: "AXF_CTR_LKP_BankAccount__c",
    label: "Conta bancária",
    kind: "lookup",
    object: "AXF_OBJ_BankAccount__c",
    scopeField: "ACCOUNT"
  },
  card: {
    api: "AXF_CTR_LKP_CreditCard__c",
    label: "Cartão de crédito",
    kind: "lookup",
    object: "AXF_OBJ_CreditCard__c",
    scopeField: "ACCOUNT"
  },
  counterparty: {
    api: "AXF_CTR_TXT_Counterparty__c",
    label: "Contraparte",
    kind: "text"
  }
};

const COMMON = ["category", "bank", "card", "counterparty"];
const FIELDS_BY_TYPE = {
  AXF_Recurring: ["name", "amount", "dueDay", ...COMMON],
  AXF_Installment: ["name", "amount", "firstDue", "count", ...COMMON],
  AXF_Consortium: ["name", "amount", "firstDue", "count", ...COMMON],
  AXF_Financing: ["name", "financed", "firstDue", "count", ...COMMON]
};

const SCOPE_LABEL = {
  AMOUNT: "Valor",
  NAME: "Nome",
  DUE: "Vencimento",
  CATEGORY: "Categoria",
  ACCOUNT: "Conta / Cartão"
};

const SCOPE_OPTIONS = [
  { label: "Todas as pendentes", value: "ALL" },
  { label: "Somente as futuras (após hoje)", value: "FUTURE" },
  { label: "A partir da parcela…", value: "FROM" },
  { label: "Somente a parcela do mês atual", value: "MONTH" },
  { label: "Somente as vencidas", value: "OVERDUE" },
  { label: "Nenhuma (só o Contrato)", value: "NONE" }
];

const STATUS_LABEL = { Pending: "Pendente", Realized: "Realizado" };
const OUTCOME_LABEL = {
  UPDATE: "Atualiza",
  KEEP: "Não altera",
  PRESERVED: "Preservado"
};

const normalize = (value) => {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  return String(value);
};

const definitionOf = (apiName) =>
  Object.values(FIELD).find((item) => item.api === apiName);

export default class AXF_LWC_contractEdit extends LightningElement {
  @api recordId;

  step = 1;
  recordType;
  original = {};
  values = {};
  scopes = {};
  previewData;
  loading = false;
  saving = false;
  loaded = false;
  requestId = 0;

  @wire(getRecord, { recordId: "$recordId", fields: RECORD_FIELDS })
  wiredRecord({ data, error }) {
    if (data) {
      this.recordType =
        data.fields.RecordType?.value?.fields?.DeveloperName?.value;
      const original = {};
      Object.values(FIELD).forEach((def) => {
        original[def.api] = normalize(data.fields[def.api]?.value);
      });
      this.original = original;
      this.values = { ...original };
      this.loaded = true;
    } else if (error) {
      this.toast("error", "Não foi possível carregar o contrato.");
    }
  }

  get isStep1() {
    return this.step === 1;
  }

  get isStep2() {
    return this.step === 2;
  }

  get supported() {
    return this.loaded && !!FIELDS_BY_TYPE[this.recordType];
  }

  get unsupported() {
    return this.loaded && !FIELDS_BY_TYPE[this.recordType];
  }

  get formFields() {
    return (FIELDS_BY_TYPE[this.recordType] || []).map((key) => {
      const def = FIELD[key];
      const value = this.values[def.api];
      return {
        ...def,
        value,
        isText: def.kind === "text",
        isNumber: def.kind === "number",
        isDate: def.kind === "date",
        isLookup: def.kind === "lookup",
        step: def.money ? "0.01" : "1",
        className: normalize(value) !== this.original[def.api] ? "changed" : ""
      };
    });
  }

  get changedApis() {
    return (FIELDS_BY_TYPE[this.recordType] || [])
      .map((key) => FIELD[key])
      .filter(
        (def) => normalize(this.values[def.api]) !== this.original[def.api]
      )
      .map((def) => def.api);
  }

  get formInvalid() {
    return (FIELDS_BY_TYPE[this.recordType] || []).some((key) => {
      const def = FIELD[key];
      const value = normalize(this.values[def.api]);
      if (def.required && value === null) {
        return true;
      }
      return def.kind === "number" && def.required && Number(value) <= 0;
    });
  }

  get continueDisabled() {
    return this.changedApis.length === 0 || this.formInvalid;
  }

  get scopeSections() {
    const sections = [];
    this.changedApis.forEach((apiName) => {
      const def = definitionOf(apiName);
      if (!def.scopeField) {
        return;
      }
      let section = sections.find((item) => item.key === def.scopeField);
      if (!section) {
        const choice = this.scopes[def.scopeField] || {};
        section = {
          key: def.scopeField,
          label: SCOPE_LABEL[def.scopeField],
          changes: [],
          scope: choice.scope,
          fromNumber: choice.fromNumber,
          showFrom: choice.scope === "FROM"
        };
        sections.push(section);
      }
      section.changes.push(this.describeChange(def));
    });
    return sections;
  }

  get unscopedChanges() {
    return this.changedApis
      .map(definitionOf)
      .filter((def) => !def.scopeField)
      .map((def) => this.describeChange(def));
  }

  get hasUnscopedChanges() {
    return this.unscopedChanges.length > 0;
  }

  get scopeOptions() {
    return SCOPE_OPTIONS;
  }

  get previewRows() {
    return (this.previewData?.rows || []).map((row) => ({
      ...row,
      key: row.entryId,
      className: `outcome-${String(row.outcome).toLowerCase()}`,
      statusLabel: STATUS_LABEL[row.status] || row.status,
      outcomeLabel: OUTCOME_LABEL[row.outcome] || row.outcome,
      nameChanged: row.name !== row.newName,
      dueChanged: row.dueDate !== row.newDueDate,
      amountChanged: row.amount !== row.newAmount,
      amountText: this.money(row.amount),
      newAmountText: this.money(row.newAmount),
      dueText: this.date(row.dueDate),
      newDueText: this.date(row.newDueDate)
    }));
  }

  get hasPreview() {
    return !!this.previewData;
  }

  get hasMissing() {
    return (this.previewData?.missing || 0) > 0;
  }

  get saveDisabled() {
    return this.saving || this.loading || !this.previewData;
  }

  describeChange(def) {
    if (def.kind === "lookup") {
      return { key: def.api, label: def.label, text: "alterado" };
    }
    const show = (value) => {
      if (value === null) {
        return "(vazio)";
      }
      if (def.money) {
        return this.money(value);
      }
      return def.kind === "date" ? this.date(value) : value;
    };
    return {
      key: def.api,
      label: def.label,
      text: `${show(this.original[def.api])} → ${show(normalize(this.values[def.api]))}`
    };
  }

  money(value) {
    if (value === null || value === undefined) {
      return "";
    }
    return `R$ ${Number(value).toFixed(2).replace(".", ",")}`;
  }

  date(value) {
    if (!value) {
      return "";
    }
    const [year, month, day] = String(value).split("-");
    return `${day}/${month}/${year}`;
  }

  handleInput(event) {
    const apiName = event.target.dataset.api;
    this.values = { ...this.values, [apiName]: normalize(event.detail.value) };
  }

  handleLookup(event) {
    const apiName = event.target.dataset.api;
    this.values = {
      ...this.values,
      [apiName]: normalize(event.detail.recordId)
    };
  }

  handleRestore() {
    this.values = { ...this.original };
  }

  async handleContinue() {
    const scopes = {};
    this.changedApis.forEach((apiName) => {
      const def = definitionOf(apiName);
      if (def.scopeField && !scopes[def.scopeField]) {
        scopes[def.scopeField] = { scope: "FUTURE", fromNumber: null };
      }
    });
    this.scopes = scopes;
    this.step = 2;
    await this.refreshPreview();
  }

  handleBack() {
    this.requestId++;
    this.step = 1;
    this.previewData = undefined;
    this.loading = false;
  }

  async handleScope(event) {
    const key = event.target.dataset.key;
    this.scopes = {
      ...this.scopes,
      [key]: { scope: event.detail.value, fromNumber: null }
    };
    await this.refreshPreview();
  }

  async handleFrom(event) {
    const key = event.target.dataset.key;
    this.scopes = {
      ...this.scopes,
      [key]: { ...this.scopes[key], fromNumber: event.detail.value }
    };
    await this.refreshPreview();
  }

  payload() {
    const values = {};
    this.changedApis.forEach((apiName) => {
      values[apiName] = normalize(this.values[apiName]);
    });
    const scopes = {};
    Object.keys(this.scopes).forEach((key) => {
      const choice = this.scopes[key];
      scopes[key] = {
        scope: choice.scope,
        fromNumber: normalize(choice.fromNumber)
      };
    });
    return { contractId: this.recordId, values, scopes };
  }

  async refreshPreview() {
    const current = ++this.requestId;
    const fromMissing = Object.values(this.scopes).some(
      (choice) =>
        choice.scope === "FROM" && normalize(choice.fromNumber) === null
    );
    if (fromMissing) {
      this.previewData = undefined;
      this.loading = false;
      return;
    }
    this.loading = true;
    try {
      const result = await preview(this.payload());
      if (current === this.requestId) {
        this.previewData = result;
      }
    } catch (error) {
      if (current === this.requestId) {
        this.previewData = undefined;
        this.toast("error", this.message(error));
      }
    } finally {
      if (current === this.requestId) {
        this.loading = false;
      }
    }
  }

  async handleSave() {
    this.saving = true;
    try {
      const summary = await save(this.payload());
      const created = summary.created ? ` ${summary.created} criado(s).` : "";
      this.toast(
        "success",
        `Contrato salvo. ${summary.updated ?? 0} Lançamento(s) atualizado(s).${created}`
      );
      try {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      } catch {
        // The toast already reported the result; a failed refresh is not an error.
      }
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (error) {
      this.toast("error", this.message(error));
    } finally {
      this.saving = false;
    }
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  message(error) {
    return error?.body?.message || "Não foi possível editar o contrato.";
  }

  toast(variant, message) {
    this.dispatchEvent(
      new ShowToastEvent({ title: "Editar contrato", message, variant })
    );
  }
}
