import labels from "./labels";

const CODE_LABEL = {
  NOT_ACCESSIBLE: labels.codeNOT_ACCESSIBLE,
  INVALID_INPUT: labels.codeINVALID_INPUT,
  INVALID_STATE: labels.codeINVALID_STATE,
  REJECTED: labels.codeREJECTED,
  ALREADY_REGISTERED: labels.codeALREADY_REGISTERED
};

/** Server failures arrive as a sanitized code; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || labels.error;
}

export function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    const value = args[index];
    return value === undefined || value === null ? "" : value;
  });
}
