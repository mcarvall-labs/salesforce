import codeUNAVAILABLELabel from "@salesforce/label/c.AXF_InternalTransfer_codeUNAVAILABLE";
import codeNOT_ACCESSIBLELabel from "@salesforce/label/c.AXF_InternalTransfer_codeNOT_ACCESSIBLE";
import codeINVALID_INPUTLabel from "@salesforce/label/c.AXF_InternalTransfer_codeINVALID_INPUT";
import codeINVALIDLabel from "@salesforce/label/c.AXF_InternalTransfer_codeINVALID";
import codeCONFLICTLabel from "@salesforce/label/c.AXF_InternalTransfer_codeCONFLICT";
import codeALREADY_DECIDEDLabel from "@salesforce/label/c.AXF_InternalTransfer_codeALREADY_DECIDED";
import codeINVALID_TARGETLabel from "@salesforce/label/c.AXF_InternalTransfer_codeINVALID_TARGET";
import errorLabel from "@salesforce/label/c.AXF_InternalTransfer_error";

const CODE_LABEL = {
  UNAVAILABLE: codeUNAVAILABLELabel,
  NOT_ACCESSIBLE: codeNOT_ACCESSIBLELabel,
  INVALID_INPUT: codeINVALID_INPUTLabel,
  INVALID: codeINVALIDLabel,
  CONFLICT: codeCONFLICTLabel,
  ALREADY_DECIDED: codeALREADY_DECIDEDLabel,
  INVALID_TARGET: codeINVALID_TARGETLabel
};

/** Server failures arrive as a sanitized {code}; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || errorLabel;
}

/** One operation key per confirmation so a retry replays instead of duplicating. */
export function newOperationKey() {
  const rnd = () =>
    Math.floor(Math.random() * 0x10000)
      .toString(16)
      .padStart(4, "0");
  return `axf32-${Date.now().toString(36)}-${rnd()}${rnd()}${rnd()}`;
}
