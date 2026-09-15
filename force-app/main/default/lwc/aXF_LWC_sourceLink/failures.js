import labels from "./labels";

const CODE_LABEL = {
  UNAVAILABLE: labels.codeUNAVAILABLE,
  NOT_ACCESSIBLE: labels.codeNOT_ACCESSIBLE,
  INVALID_INPUT: labels.codeINVALID_INPUT,
  INVALID: labels.codeINVALID,
  INVALID_SOURCE: labels.codeINVALID_SOURCE,
  INVALID_SOURCE_DATA: labels.codeINVALID_SOURCE_DATA,
  NOT_POSTED: labels.codeNOT_POSTED,
  FUNDING_NOT_AVAILABLE: labels.codeFUNDING_NOT_AVAILABLE,
  REVIEW_OPEN: labels.codeREVIEW_OPEN,
  SOURCE_EXHAUSTED: labels.codeSOURCE_EXHAUSTED,
  ALLOCATIONS_UNVERIFIED: labels.codeALLOCATIONS_UNVERIFIED,
  INVALID_TARGET: labels.codeINVALID_TARGET,
  TARGET_CANCELLED: labels.codeTARGET_CANCELLED,
  TARGET_REALIZED: labels.codeTARGET_REALIZED,
  FUNDING_MISMATCH: labels.codeFUNDING_MISMATCH,
  CURRENCY_MISMATCH: labels.codeCURRENCY_MISMATCH,
  MISSING_MATERIAL_FX: labels.codeMISSING_MATERIAL_FX,
  ALREADY_LINKED: labels.codeALREADY_LINKED,
  REVIEW_REQUIRED: labels.codeREVIEW_REQUIRED,
  CONFLICT: labels.codeCONFLICT,
  UNAVAILABLE_AMOUNT: labels.codeUNAVAILABLE_AMOUNT,
  REPORTING_CURRENCY_REQUIRED: labels.codeREPORTING_CURRENCY_REQUIRED,
  MATERIALIZATION_REQUIRED: labels.codeMATERIALIZATION_REQUIRED
};

/** Server failures arrive as a sanitized {code}; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || labels.error;
}

/**
 * AXF-140: a candidate reason is the same sanitized server code, so it resolves through the same
 * map; a code this component does not know is shown as the code itself rather than dropped.
 */
export function reasonLabel(code) {
  return CODE_LABEL[code] || code;
}

export function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    return args[index] === undefined ? match : args[index];
  });
}

/** One operation key per draft so a retry replays instead of duplicating. */
export function newOperationKey() {
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  return `axf134-${Date.now().toString(36)}-${rnd()}${rnd()}${rnd()}`;
}
