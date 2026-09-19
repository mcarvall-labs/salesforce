import codeForbiddenLabel from "@salesforce/label/c.AXF_ForecastComparison_codeForbidden";
import codeNotAccessibleLabel from "@salesforce/label/c.AXF_ForecastComparison_codeNotAccessible";
import codeInvalidInputLabel from "@salesforce/label/c.AXF_ForecastComparison_codeInvalidInput";
import codeUnavailableLabel from "@salesforce/label/c.AXF_ForecastComparison_codeUnavailable";
import codeUnexpectedLabel from "@salesforce/label/c.AXF_ForecastComparison_codeUnexpected";
import errorLabel from "@salesforce/label/c.AXF_ForecastComparison_error";

const CODE_LABEL = {
  FORBIDDEN: codeForbiddenLabel,
  NOT_ACCESSIBLE: codeNotAccessibleLabel,
  INVALID_INPUT: codeInvalidInputLabel,
  UNAVAILABLE: codeUnavailableLabel,
  UNEXPECTED: codeUnexpectedLabel
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
