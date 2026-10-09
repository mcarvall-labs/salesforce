import { LightningElement, wire } from "lwc";
import {
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import INVOICE_SELECTED from "@salesforce/messageChannel/AXF_MC_InvoiceSelected__c";

export default class AXF_LWC_invoiceDetails extends LightningElement {
  invoice;
  subscription;

  @wire(MessageContext)
  messageContext;

  connectedCallback() {
    this.subscription = subscribe(
      this.messageContext,
      INVOICE_SELECTED,
      (message) => {
        this.invoice = message;
      }
    );
  }

  disconnectedCallback() {
    unsubscribe(this.subscription);
    this.subscription = undefined;
  }
}
