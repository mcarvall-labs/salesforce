import labels from "./labels";

const CODE_LABEL = {
  UNAVAILABLE: labels.codeUNAVAILABLE,
  NOT_ACCESSIBLE: labels.codeNOT_ACCESSIBLE,
  INVALID_INPUT: labels.codeINVALID_INPUT,
  INVALID: labels.codeINVALID_INPUT,
  VALUE_CONSERVATION: labels.codeVALUE_CONSERVATION,
  CURRENCY_MISMATCH: labels.codeCURRENCY_MISMATCH,
  CONFLICT: labels.codeCONFLICT,
  LOCK_PLAN_CHANGED: labels.codeLOCK_PLAN_CHANGED,
  LOCKED: labels.codeLOCKED,
  REJECTED: labels.codeREJECTED,
  UNEXPECTED: labels.codeUNEXPECTED,
  FACT_NOT_RECONCILABLE: labels.codeFACT_NOT_RECONCILABLE,
  REPORTING_CURRENCY_REQUIRED: labels.codeREPORTING_CURRENCY_REQUIRED
};

/** Server failures arrive as a sanitized {code, reasons}; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  if (!raw) {
    return labels.error;
  }
  try {
    const parsed = JSON.parse(raw);
    return CODE_LABEL[parsed.code] || labels.error;
  } catch {
    return CODE_LABEL[raw] || labels.error;
  }
}

/** The reasons array is only read as opaque tokens; the surface never explains a figure itself. */
export function failureCode(error) {
  const raw = error && error.body && error.body.message;
  if (!raw) {
    return null;
  }
  try {
    const parsed = JSON.parse(raw);
    return parsed.code || raw;
  } catch {
    return raw;
  }
}

export function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    return args[index] === undefined || args[index] === null ? "" : args[index];
  });
}

/** One operation key per draft so a retry replays instead of duplicating an allocation. */
export function newOperationKey() {
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  return `axf30-${Date.now().toString(36)}-${rnd()}${rnd()}${rnd()}`;
}

/** UUID v4 of one human intention: reused on retry, so the aggregate identity is stable. */
export function newCorrelationId() {
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  const variant = ((Math.floor(Math.random() * 4) + 8) & 0xf).toString(16);
  return `${rnd()}${rnd()}-${rnd()}-4${rnd().slice(1)}-${variant}${rnd().slice(
    1
  )}-${rnd()}${rnd()}${rnd()}`;
}
