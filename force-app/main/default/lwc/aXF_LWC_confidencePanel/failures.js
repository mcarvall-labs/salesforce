import codeForbiddenLabel from "@salesforce/label/c.AXF_ConfidencePanel_codeForbidden";
import codeInvalidInputLabel from "@salesforce/label/c.AXF_ConfidencePanel_codeInvalidInput";
import codeNotAccessibleLabel from "@salesforce/label/c.AXF_ConfidencePanel_codeNotAccessible";
import errorLabel from "@salesforce/label/c.AXF_ConfidencePanel_error";

const CODE_LABEL = {
  FORBIDDEN: codeForbiddenLabel,
  INVALID_INPUT: codeInvalidInputLabel,
  NOT_ACCESSIBLE: codeNotAccessibleLabel,
  UNEXPECTED: errorLabel
};

/** Server failures arrive as a sanitized {code}; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || errorLabel;
}

export function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    return args[index] === undefined ? match : args[index];
  });
}
