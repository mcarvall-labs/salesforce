import { LightningElement, api } from "lwc";
import listEntities from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.listEntities";
import readEntity from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.readEntity";
import updateEntity from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.updateEntity";
import createEntity from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntity.createEntity";

export default class AxfFinancialEntities extends LightningElement {
  state = "LOADING";
  entities = [];
  selected;
  errorMessage;
  saving = false;
  creating = false;
  createDraft = { kind: "PERSON", legalName: "", displayName: "" };

  connectedCallback() {
    this.load();
  }

  async load() {
    this.state = "LOADING";
    this.entities = [];
    this.selected = undefined;
    try {
      const response = await listEntities();
      this.state = response.state;
      this.entities = response.state === "READY_DATA" ? response.entities : [];
      if (response.state === "ERROR_TERMINAL")
        this.errorMessage =
          "Ocorreu um erro terminal ao carregar as entidades.";
    } catch {
      this.state = "ERROR_RECOVERABLE";
      this.errorMessage =
        "Não foi possível carregar as entidades. Tente novamente.";
    }
  }

  async handleSelect(event) {
    const entityRef = event.currentTarget.dataset.ref;
    this.state = "LOADING";
    this.selected = undefined;
    try {
      const response = await readEntity({ entityRef });
      this.state = response.state;
      if (response.state === "READY_DATA") this.selected = response.detail;
    } catch {
      this.state = "FORBIDDEN";
    }
  }

  handleRetry() {
    this.load();
  }

  handleChange(event) {
    this.selected = {
      ...this.selected,
      [event.target.name]: event.detail.value
    };
  }

  handleCreateChange(event) {
    this.createDraft = {
      ...this.createDraft,
      [event.target.name]: event.detail.value
    };
  }

  startCreate() {
    this.createDraft = { kind: "PERSON", legalName: "", displayName: "" };
    this.creating = true;
    this.selected = undefined;
  }

  cancelCreate() {
    this.creating = false;
    this.createDraft = { kind: "PERSON", legalName: "", displayName: "" };
  }

  async handleCreate(event) {
    event.preventDefault();
    this.saving = true;
    try {
      const uuid = this.uuid();
      await createEntity({
        request: {
          ...this.createDraft,
          householdId: this.householdId,
          entityKey: `fie-v1:${uuid}`,
          idempotencyKey: this.uuid(),
          correlationId: this.uuid()
        }
      });
      this.creating = false;
      await this.load();
    } catch (error) {
      this.applyMutationError(error);
      this.creating = false;
      this.createDraft = { kind: "PERSON", legalName: "", displayName: "" };
    } finally {
      this.saving = false;
    }
  }

  async handleSave(event) {
    event.preventDefault();
    this.saving = true;
    this.errorMessage = undefined;
    try {
      const result = await updateEntity({
        request: {
          entityRef: this.selected.entityRef,
          displayName: this.selected.displayName,
          legalName: this.selected.legalName,
          lifecycle: this.selected.lifecycle,
          activeTo: this.selected.activeTo,
          expectedVersion: this.selected.version,
          idempotencyKey: this.uuid(),
          correlationId: this.uuid()
        }
      });
      this.selected = { ...this.selected, ...result };
      this.entities = this.entities.map((item) => {
        return item.entityRef === result.entityRef
          ? { ...item, ...result }
          : item;
      });
      this.state = "READY_DATA";
      this.template.querySelector(".detail")?.focus();
    } catch (error) {
      this.applyMutationError(error);
    } finally {
      this.saving = false;
    }
  }

  applyMutationError(error) {
    const code = error?.body?.message || error?.message || "ERROR_TERMINAL";
    if (code.includes("CONFLICT")) {
      this.state = "CONFLICT";
      this.errorMessage =
        "A entidade foi alterada. Recarregue antes de tentar novamente.";
    } else if (code.includes("FORBIDDEN")) {
      this.state = "FORBIDDEN";
      this.entities = [];
      this.selected = undefined;
      this.creating = false;
      this.createDraft = { kind: "PERSON", legalName: "", displayName: "" };
    } else {
      this.state =
        error?.body?.exceptionType === "System.CalloutException"
          ? "ERROR_RECOVERABLE"
          : "ERROR_TERMINAL";
      this.errorMessage = "Não foi possível concluir a operação.";
    }
  }

  uuid() {
    if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
    if (!globalThis.crypto?.getRandomValues)
      throw new Error("SECURE_RANDOM_UNAVAILABLE");
    const bytes = new Uint8Array(16);
    globalThis.crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map((value) => value.toString(16).padStart(2, "0"));
    return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
  }

  get loading() {
    return this.state === "LOADING";
  }
  get empty() {
    return this.state === "READY_EMPTY";
  }
  get ready() {
    return this.state === "READY_DATA";
  }
  get forbidden() {
    return this.state === "FORBIDDEN";
  }
  get recoverableError() {
    return this.state === "ERROR_RECOVERABLE";
  }
  get conflict() {
    return this.state === "CONFLICT";
  }
  get lifecycleOptions() {
    return [
      { label: "Ativa", value: "ACTIVE" },
      { label: "Suspensa", value: "SUSPENDED" },
      { label: "Encerrada", value: "CLOSED" }
    ];
  }
  get kindOptions() {
    return [
      { label: "Pessoa", value: "PERSON" },
      { label: "Organização", value: "ORGANIZATION" }
    ];
  }
  get closedLifecycle() {
    return this.selected?.lifecycle === "CLOSED";
  }
  get terminalError() {
    return this.state === "ERROR_TERMINAL";
  }
  get canEditLegalName() {
    return (
      this.selected &&
      Object.prototype.hasOwnProperty.call(this.selected, "legalName")
    );
  }
  get cannotCreate() {
    return !this.householdId;
  }

  @api householdId;
}
