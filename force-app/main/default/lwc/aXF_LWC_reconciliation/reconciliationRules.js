// Pure rules of the reconciliation screen, kept out of the component so they can be tested alone.

const MONTHS = [
  "Janeiro",
  "Fevereiro",
  "Março",
  "Abril",
  "Maio",
  "Junho",
  "Julho",
  "Agosto",
  "Setembro",
  "Outubro",
  "Novembro",
  "Dezembro"
];

// Six months back to six months ahead of the given date; the current one is at index 6.
export function monthOptions(today) {
  const options = [];
  for (let offset = -6; offset <= 6; offset++) {
    const date = new Date(today.getFullYear(), today.getMonth() + offset, 1);
    const month = String(date.getMonth() + 1).padStart(2, "0");
    options.push({
      label: `${MONTHS[date.getMonth()]}/${date.getFullYear()}`,
      value: `${date.getFullYear()}-${month}`
    });
  }
  return options;
}

// invoice: the Entry of a card invoice (paid from the account); card: a card purchase;
// account: everything else.
export function entryKind(entry) {
  if (entry.cardId && entry.invoiceId) {
    return "invoice";
  }
  return entry.cardId ? "card" : "account";
}

// Card Entry only with card transactions, the others only with account transactions, expense with
// an outflow and income with an inflow, and the same account/card when the Entry names one.
export function isCompatible(entry, transaction) {
  const kind = entryKind(entry);
  const expectedSource = kind === "card" ? "card" : "account";
  if (transaction.source !== expectedSource) {
    return false;
  }
  if (
    entry.type === "Expense" ? transaction.amount >= 0 : transaction.amount <= 0
  ) {
    return false;
  }
  if (kind === "card" && entry.cardId !== transaction.sourceId) {
    return false;
  }
  if (
    kind === "account" &&
    entry.accountId &&
    entry.accountId !== transaction.sourceId
  ) {
    return false;
  }
  return true;
}

function matchesDates(filters, day) {
  if (filters.dateFrom && (!day || day < filters.dateFrom)) {
    return false;
  }
  if (filters.dateTo && (!day || day > filters.dateTo)) {
    return false;
  }
  return true;
}

function matchesCommon(filters, text, value, day) {
  if (!matchesDates(filters, day)) {
    return false;
  }
  if (
    filters.text &&
    !(text || "").toLowerCase().includes(filters.text.toLowerCase())
  ) {
    return false;
  }
  const amount = Math.abs(value || 0);
  if (filters.min !== "" && amount < Number(filters.min)) {
    return false;
  }
  if (filters.max !== "" && amount > Number(filters.max)) {
    return false;
  }
  return true;
}

// A source filter is "account:<id>" or "card:<id>"; the invoice Entry belongs to its card.
export function matchesEntry(entry, filters) {
  if (filters.source) {
    const [kind, id] = filters.source.split(":");
    const unnamed = !entry.accountId && !entry.cardId;
    if (
      (kind === "card" ? entry.cardId : entry.accountId) !== id &&
      !(kind === "account" && unnamed)
    ) {
      return false;
    }
  }
  if (filters.type && entry.type !== filters.type) {
    return false;
  }
  return matchesCommon(filters, entry.name, entry.amount, entry.dueDate);
}

export function matchesTransaction(transaction, filters) {
  if (filters.source) {
    const [kind, id] = filters.source.split(":");
    const transactionKind = transaction.source === "card" ? "card" : "account";
    if (kind !== transactionKind || id !== transaction.sourceId) {
      return false;
    }
  }
  if (filters.type === "Expense" && transaction.amount >= 0) {
    return false;
  }
  if (filters.type === "Income" && transaction.amount <= 0) {
    return false;
  }
  return matchesCommon(
    filters,
    transaction.description,
    transaction.amount,
    transaction.transactionDate
  );
}
