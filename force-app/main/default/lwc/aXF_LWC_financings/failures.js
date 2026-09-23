import labels from "./labels";

const CODE_LABEL = {
  NOT_ACCESSIBLE: labels.codeNOT_ACCESSIBLE,
  NOT_ALLOWED: labels.codeNOT_ALLOWED,
  CONFLICT: labels.codeCONFLICT,
  INVALID_INPUT: labels.codeINVALID_INPUT,
  UNAVAILABLE: labels.codeUNAVAILABLE,
  REJECTED: labels.codeREJECTED
};

/** Server failures arrive as a sanitized code; anything else is the generic message. */
export function failureCode(error) {
  const raw = error && error.body && error.body.message;
  return raw ? String(raw) : null;
}

export function parseFailure(error) {
  return CODE_LABEL[failureCode(error)] || labels.error;
}

export function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    const value = args[index];
    return value === undefined || value === null ? "" : value;
  });
}

/** A fresh key per explicit command: one human intent, one idempotent operation. */
export function newOperationKey() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  return `axf156-${Date.now().toString(36)}-${rnd()}${rnd()}${rnd()}`;
}
