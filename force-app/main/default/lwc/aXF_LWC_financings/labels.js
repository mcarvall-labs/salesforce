// AXF-156: every text of the Financing screen comes from a Custom Label (en_US + pt_BR).
import title from "@salesforce/label/c.AXF_Financings_title";
import intro from "@salesforce/label/c.AXF_Financings_intro";
import noCapability from "@salesforce/label/c.AXF_Financings_noCapability";
import readOnly from "@salesforce/label/c.AXF_Financings_readOnly";
import loading from "@salesforce/label/c.AXF_Financings_loading";
import error from "@salesforce/label/c.AXF_Financings_error";
import newFinancing from "@salesforce/label/c.AXF_Financings_newFinancing";
import listCaption from "@salesforce/label/c.AXF_Financings_listCaption";
import noFinancings from "@salesforce/label/c.AXF_Financings_noFinancings";
import colDescription from "@salesforce/label/c.AXF_Financings_colDescription";
import colHolder from "@salesforce/label/c.AXF_Financings_colHolder";
import colMethod from "@salesforce/label/c.AXF_Financings_colMethod";
import colProgress from "@salesforce/label/c.AXF_Financings_colProgress";
import colNextDue from "@salesforce/label/c.AXF_Financings_colNextDue";
import colNextAmount from "@salesforce/label/c.AXF_Financings_colNextAmount";
import colBalance from "@salesforce/label/c.AXF_Financings_colBalance";
import colState from "@salesforce/label/c.AXF_Financings_colState";
import colActions from "@salesforce/label/c.AXF_Financings_colActions";
import colSequence from "@salesforce/label/c.AXF_Financings_colSequence";
import colDueDate from "@salesforce/label/c.AXF_Financings_colDueDate";
import colAmount from "@salesforce/label/c.AXF_Financings_colAmount";
import colInterest from "@salesforce/label/c.AXF_Financings_colInterest";
import colPrincipal from "@salesforce/label/c.AXF_Financings_colPrincipal";
import colBalanceAfter from "@salesforce/label/c.AXF_Financings_colBalanceAfter";
import colStatus from "@salesforce/label/c.AXF_Financings_colStatus";
import methodPRICE from "@salesforce/label/c.AXF_Financings_methodPRICE";
import methodSAC from "@salesforce/label/c.AXF_Financings_methodSAC";
import methodINSTALLMENT from "@salesforce/label/c.AXF_Financings_methodINSTALLMENT";
import stateACTIVE from "@salesforce/label/c.AXF_Financings_stateACTIVE";
import stateENDED from "@salesforce/label/c.AXF_Financings_stateENDED";
import stateSETTLED from "@salesforce/label/c.AXF_Financings_stateSETTLED";
import legacy from "@salesforce/label/c.AXF_Financings_legacy";
import progress from "@salesforce/label/c.AXF_Financings_progress";
import viewInstallments from "@salesforce/label/c.AXF_Financings_viewInstallments";
import viewInstallmentsFor from "@salesforce/label/c.AXF_Financings_viewInstallmentsFor";
import installmentsCaption from "@salesforce/label/c.AXF_Financings_installmentsCaption";
import noInstallments from "@salesforce/label/c.AXF_Financings_noInstallments";
import installmentsTruncated from "@salesforce/label/c.AXF_Financings_installmentsTruncated";
import installmentsUnverified from "@salesforce/label/c.AXF_Financings_installmentsUnverified";
import projected from "@salesforce/label/c.AXF_Financings_projected";
import instPAID from "@salesforce/label/c.AXF_Financings_instPAID";
import instPARTIAL from "@salesforce/label/c.AXF_Financings_instPARTIAL";
import instPLANNED from "@salesforce/label/c.AXF_Financings_instPLANNED";
import instCANCELLED from "@salesforce/label/c.AXF_Financings_instCANCELLED";
import editAmount from "@salesforce/label/c.AXF_Financings_editAmount";
import editAmountFor from "@salesforce/label/c.AXF_Financings_editAmountFor";
import newAmount from "@salesforce/label/c.AXF_Financings_newAmount";
import editHint from "@salesforce/label/c.AXF_Financings_editHint";
import amountSaved from "@salesforce/label/c.AXF_Financings_amountSaved";
import end from "@salesforce/label/c.AXF_Financings_end";
import endFor from "@salesforce/label/c.AXF_Financings_endFor";
import endDate from "@salesforce/label/c.AXF_Financings_endDate";
import endHint from "@salesforce/label/c.AXF_Financings_endHint";
import confirmEnd from "@salesforce/label/c.AXF_Financings_confirmEnd";
import ended from "@salesforce/label/c.AXF_Financings_ended";
import settle from "@salesforce/label/c.AXF_Financings_settle";
import settleFor from "@salesforce/label/c.AXF_Financings_settleFor";
import settleHeading from "@salesforce/label/c.AXF_Financings_settleHeading";
import settleAmount from "@salesforce/label/c.AXF_Financings_settleAmount";
import settleAmountHint from "@salesforce/label/c.AXF_Financings_settleAmountHint";
import settleDate from "@salesforce/label/c.AXF_Financings_settleDate";
import settleHint from "@salesforce/label/c.AXF_Financings_settleHint";
import confirmSettle from "@salesforce/label/c.AXF_Financings_confirmSettle";
import settled from "@salesforce/label/c.AXF_Financings_settled";
import close from "@salesforce/label/c.AXF_Financings_close";
import cancel from "@salesforce/label/c.AXF_Financings_cancel";
import save from "@salesforce/label/c.AXF_Financings_save";
import notAvailable from "@salesforce/label/c.AXF_Financings_notAvailable";
import codeNOT_ACCESSIBLE from "@salesforce/label/c.AXF_Financings_codeNOT_ACCESSIBLE";
import codeNOT_ALLOWED from "@salesforce/label/c.AXF_Financings_codeNOT_ALLOWED";
import codeCONFLICT from "@salesforce/label/c.AXF_Financings_codeCONFLICT";
import codeINVALID_INPUT from "@salesforce/label/c.AXF_Financings_codeINVALID_INPUT";
import codeUNAVAILABLE from "@salesforce/label/c.AXF_Financings_codeUNAVAILABLE";
import codeREJECTED from "@salesforce/label/c.AXF_Financings_codeREJECTED";

