import codeUNAVAILABLELabel from "@salesforce/label/c.AXF_SourceLink_codeUNAVAILABLE";
import codeNOT_ACCESSIBLELabel from "@salesforce/label/c.AXF_SourceLink_codeNOT_ACCESSIBLE";
import codeINVALID_INPUTLabel from "@salesforce/label/c.AXF_SourceLink_codeINVALID_INPUT";
import codeINVALIDLabel from "@salesforce/label/c.AXF_SourceLink_codeINVALID";
import codeINVALID_SOURCELabel from "@salesforce/label/c.AXF_SourceLink_codeINVALID_SOURCE";
import codeINVALID_SOURCE_DATALabel from "@salesforce/label/c.AXF_SourceLink_codeINVALID_SOURCE_DATA";
import codeNOT_POSTEDLabel from "@salesforce/label/c.AXF_SourceLink_codeNOT_POSTED";
import codeFUNDING_NOT_AVAILABLELabel from "@salesforce/label/c.AXF_SourceLink_codeFUNDING_NOT_AVAILABLE";
import codeREVIEW_OPENLabel from "@salesforce/label/c.AXF_SourceLink_codeREVIEW_OPEN";
import codeSOURCE_EXHAUSTEDLabel from "@salesforce/label/c.AXF_SourceLink_codeSOURCE_EXHAUSTED";
import codeALLOCATIONS_UNVERIFIEDLabel from "@salesforce/label/c.AXF_SourceLink_codeALLOCATIONS_UNVERIFIED";
import codeINVALID_TARGETLabel from "@salesforce/label/c.AXF_SourceLink_codeINVALID_TARGET";
import codeTARGET_CANCELLEDLabel from "@salesforce/label/c.AXF_SourceLink_codeTARGET_CANCELLED";
import codeTARGET_REALIZEDLabel from "@salesforce/label/c.AXF_SourceLink_codeTARGET_REALIZED";
import codeFUNDING_MISMATCHLabel from "@salesforce/label/c.AXF_SourceLink_codeFUNDING_MISMATCH";
import codeCURRENCY_MISMATCHLabel from "@salesforce/label/c.AXF_SourceLink_codeCURRENCY_MISMATCH";
import codeALREADY_LINKEDLabel from "@salesforce/label/c.AXF_SourceLink_codeALREADY_LINKED";
import codeREVIEW_REQUIREDLabel from "@salesforce/label/c.AXF_SourceLink_codeREVIEW_REQUIRED";
import codeCONFLICTLabel from "@salesforce/label/c.AXF_SourceLink_codeCONFLICT";
import codeUNAVAILABLE_AMOUNTLabel from "@salesforce/label/c.AXF_SourceLink_codeUNAVAILABLE_AMOUNT";
import codeREPORTING_CURRENCY_REQUIREDLabel from "@salesforce/label/c.AXF_SourceLink_codeREPORTING_CURRENCY_REQUIRED";
import codeMATERIALIZATION_REQUIREDLabel from "@salesforce/label/c.AXF_SourceLink_codeMATERIALIZATION_REQUIRED";
import errorLabel from "@salesforce/label/c.AXF_SourceLink_error";

const CODE_LABEL = {
  UNAVAILABLE: codeUNAVAILABLELabel,
  NOT_ACCESSIBLE: codeNOT_ACCESSIBLELabel,
  INVALID_INPUT: codeINVALID_INPUTLabel,
  INVALID: codeINVALIDLabel,
  INVALID_SOURCE: codeINVALID_SOURCELabel,
  INVALID_SOURCE_DATA: codeINVALID_SOURCE_DATALabel,
  NOT_POSTED: codeNOT_POSTEDLabel,
  FUNDING_NOT_AVAILABLE: codeFUNDING_NOT_AVAILABLELabel,
  REVIEW_OPEN: codeREVIEW_OPENLabel,
  SOURCE_EXHAUSTED: codeSOURCE_EXHAUSTEDLabel,
  ALLOCATIONS_UNVERIFIED: codeALLOCATIONS_UNVERIFIEDLabel,
  INVALID_TARGET: codeINVALID_TARGETLabel,
  TARGET_CANCELLED: codeTARGET_CANCELLEDLabel,
  TARGET_REALIZED: codeTARGET_REALIZEDLabel,
  FUNDING_MISMATCH: codeFUNDING_MISMATCHLabel,
  CURRENCY_MISMATCH: codeCURRENCY_MISMATCHLabel,
  ALREADY_LINKED: codeALREADY_LINKEDLabel,
  REVIEW_REQUIRED: codeREVIEW_REQUIREDLabel,
  CONFLICT: codeCONFLICTLabel,
  UNAVAILABLE_AMOUNT: codeUNAVAILABLE_AMOUNTLabel,
  REPORTING_CURRENCY_REQUIRED: codeREPORTING_CURRENCY_REQUIREDLabel,
  MATERIALIZATION_REQUIRED: codeMATERIALIZATION_REQUIREDLabel
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

/** One operation key per draft so a retry replays instead of duplicating. */
export function newOperationKey() {
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  return `axf134-${Date.now().toString(36)}-${rnd()}${rnd()}${rnd()}`;
}
