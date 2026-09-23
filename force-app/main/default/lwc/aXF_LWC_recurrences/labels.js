// AXF-155: every text of the Recurring screen comes from a Custom Label (en_US + pt_BR).
import title from "@salesforce/label/c.AXF_Recurrences_title";
import intro from "@salesforce/label/c.AXF_Recurrences_intro";
import noCapability from "@salesforce/label/c.AXF_Recurrences_noCapability";
import readOnly from "@salesforce/label/c.AXF_Recurrences_readOnly";
import loading from "@salesforce/label/c.AXF_Recurrences_loading";
import error from "@salesforce/label/c.AXF_Recurrences_error";
import newRecurrence from "@salesforce/label/c.AXF_Recurrences_newRecurrence";
import formHeading from "@salesforce/label/c.AXF_Recurrences_formHeading";
import listCaption from "@salesforce/label/c.AXF_Recurrences_listCaption";
import noRecurrences from "@salesforce/label/c.AXF_Recurrences_noRecurrences";
import colDescription from "@salesforce/label/c.AXF_Recurrences_colDescription";
import colHolder from "@salesforce/label/c.AXF_Recurrences_colHolder";
import colPeriodicity from "@salesforce/label/c.AXF_Recurrences_colPeriodicity";
import colAmount from "@salesforce/label/c.AXF_Recurrences_colAmount";
import colNature from "@salesforce/label/c.AXF_Recurrences_colNature";
import colSource from "@salesforce/label/c.AXF_Recurrences_colSource";
import colNextDue from "@salesforce/label/c.AXF_Recurrences_colNextDue";
import colState from "@salesforce/label/c.AXF_Recurrences_colState";
import colActions from "@salesforce/label/c.AXF_Recurrences_colActions";
import colDueDate from "@salesforce/label/c.AXF_Recurrences_colDueDate";
import colStatus from "@salesforce/label/c.AXF_Recurrences_colStatus";
import stateACTIVE from "@salesforce/label/c.AXF_Recurrences_stateACTIVE";
import stateENDED from "@salesforce/label/c.AXF_Recurrences_stateENDED";
import natureDEBIT from "@salesforce/label/c.AXF_Recurrences_natureDEBIT";
import natureCREDIT from "@salesforce/label/c.AXF_Recurrences_natureCREDIT";
import periodWEEKLY from "@salesforce/label/c.AXF_Recurrences_periodWEEKLY";
import periodBIWEEKLY from "@salesforce/label/c.AXF_Recurrences_periodBIWEEKLY";
import periodMONTHLY from "@salesforce/label/c.AXF_Recurrences_periodMONTHLY";
import periodBIMONTHLY from "@salesforce/label/c.AXF_Recurrences_periodBIMONTHLY";
import periodQUARTERLY from "@salesforce/label/c.AXF_Recurrences_periodQUARTERLY";
import periodCUSTOM from "@salesforce/label/c.AXF_Recurrences_periodCUSTOM";
import periodEveryMonths from "@salesforce/label/c.AXF_Recurrences_periodEveryMonths";
import fieldHolder from "@salesforce/label/c.AXF_Recurrences_fieldHolder";
import fieldDescription from "@salesforce/label/c.AXF_Recurrences_fieldDescription";
import fieldNature from "@salesforce/label/c.AXF_Recurrences_fieldNature";
import fieldAmount from "@salesforce/label/c.AXF_Recurrences_fieldAmount";
import fieldCurrency from "@salesforce/label/c.AXF_Recurrences_fieldCurrency";
import fieldFirstDueDate from "@salesforce/label/c.AXF_Recurrences_fieldFirstDueDate";
import fieldPeriodicity from "@salesforce/label/c.AXF_Recurrences_fieldPeriodicity";
import fieldPeriodMonths from "@salesforce/label/c.AXF_Recurrences_fieldPeriodMonths";
import fieldSource from "@salesforce/label/c.AXF_Recurrences_fieldSource";
import noSources from "@salesforce/label/c.AXF_Recurrences_noSources";
import formInvalid from "@salesforce/label/c.AXF_Recurrences_formInvalid";
import create from "@salesforce/label/c.AXF_Recurrences_create";
import cancel from "@salesforce/label/c.AXF_Recurrences_cancel";
import save from "@salesforce/label/c.AXF_Recurrences_save";
import close from "@salesforce/label/c.AXF_Recurrences_close";
import created from "@salesforce/label/c.AXF_Recurrences_created";
import viewOccurrences from "@salesforce/label/c.AXF_Recurrences_viewOccurrences";
import viewOccurrencesFor from "@salesforce/label/c.AXF_Recurrences_viewOccurrencesFor";
import occurrencesCaption from "@salesforce/label/c.AXF_Recurrences_occurrencesCaption";
import noOccurrences from "@salesforce/label/c.AXF_Recurrences_noOccurrences";
import occurrencesTruncated from "@salesforce/label/c.AXF_Recurrences_occurrencesTruncated";
import occurrencesUnverified from "@salesforce/label/c.AXF_Recurrences_occurrencesUnverified";
import occPLANNED from "@salesforce/label/c.AXF_Recurrences_occPLANNED";
import occRECONCILED from "@salesforce/label/c.AXF_Recurrences_occRECONCILED";
import occPARTIAL from "@salesforce/label/c.AXF_Recurrences_occPARTIAL";
import occCANCELLED from "@salesforce/label/c.AXF_Recurrences_occCANCELLED";
import editAmount from "@salesforce/label/c.AXF_Recurrences_editAmount";
import editAmountFor from "@salesforce/label/c.AXF_Recurrences_editAmountFor";
import newAmount from "@salesforce/label/c.AXF_Recurrences_newAmount";
import editHint from "@salesforce/label/c.AXF_Recurrences_editHint";
import amountSaved from "@salesforce/label/c.AXF_Recurrences_amountSaved";
import end from "@salesforce/label/c.AXF_Recurrences_end";
import endFor from "@salesforce/label/c.AXF_Recurrences_endFor";
import endDate from "@salesforce/label/c.AXF_Recurrences_endDate";
import endHint from "@salesforce/label/c.AXF_Recurrences_endHint";
import confirmEnd from "@salesforce/label/c.AXF_Recurrences_confirmEnd";
import ended from "@salesforce/label/c.AXF_Recurrences_ended";
import notAvailable from "@salesforce/label/c.AXF_Recurrences_notAvailable";
import codeNOT_ACCESSIBLE from "@salesforce/label/c.AXF_Recurrences_codeNOT_ACCESSIBLE";
import codeNOT_ALLOWED from "@salesforce/label/c.AXF_Recurrences_codeNOT_ALLOWED";
import codeCONFLICT from "@salesforce/label/c.AXF_Recurrences_codeCONFLICT";
import codeINVALID_INPUT from "@salesforce/label/c.AXF_Recurrences_codeINVALID_INPUT";
import codeTOO_LARGE from "@salesforce/label/c.AXF_Recurrences_codeTOO_LARGE";
import codeUNAVAILABLE from "@salesforce/label/c.AXF_Recurrences_codeUNAVAILABLE";
import codeREJECTED from "@salesforce/label/c.AXF_Recurrences_codeREJECTED";

