import LANG from "@salesforce/i18n/lang";
import typeLabel from "@salesforce/label/c.AXF_ManualEntry_typeLabel";
import typeSingle from "@salesforce/label/c.AXF_ManualEntry_typeSingle";
import typeInstallment from "@salesforce/label/c.AXF_ManualEntry_typeInstallment";
import typeRecurring from "@salesforce/label/c.AXF_ManualEntry_typeRecurring";
import typeConsortium from "@salesforce/label/c.AXF_ManualEntry_typeConsortium";
import consortiumUnavailable from "@salesforce/label/c.AXF_ManualEntry_consortiumUnavailable";
import realizedLabel from "@salesforce/label/c.AXF_ManualEntry_realizedLabel";
import realizedHelp from "@salesforce/label/c.AXF_ManualEntry_realizedHelp";
import sourceCurrentAccount from "@salesforce/label/c.AXF_ManualEntry_sourceCurrentAccount";
import sourceCard from "@salesforce/label/c.AXF_ManualEntry_sourceCard";
import sourceWallet from "@salesforce/label/c.AXF_ManualEntry_sourceWallet";
import accountOptionLabel from "@salesforce/label/c.AXF_ManualEntry_accountOptionLabel";
import cardOptionLabel from "@salesforce/label/c.AXF_ManualEntry_cardOptionLabel";
import walletOptionLabel from "@salesforce/label/c.AXF_ManualEntry_walletOptionLabel";
import noOriginOfKind from "@salesforce/label/c.AXF_ManualEntry_noOriginOfKind";
import originRequired from "@salesforce/label/c.AXF_ManualEntry_originRequired";
import connectedHint from "@salesforce/label/c.AXF_ManualEntry_connectedHint";
import scheduleRedirect from "@salesforce/label/c.AXF_ManualEntry_scheduleRedirect";
import continueSchedule from "@salesforce/label/c.AXF_ManualEntry_continueSchedule";
import reviewType from "@salesforce/label/c.AXF_ManualEntry_reviewType";
import reviewSituation from "@salesforce/label/c.AXF_ManualEntry_reviewSituation";
import situationPlanned from "@salesforce/label/c.AXF_ManualEntry_situationPlanned";
import situationRealized from "@salesforce/label/c.AXF_ManualEntry_situationRealized";
import factPanelTitle from "@salesforce/label/c.AXF_ManualEntry_factPanelTitle";
import reconcileNowTitle from "@salesforce/label/c.AXF_ManualEntry_reconcileNowTitle";
import factRequired from "@salesforce/label/c.AXF_ManualEntry_factRequired";
import noReconcilePermission from "@salesforce/label/c.AXF_ManualEntry_noReconcilePermission";
import suggestionsTitle from "@salesforce/label/c.AXF_ManualEntry_suggestionsTitle";
import noSuggestions from "@salesforce/label/c.AXF_ManualEntry_noSuggestions";
import tied from "@salesforce/label/c.AXF_ManualEntry_tied";
import searchTitle from "@salesforce/label/c.AXF_ManualEntry_searchTitle";
import searchHelp from "@salesforce/label/c.AXF_ManualEntry_searchHelp";
import searchFrom from "@salesforce/label/c.AXF_ManualEntry_searchFrom";
import searchTo from "@salesforce/label/c.AXF_ManualEntry_searchTo";
import searchTerm from "@salesforce/label/c.AXF_ManualEntry_searchTerm";
import searchAction from "@salesforce/label/c.AXF_ManualEntry_searchAction";
import noResults from "@salesforce/label/c.AXF_ManualEntry_noResults";
import truncated from "@salesforce/label/c.AXF_ManualEntry_truncated";
import factText from "@salesforce/label/c.AXF_ManualEntry_factText";
import select from "@salesforce/label/c.AXF_ManualEntry_select";
import selectFor from "@salesforce/label/c.AXF_ManualEntry_selectFor";
import selected from "@salesforce/label/c.AXF_ManualEntry_selected";
import reconcileAction from "@salesforce/label/c.AXF_ManualEntry_reconcileAction";
import reconcileFor from "@salesforce/label/c.AXF_ManualEntry_reconcileFor";
import reconciled from "@salesforce/label/c.AXF_ManualEntry_reconciled";
import partiallyReconciled from "@salesforce/label/c.AXF_ManualEntry_partiallyReconciled";
import realizedDone from "@salesforce/label/c.AXF_ManualEntry_realizedDone";
import realizedLinkedDone from "@salesforce/label/c.AXF_ManualEntry_realizedLinkedDone";
import periodInvalid from "@salesforce/label/c.AXF_ManualEntry_periodInvalid";
import codeCONFLICT from "@salesforce/label/c.AXF_ManualEntry_codeCONFLICT";
import codeALREADY_LINKED from "@salesforce/label/c.AXF_ManualEntry_codeALREADY_LINKED";
import codeFACT_REQUIRED from "@salesforce/label/c.AXF_ManualEntry_codeFACT_REQUIRED";
import codeFACT_MISMATCH from "@salesforce/label/c.AXF_ManualEntry_codeFACT_MISMATCH";
import codeUNAVAILABLE_AMOUNT from "@salesforce/label/c.AXF_ManualEntry_codeUNAVAILABLE_AMOUNT";
import codeNOT_ACCESSIBLE from "@salesforce/label/c.AXF_BankStatement_codeNOT_ACCESSIBLE";
import codeUNAVAILABLE from "@salesforce/label/c.AXF_BankStatement_codeUNAVAILABLE";
import codeINVALID_INPUT from "@salesforce/label/c.AXF_BankStatement_codeINVALID_INPUT";
import codeEXHAUSTED from "@salesforce/label/c.AXF_BankStatement_codeEXHAUSTED";
import codeREVIEW_OPEN from "@salesforce/label/c.AXF_BankStatement_codeREVIEW_OPEN";
import error from "@salesforce/label/c.AXF_BankStatement_error";

