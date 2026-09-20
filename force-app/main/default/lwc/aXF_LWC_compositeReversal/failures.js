const CODE_LABEL = {
  UNAVAILABLE: "Voce nao tem permissao para esta operacao.",
  NOT_ACCESSIBLE: "Registro indisponivel.",
  INVALID: "Dados invalidos.",
  INVALID_INPUT: "Dados invalidos.",
  INVALID_REASON: "Motivo invalido.",
  INVALID_TARGET: "Alocacao invalida para esta operacao.",
  ALREADY_REVERSED: "Esta alocacao ja foi revertida com outro motivo.",
  CONFLICT: "A versao mudou; recarregue e tente novamente.",
  VALUE_CONSERVATION: "O valor solicitado excede a capacidade disponivel.",
  CURRENCY_MISMATCH: "Moeda incompativel entre origem e destino.",
  REPORTING_CURRENCY_REQUIRED:
    "Moeda de referencia do relatorio nao configurada."
};

/** Server failures arrive as a sanitized {code}; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || raw || "Ocorreu um erro inesperado.";
}

export function code(error) {
  return error && error.body && error.body.message;
}

/** One operation key per composite draft so a retry replays instead of duplicating. */
export function newOperationKey() {
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  return `axf142-${Date.now().toString(36)}-${rnd()}${rnd()}${rnd()}`;
}

/** UUID v4: the canonical correlation id of one human intention (never a replay identity). */
export function newCorrelationId() {
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  const a = rnd() + rnd();
  const b = rnd();
  const c = "4" + rnd().slice(1);
  const d =
    ((parseInt(rnd().slice(0, 1), 16) & 0x3) | 0x8).toString(16) +
    rnd().slice(1);
  const e = rnd() + rnd() + rnd();
  return `${a}-${b}-${c}-${d}-${e}`;
}
