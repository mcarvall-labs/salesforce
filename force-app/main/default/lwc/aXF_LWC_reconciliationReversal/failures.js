import codeUNAVAILABLELabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeUNAVAILABLE";
import codeNOT_ACCESSIBLELabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeNOT_ACCESSIBLE";
import codeINVALID_INPUTLabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeINVALID_INPUT";
import codeINVALIDLabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeINVALID";
import codeINVALID_REASONLabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeINVALID_REASON";
import codeINVALID_TARGETLabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeINVALID_TARGET";
import codeALREADY_REVERSEDLabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeALREADY_REVERSED";
import codeCONFLICTLabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeCONFLICT";
import codeREPORTING_CURRENCY_REQUIREDLabel from "@salesforce/label/c.AXF_ReconciliationReversal_codeREPORTING_CURRENCY_REQUIRED";
import errorLabel from "@salesforce/label/c.AXF_ReconciliationReversal_error";

const CODE_LABEL = {
  UNAVAILABLE: codeUNAVAILABLELabel,
  NOT_ACCESSIBLE: codeNOT_ACCESSIBLELabel,
  INVALID_INPUT: codeINVALID_INPUTLabel,
  INVALID: codeINVALIDLabel,
  INVALID_REASON: codeINVALID_REASONLabel,
  INVALID_TARGET: codeINVALID_TARGETLabel,
  ALREADY_REVERSED: codeALREADY_REVERSEDLabel,
  CONFLICT: codeCONFLICTLabel,
  REPORTING_CURRENCY_REQUIRED: codeREPORTING_CURRENCY_REQUIREDLabel
};

/** Server failures arrive as a sanitized {code}; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || errorLabel;
}

export function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    return args[index] === undefined || args[index] === null ? "" : args[index];
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
