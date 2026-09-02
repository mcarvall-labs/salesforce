import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getContexts from "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts";
import { MessageContext, publish } from "lightning/messageService";
import CONTEXT_CHANGED from "@salesforce/messageChannel/AXF_ContextChanged__c";

const L = {
  TITLE: "Contexto financeiro",
  LABEL: "Pessoa ou empresa",
  PLACEHOLDER: "Selecione um contexto",
  EMPTY: "Nenhuma pessoa ou empresa autorizada está disponível.",
  ERROR: "Não foi possível carregar os contextos autorizados.",
  RETRY: "Tentar novamente",
  CHANGED: "Contexto alterado para",
};

export default class AxfContextBar extends LightningElement {
  labels = L;
  contexts = [];
  selectedId;
  loading = true;
  error = false;
  announcement;
  selectionVersion = 0;
  wiredResult;

  @wire(MessageContext) messageContext;

  @wire(getContexts)
  wiredContexts(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (error) {
      this.loading = false;
      this.error = true;
      this.contexts = [];
      this.selectedId = undefined;
      return;
    }
    if (!data) return;
    this.contexts = data;
    this.error = false;
    this.loading = false;
    if (data.length === 1) {
      this.selectContext(data[0]);
    }
  }

  get options() {
    return this.contexts.map((item) => ({
      label: item.label,
      value: item.accountId,
    }));
  }

  get isEmpty() {
    return !this.loading && !this.error && this.contexts.length === 0;
  }

  get isReady() {
    return !this.loading && !this.error && this.contexts.length > 0;
  }

  handleChange(event) {
    const context = this.contexts.find(
      (item) => item.accountId === event.detail.value,
    );
    if (context) this.selectContext(context);
  }

  selectContext(context) {
    this.selectedId = context.accountId;
    this.selectionVersion += 1;
    this.announcement = `${L.CHANGED} ${context.label}.`;
    const detail = {
      accountId: context.accountId,
      contextType: context.contextType,
      label: context.label,
      presentationCurrency: context.presentationCurrency,
      selectionVersion: this.selectionVersion,
    };
    publish(this.messageContext, CONTEXT_CHANGED, detail);
    this.dispatchEvent(new CustomEvent("contextchange", { detail }));
  }

  handleRetry() {
    this.loading = true;
    this.error = false;
    Promise.resolve(refreshApex(this.wiredResult)).catch(() => {
      this.loading = false;
      this.error = true;
    });
  }
}
