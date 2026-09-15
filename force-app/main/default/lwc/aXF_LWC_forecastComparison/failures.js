import labels from "./labels";

const CODE_LABEL = {
  FORBIDDEN: labels.codeForbidden,
  NOT_ACCESSIBLE: labels.codeNotAccessible,
  INVALID_INPUT: labels.codeInvalidInput,
  UNAVAILABLE: labels.codeUnavailable,
  UNEXPECTED: labels.codeUnexpected
};

/** Server failures arrive as a sanitized {code}; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || labels.error;
}

export function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    return args[index] === undefined ? match : args[index];
  });
}
