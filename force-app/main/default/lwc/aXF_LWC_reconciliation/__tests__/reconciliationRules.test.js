import {
  entryKind,
  isCompatible,
  matchesEntry,
  matchesTransaction,
  monthOptions
} from "../reconciliationRules";

const noFilters = { source: "", text: "", min: "", max: "", type: "" };
const accountEntry = {
  id: "e1",
  type: "Expense",
  amount: 100,
  name: "Conta de luz"
};
const cardEntry = {
  id: "e2",
  type: "Expense",
  amount: 50,
  name: "Notebook",
  cardId: "c1"
};
const invoiceEntry = {
  id: "e3",
  type: "Expense",
  amount: 300,
  name: "Fatura",
  cardId: "c1",
  invoiceId: "i1"
};
const debit = {
  id: "t1",
  source: "account",
  amount: -100,
  sourceId: "a1",
  description: "Pagamento luz"
};
const credit = {
  id: "t2",
  source: "account",
  amount: 100,
  sourceId: "a1",
  description: "PIX recebido"
};
const purchase = {
  id: "t3",
  source: "card",
  amount: -50,
  sourceId: "c1",
  description: "NOTEBOOK LOJA"
};

describe("entryKind", () => {
  it("tells invoice, card and account entries apart", () => {
    expect(entryKind(invoiceEntry)).toBe("invoice");
    expect(entryKind(cardEntry)).toBe("card");
    expect(entryKind(accountEntry)).toBe("account");
  });
});

describe("isCompatible", () => {
  it("pairs card entries with card transactions only", () => {
    expect(isCompatible(cardEntry, purchase)).toBe(true);
    expect(isCompatible(cardEntry, debit)).toBe(false);
    expect(isCompatible({ ...cardEntry, cardId: "other" }, purchase)).toBe(
      false
    );
  });

  it("pairs account and invoice entries with account transactions only", () => {
    expect(isCompatible(accountEntry, debit)).toBe(true);
    expect(isCompatible(accountEntry, purchase)).toBe(false);
    expect(isCompatible(invoiceEntry, debit)).toBe(true);
    expect(isCompatible(invoiceEntry, purchase)).toBe(false);
  });

  it("keeps the account of an entry that names one", () => {
    expect(isCompatible({ ...accountEntry, accountId: "a1" }, debit)).toBe(
      true
    );
    expect(isCompatible({ ...accountEntry, accountId: "a2" }, debit)).toBe(
      false
    );
  });

  it("matches expense with outflow and income with inflow", () => {
    expect(isCompatible(accountEntry, credit)).toBe(false);
    expect(isCompatible({ ...accountEntry, type: "Income" }, credit)).toBe(
      true
    );
    expect(isCompatible({ ...accountEntry, type: "Income" }, debit)).toBe(
      false
    );
  });
});

describe("filters", () => {
  it("filters entries by text, range, type and source", () => {
    expect(matchesEntry(accountEntry, { ...noFilters, text: "LUZ" })).toBe(
      true
    );
    expect(matchesEntry(accountEntry, { ...noFilters, text: "net" })).toBe(
      false
    );
    expect(matchesEntry(accountEntry, { ...noFilters, min: "101" })).toBe(
      false
    );
    expect(matchesEntry(accountEntry, { ...noFilters, max: "99" })).toBe(false);
    expect(
      matchesEntry(accountEntry, { ...noFilters, min: "100", max: "100" })
    ).toBe(true);
    expect(matchesEntry(accountEntry, { ...noFilters, type: "Income" })).toBe(
      false
    );
    expect(matchesEntry(cardEntry, { ...noFilters, source: "card:c1" })).toBe(
      true
    );
    expect(
      matchesEntry(invoiceEntry, { ...noFilters, source: "card:c1" })
    ).toBe(true);
    expect(matchesEntry(cardEntry, { ...noFilters, source: "card:c2" })).toBe(
      false
    );
    expect(
      matchesEntry(
        { ...accountEntry, accountId: "a1" },
        { ...noFilters, source: "account:a1" }
      )
    ).toBe(true);
  });

  it("filters transactions by text, range, direction and source", () => {
    expect(matchesTransaction(debit, { ...noFilters, text: "luz" })).toBe(true);
    expect(matchesTransaction(debit, { ...noFilters, text: "pix" })).toBe(
      false
    );
    expect(
      matchesTransaction(debit, { ...noFilters, min: "100", max: "100" })
    ).toBe(true);
    expect(matchesTransaction(debit, { ...noFilters, type: "Income" })).toBe(
      false
    );
    expect(matchesTransaction(credit, { ...noFilters, type: "Income" })).toBe(
      true
    );
    expect(matchesTransaction(credit, { ...noFilters, type: "Expense" })).toBe(
      false
    );
    expect(
      matchesTransaction(purchase, { ...noFilters, source: "card:c1" })
    ).toBe(true);
    expect(
      matchesTransaction(purchase, { ...noFilters, source: "account:c1" })
    ).toBe(false);
    expect(
      matchesTransaction(debit, { ...noFilters, source: "account:a1" })
    ).toBe(true);
    expect(
      matchesTransaction(debit, { ...noFilters, source: "account:a2" })
    ).toBe(false);
  });
});

describe("monthOptions", () => {
  it("lists six months back and ahead with the current one in the middle", () => {
    const options = monthOptions(new Date(2026, 9, 15));
    expect(options).toHaveLength(13);
    expect(options[6]).toEqual({ label: "Outubro/2026", value: "2026-10" });
    expect(options[0].value).toBe("2026-04");
    expect(options[12].value).toBe("2027-04");
  });
});

describe("date range and unnamed accounts", () => {
  const dated = { ...accountEntry, dueDate: "2026-10-10" };
  const datedTransaction = { ...debit, transactionDate: "2026-10-10" };

  it("keeps only rows inside the date range", () => {
    expect(matchesEntry(dated, { ...noFilters, dateFrom: "2026-10-10" })).toBe(
      true
    );
    expect(matchesEntry(dated, { ...noFilters, dateFrom: "2026-10-11" })).toBe(
      false
    );
    expect(matchesEntry(dated, { ...noFilters, dateTo: "2026-10-09" })).toBe(
      false
    );
    expect(
      matchesTransaction(datedTransaction, {
        ...noFilters,
        dateFrom: "2026-10-01",
        dateTo: "2026-10-10"
      })
    ).toBe(true);
    expect(
      matchesTransaction(datedTransaction, {
        ...noFilters,
        dateTo: "2026-10-09"
      })
    ).toBe(false);
    expect(
      matchesTransaction(debit, { ...noFilters, dateFrom: "2026-10-01" })
    ).toBe(false);
  });

  it("shows entries without a named account under any account filter", () => {
    expect(
      matchesEntry(accountEntry, { ...noFilters, source: "account:a1" })
    ).toBe(true);
    expect(
      matchesEntry(
        { ...accountEntry, accountId: "a2" },
        { ...noFilters, source: "account:a1" }
      )
    ).toBe(false);
    expect(
      matchesEntry(cardEntry, { ...noFilters, source: "account:a1" })
    ).toBe(false);
  });

  it("treats a missing amount as zero in the value filters", () => {
    expect(
      matchesEntry(
        { ...accountEntry, amount: null },
        { ...noFilters, min: "1" }
      )
    ).toBe(false);
  });
});
