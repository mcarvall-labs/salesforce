import labels from "./labels";

const CODE_LABEL = {
  UNAVAILABLE: labels.codeUNAVAILABLE,
  NOT_ACCESSIBLE: labels.codeNOT_ACCESSIBLE,
  INVALID_INPUT: labels.codeINVALID_INPUT,
  INVALID: labels.codeINVALID,
  INVALID_REASON: labels.codeINVALID_REASON,
  INVALID_TARGET: labels.codeINVALID_TARGET,
  ALREADY_REVERSED: labels.codeALREADY_REVERSED,
  CONFLICT: labels.codeCONFLICT,
  REPORTING_CURRENCY_REQUIRED: labels.codeREPORTING_CURRENCY_REQUIRED
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

/** One operation key per draft so a retry replays instead of duplicating. */
export function newOperationKey() {
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  return `axf141-${Date.now().toString(36)}-${rnd()}${rnd()}${rnd()}`;
}