export default {
  title,
  intro,
  noCapability,
  readOnly,
  loading,
  error,
  newRecurrence,
  formHeading,
  listCaption,
  noRecurrences,
  colDescription,
  colHolder,
  colPeriodicity,
  colAmount,
  colNature,
  colSource,
  colNextDue,
  colState,
  colActions,
  colDueDate,
  colStatus,
  stateACTIVE,
  stateENDED,
  natureDEBIT,
  natureCREDIT,
  periodWEEKLY,
  periodBIWEEKLY,
  periodMONTHLY,
  periodBIMONTHLY,
  periodQUARTERLY,
  periodCUSTOM,
  periodEveryMonths,
  fieldHolder,
  fieldDescription,
  fieldNature,
  fieldAmount,
  fieldCurrency,
  fieldFirstDueDate,
  fieldPeriodicity,
  fieldPeriodMonths,
  fieldSource,
  noSources,
  formInvalid,
  create,
  cancel,
  save,
  close,
  created,
  viewOccurrences,
  viewOccurrencesFor,
  occurrencesCaption,
  noOccurrences,
  occurrencesTruncated,
  occurrencesUnverified,
  occPLANNED,
  occRECONCILED,
  occPARTIAL,
  occCANCELLED,
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
  notAvailable,
  codeNOT_ACCESSIBLE,
  codeNOT_ALLOWED,
  codeCONFLICT,
  codeINVALID_INPUT,
  codeTOO_LARGE,
  codeUNAVAILABLE,
  codeREJECTED
};
