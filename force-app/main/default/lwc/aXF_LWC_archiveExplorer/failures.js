import codeForbiddenLabel from "@salesforce/label/c.AXF_ArchiveExplorer_codeForbidden";
import codeNotAccessibleLabel from "@salesforce/label/c.AXF_ArchiveExplorer_codeNotAccessible";
import codeInvalidInputLabel from "@salesforce/label/c.AXF_ArchiveExplorer_codeInvalidInput";
import codePolicyLabel from "@salesforce/label/c.AXF_ArchiveExplorer_codePolicy";
import codeRunInProgressLabel from "@salesforce/label/c.AXF_ArchiveExplorer_codeRunInProgress";
import codeAsyncLabel from "@salesforce/label/c.AXF_ArchiveExplorer_codeAsync";
import errorLabel from "@salesforce/label/c.AXF_ArchiveExplorer_error";

const CODE_LABEL = {
  FORBIDDEN: codeForbiddenLabel,
  NOT_ACCESSIBLE: codeNotAccessibleLabel,
  INVALID_INPUT: codeInvalidInputLabel,
  POLICY_MISSING: codePolicyLabel,
  POLICY_DISABLED: codePolicyLabel,
  POLICY_INVALID: codePolicyLabel,
  RUN_IN_PROGRESS: codeRunInProgressLabel,
  ASYNC_UNAVAILABLE: codeAsyncLabel
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
