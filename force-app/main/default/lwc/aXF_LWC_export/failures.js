import codeFORBIDDENLabel from "@salesforce/label/c.AXF_Export_codeFORBIDDEN";
import codeNOT_ACCESSIBLELabel from "@salesforce/label/c.AXF_Export_codeNOT_ACCESSIBLE";
import codeINVALID_INPUTLabel from "@salesforce/label/c.AXF_Export_codeINVALID_INPUT";
import codeCONFLICTLabel from "@salesforce/label/c.AXF_Export_codeCONFLICT";
import codeEXPORT_POLICY_MISSINGLabel from "@salesforce/label/c.AXF_Export_codeEXPORT_POLICY_MISSING";
import codeSHARE_FAILEDLabel from "@salesforce/label/c.AXF_Export_codeSHARE_FAILED";
import errorLabel from "@salesforce/label/c.AXF_Export_error";

const CODE_LABEL = {
  FORBIDDEN: codeFORBIDDENLabel,
  NOT_ACCESSIBLE: codeNOT_ACCESSIBLELabel,
  INVALID_INPUT: codeINVALID_INPUTLabel,
  CONFLICT: codeCONFLICTLabel,
  EXPORT_POLICY_MISSING: codeEXPORT_POLICY_MISSINGLabel,
  SHARE_FAILED: codeSHARE_FAILEDLabel
};

/** Server failures arrive as a sanitized {code}; anything else is the generic message. */
export function parseFailure(error) {
  const raw = error && error.body && error.body.message;
  return CODE_LABEL[raw] || errorLabel;
}

/** A refused/revoked download outcome (never thrown) mapped the same way as a thrown code. */
export function outcomeMessage(outcome) {
  return CODE_LABEL[outcome] || errorLabel;
}