const PT = {
  trackConfirmation: "Acompanhar confirmação",
  title: "Adicionar Receita ou Despesa",
  forbidden: "Você não tem autorização para lançar nesta pessoa ou empresa.",
  stepContext: "Contexto",
  stepDetails: "Detalhes",
  stepSource: "Origem",
  stepReview: "Revisar",
  stepOf: "Etapa {0} de {1}",
  contextLabel: "Pessoa ou empresa",
  contextPlaceholder: "Selecione um contexto",
  noContext: "Nenhuma pessoa ou empresa autorizada está disponível.",
  natureLabel: "Natureza",
  natureIncome: "Receita",
  natureExpense: "Despesa",
  amountLabel: "Valor",
  currencyLabel: "Moeda (ISO)",
  purchaseDateLabel: "Data de competência",
  dueDateLabel: "Vencimento (opcional)",
  sourceLabel: "Origem do lançamento",
  back: "Voltar",
  next: "Próximo",
  confirm: "Confirmar",
  cancel: "Cancelar",
  confirming: "Confirmando…",
  reviewTitle: "Revise antes de confirmar",
  reviewNature: "Natureza",
  reviewAmount: "Valor",
  reviewDate: "Competência",
  reviewSource: "Origem",
  done: "Lançamento criado.",
  alreadyDone: "Este lançamento já havia sido confirmado.",
  conflict:
    "Este lançamento foi alterado em outra tentativa. Cancele e comece novamente antes de confirmar.",
  invalid: "Revise os campos destacados antes de confirmar.",
  newEntry: "Novo lançamento"
};

const EN = {
  trackConfirmation: "Track confirmation",
  title: "Add Income or Expense",
  forbidden:
    "You are not authorized to post an entry for this person or company.",
  stepContext: "Context",
  stepDetails: "Details",
  stepSource: "Source",
  stepReview: "Review",
  stepOf: "Step {0} of {1}",
  contextLabel: "Person or company",
  contextPlaceholder: "Select a context",
  noContext: "No authorized person or company is available.",
  natureLabel: "Nature",
  natureIncome: "Income",
  natureExpense: "Expense",
  amountLabel: "Amount",
  currencyLabel: "Currency (ISO)",
  purchaseDateLabel: "Accounting date",
  dueDateLabel: "Due date (optional)",
  sourceLabel: "Entry source",
  back: "Back",
  next: "Next",
  confirm: "Confirm",
  cancel: "Cancel",
  confirming: "Confirming…",
  reviewTitle: "Review before confirming",
  reviewNature: "Nature",
  reviewAmount: "Amount",
  reviewDate: "Accounting date",
  reviewSource: "Source",
  done: "Entry created.",
  alreadyDone: "This entry was already confirmed.",
  conflict:
    "This entry changed in another attempt. Cancel and start again before confirming.",
  invalid: "Review the highlighted fields before confirming.",
  newEntry: "New entry"
};

// AXF-153: every new text comes from a Custom Label (base en_US + pt_BR translation).
const CUSTOM = {
  typeLabel,
  typeSingle,
  typeInstallment,
  typeRecurring,
  typeConsortium,
  consortiumUnavailable,
  realizedLabel,
  realizedHelp,
  sourceCurrentAccount,
  sourceCard,
  sourceWallet,
  accountOptionLabel,
  cardOptionLabel,
  walletOptionLabel,
  noOriginOfKind,
  originRequired,
  connectedHint,
  scheduleRedirect,
  continueSchedule,
  reviewType,
  reviewSituation,
  situationPlanned,
  situationRealized,
  factPanelTitle,
  reconcileNowTitle,
  factRequired,
  noReconcilePermission,
  suggestionsTitle,
  noSuggestions,
  tied,
  searchTitle,
  searchHelp,
  searchFrom,
  searchTo,
  searchTerm,
  searchAction,
  noResults,
  truncated,
  factText,
  select,
  selectFor,
  selected,
  reconcileAction,
  reconcileFor,
  reconciled,
  partiallyReconciled,
  realizedDone,
  realizedLinkedDone,
  periodInvalid,
  codeCONFLICT,
  codeALREADY_LINKED,
  codeFACT_REQUIRED,
  codeFACT_MISMATCH,
  codeUNAVAILABLE_AMOUNT,
  codeNOT_ACCESSIBLE,
  codeUNAVAILABLE,
  codeINVALID_INPUT,
  codeEXHAUSTED,
  codeREVIEW_OPEN,
  error
};

const EMBEDDED = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;
const L = { ...EMBEDDED, ...CUSTOM };
export default L;
