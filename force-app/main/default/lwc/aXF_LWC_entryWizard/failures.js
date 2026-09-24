import L from "./labels";

const CODE_LABEL = {
  NOT_ACCESSIBLE: L.codeNOT_ACCESSIBLE,
  UNAVAILABLE: L.codeUNAVAILABLE,
  INVALID_INPUT: L.codeINVALID_INPUT,
  INVALID: L.codeINVALID_INPUT,
  INVALID_TARGET: L.codeINVALID_INPUT,
  CONFLICT: L.codeCONFLICT,
  ALREADY_LINKED: L.codeALREADY_LINKED,
  SOURCE_EXHAUSTED: L.codeEXHAUSTED,
  TARGET_REALIZED: L.codeEXHAUSTED,
  UNAVAILABLE_AMOUNT: L.codeUNAVAILABLE_AMOUNT,
  REVIEW_OPEN: L.codeREVIEW_OPEN,
  FACT_REQUIRED: L.codeFACT_REQUIRED,
  FACT_MISMATCH: L.codeFACT_MISMATCH,
  INVALID_SOURCE: L.codeFACT_MISMATCH,
  CURRENCY_MISMATCH: L.codeFACT_MISMATCH
};

/** AXF-153 endpoints fail with a sanitized code; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return (raw && CODE_LABEL[String(raw)]) || L.error;
}

export function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    const value = args[index];
    return value === undefined || value === null ? "" : value;
  });
}
