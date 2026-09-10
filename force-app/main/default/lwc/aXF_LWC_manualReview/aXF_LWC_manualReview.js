import { LightningElement } from "lwc";
import LANG from "@salesforce/i18n/lang";
import listPending from "@salesforce/apex/AXF_CLS_CTRL_ManualReview.listPending";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_ManualReview.confirm";
const en = String(LANG).toLowerCase().startsWith("en");
export default class ManualReview extends LightningElement {
  labels = en
    ? {
        title: "Manual confirmations",
        refresh: "Refresh",
        empty: "No pending confirmations.",
        note: "Confirmation reason",
        confirm: "Confirm entry",
        reason: "Confirmation requested when this entry was created.",
        holder: "Holder",
        entry: "Entry",
        error:
          "Unable to confirm or load. Refresh and review current access and version before retrying.",
        done: "Confirmation recorded.",
        loading: "Loading confirmations"
      }
    : {
        title: "Confirmações manuais",
        refresh: "Atualizar",
        empty: "Nenhuma confirmação pendente.",
        note: "Motivo da confirmação",
        confirm: "Confirmar lançamento",
        reason: "Confirmação solicitada na criação deste lançamento.",
        holder: "Titular",
        entry: "Lançamento",
        error:
          "Não foi possível confirmar ou carregar. Atualize e confira o acesso e a versão antes de tentar novamente.",
        done: "Confirmação registrada.",
        loading: "Carregando confirmações"
      };
  items = [];
  busy = false;
  feedback = "";
  notes = {};
  connectedCallback() {
    this.refresh();
  }
  get empty() {
    return !this.busy && this.items.length === 0;
  }
  async refresh() {
    if (this.busy) return;
    this.busy = true;
    this.feedback = "";
    try {
      this.items = JSON.parse(await listPending()).map((i) => ({
        ...i,
        entryUrl: "/" + i.financialTransactionId,
        holderUrl: "/" + i.accountId
      }));
    } catch {
      this.items = [];
      this.feedback = this.labels.error;
    } finally {
      this.busy = false;
    }
  }
  handleNote(event) {
    this.notes = {
      ...this.notes,
      [event.target.dataset.id]: event.target.value
    };
  }
  async handleConfirm(event) {
    if (this.busy) return;
    const id = event.target.dataset.id,
      item = this.items.find((i) => i.reviewItemId === id),
      note = this.notes[id];
    if (!item || !note || !note.trim()) {
      this.feedback = this.labels.note;
      return;
    }
    this.busy = true;
    this.feedback = "";
    try {
      const result = JSON.parse(
        await confirm({ itemId: id, version: item.version, note })
      );
      if (!result.success) {
        this.feedback = this.labels.error;
        return;
      }
      this.items = this.items.filter((i) => i.reviewItemId !== id);
      this.feedback = this.labels.done;
    } catch {
      this.feedback = this.labels.error;
    } finally {
      this.busy = false;
    }
  }
}