export default {
  title,
  intro,
  noCapability,
  readOnly,
  loading,
  error,
  newFinancing,
  listCaption,
  noFinancings,
  colDescription,
  colHolder,
  colMethod,
  colProgress,
  colNextDue,
  colNextAmount,
  colBalance,
  colState,
  colActions,
  colSequence,
  colDueDate,
  colAmount,
  colInterest,
  colPrincipal,
  colBalanceAfter,
  colStatus,
  methodPRICE,
  methodSAC,
  methodINSTALLMENT,
  stateACTIVE,
  stateENDED,
  stateSETTLED,
  legacy,
  progress,
  viewInstallments,
  viewInstallmentsFor,
  installmentsCaption,
  noInstallments,
  installmentsTruncated,
  installmentsUnverified,
  projected,
  instPAID,
  instPARTIAL,
  instPLANNED,
  instCANCELLED,
  editAmount,
  editAmountFor,
  newAmount,
  editHint,
  amountSaved,
  end,
  endFor,
  endDate,
  endHint,
  confirmEnd,
  ended,
  settle,
  settleFor,
  settleHeading,
  settleAmount,
  settleAmountHint,
  settleDate,
  settleHint,
  confirmSettle,
  settled,
  close,
  cancel,
  save,
  notAvailable,
  codeNOT_ACCESSIBLE,
  codeNOT_ALLOWED,
  codeCONFLICT,
  codeINVALID_INPUT,
  codeUNAVAILABLE,
  codeREJECTED
};
