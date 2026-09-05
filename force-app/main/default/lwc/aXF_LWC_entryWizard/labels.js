import LANG from "@salesforce/i18n/lang";

const PT = {
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
  sourceCash: "Dinheiro",
  sourceBank: "Conta bancária",
  sourceCard: "Cartão de crédito",
  sourceOptionLabel: "Selecione a conta ou cartão",
  noSources: "Nenhuma conta ou cartão disponível para esta pessoa ou empresa.",
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
  sourceCash: "Cash",
  sourceBank: "Bank account",
  sourceCard: "Credit card",
  sourceOptionLabel: "Select the account or card",
  noSources: "No account or card is available for this person or company.",
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

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;
export default L;
