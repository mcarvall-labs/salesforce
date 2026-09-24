// AXF-152: card-specific texts; generic statement texts are shared with AXF-151.
import title from "@salesforce/label/c.AXF_CardStatement_title";
import intro from "@salesforce/label/c.AXF_CardStatement_intro";
import noCapability from "@salesforce/label/c.AXF_CardStatement_noCapability";
import cardsCaption from "@salesforce/label/c.AXF_CardStatement_cardsCaption";
import noCards from "@salesforce/label/c.AXF_CardStatement_noCards";
import colCard from "@salesforce/label/c.AXF_CardStatement_colCard";
import colCreditLimit from "@salesforce/label/c.AXF_CardStatement_colCreditLimit";
import colAvailableLimit from "@salesforce/label/c.AXF_CardStatement_colAvailableLimit";
import colClosingDay from "@salesforce/label/c.AXF_CardStatement_colClosingDay";
import colDueDay from "@salesforce/label/c.AXF_CardStatement_colDueDay";
import notAvailable from "@salesforce/label/c.AXF_CardStatement_notAvailable";
import viewInvoice from "@salesforce/label/c.AXF_CardStatement_viewInvoice";
import viewInvoiceFor from "@salesforce/label/c.AXF_CardStatement_viewInvoiceFor";
import defineClosing from "@salesforce/label/c.AXF_CardStatement_defineClosing";
import defineClosingFor from "@salesforce/label/c.AXF_CardStatement_defineClosingFor";
import closingDayInput from "@salesforce/label/c.AXF_CardStatement_closingDayInput";
import dueDayInput from "@salesforce/label/c.AXF_CardStatement_dueDayInput";
import dayRange from "@salesforce/label/c.AXF_CardStatement_dayRange";
import closingSaved from "@salesforce/label/c.AXF_CardStatement_closingSaved";
import invoiceCaption from "@salesforce/label/c.AXF_CardStatement_invoiceCaption";
import previousInvoice from "@salesforce/label/c.AXF_CardStatement_previousInvoice";
import nextInvoice from "@salesforce/label/c.AXF_CardStatement_nextInvoice";
import invoiceWindow from "@salesforce/label/c.AXF_CardStatement_invoiceWindow";
import closingDate from "@salesforce/label/c.AXF_CardStatement_closingDate";
import dueDate from "@salesforce/label/c.AXF_CardStatement_dueDate";
import total from "@salesforce/label/c.AXF_CardStatement_total";
import totalPartial from "@salesforce/label/c.AXF_CardStatement_totalPartial";
import mixedCurrency from "@salesforce/label/c.AXF_CardStatement_mixedCurrency";
import plannedTotal from "@salesforce/label/c.AXF_CardStatement_plannedTotal";
import noCalendar from "@salesforce/label/c.AXF_CardStatement_noCalendar";
import newExpense from "@salesforce/label/c.AXF_CardStatement_newExpense";
import noLines from "@salesforce/label/c.AXF_CardStatement_noLines";
import codeNOT_ACCESSIBLE from "@salesforce/label/c.AXF_CardStatement_codeNOT_ACCESSIBLE";
import codeNOT_ALLOWED from "@salesforce/label/c.AXF_CardStatement_codeNOT_ALLOWED";
import codeCONFLICT from "@salesforce/label/c.AXF_CardStatement_codeCONFLICT";
import codeINVALID_INPUT from "@salesforce/label/c.AXF_CardStatement_codeINVALID_INPUT";
import codeREJECTED from "@salesforce/label/c.AXF_CardStatement_codeREJECTED";
import loading from "@salesforce/label/c.AXF_BankStatement_loading";
import colHolder from "@salesforce/label/c.AXF_BankStatement_colHolder";
import colActions from "@salesforce/label/c.AXF_BankStatement_colActions";
import save from "@salesforce/label/c.AXF_BankStatement_save";
import cancel from "@salesforce/label/c.AXF_BankStatement_cancel";
import customPeriod from "@salesforce/label/c.AXF_BankStatement_customPeriod";
import filtersLegend from "@salesforce/label/c.AXF_BankStatement_filtersLegend";
import fromDate from "@salesforce/label/c.AXF_BankStatement_fromDate";
import toDate from "@salesforce/label/c.AXF_BankStatement_toDate";
import minAmount from "@salesforce/label/c.AXF_BankStatement_minAmount";
import maxAmount from "@salesforce/label/c.AXF_BankStatement_maxAmount";
import term from "@salesforce/label/c.AXF_BankStatement_term";
import applyFilters from "@salesforce/label/c.AXF_BankStatement_applyFilters";
import clearFilters from "@salesforce/label/c.AXF_BankStatement_clearFilters";
import colDate from "@salesforce/label/c.AXF_BankStatement_colDate";
import colDescription from "@salesforce/label/c.AXF_BankStatement_colDescription";
import colOrigin from "@salesforce/label/c.AXF_BankStatement_colOrigin";
import colAmount from "@salesforce/label/c.AXF_BankStatement_colAmount";
import colStatus from "@salesforce/label/c.AXF_BankStatement_colStatus";
import statusRECONCILED from "@salesforce/label/c.AXF_BankStatement_statusRECONCILED";
import statusPARTIAL from "@salesforce/label/c.AXF_BankStatement_statusPARTIAL";
import statusUNRECONCILED from "@salesforce/label/c.AXF_BankStatement_statusUNRECONCILED";
import statusUNVERIFIED from "@salesforce/label/c.AXF_BankStatement_statusUNVERIFIED";
import originPLUGGY from "@salesforce/label/c.AXF_BankStatement_originPLUGGY";
import originCSV from "@salesforce/label/c.AXF_BankStatement_originCSV";
import originMANUAL from "@salesforce/label/c.AXF_BankStatement_originMANUAL";
import originPLANNED from "@salesforce/label/c.AXF_BankStatement_originPLANNED";
import originACTUAL_ONLY from "@salesforce/label/c.AXF_BankStatement_originACTUAL_ONLY";
import showSuggestions from "@salesforce/label/c.AXF_BankStatement_showSuggestions";
import showSuggestionsFor from "@salesforce/label/c.AXF_BankStatement_showSuggestionsFor";
import suggestionsCaption from "@salesforce/label/c.AXF_BankStatement_suggestionsCaption";
import noSuggestions from "@salesforce/label/c.AXF_BankStatement_noSuggestions";
import suggestionAction from "@salesforce/label/c.AXF_BankStatement_suggestionAction";
import tied from "@salesforce/label/c.AXF_BankStatement_tied";
import confirmed from "@salesforce/label/c.AXF_BankStatement_confirmed";
import truncated from "@salesforce/label/c.AXF_BankStatement_truncated";
import error from "@salesforce/label/c.AXF_BankStatement_error";
import codeUNAVAILABLE from "@salesforce/label/c.AXF_BankStatement_codeUNAVAILABLE";
import codeALREADY_LINKED from "@salesforce/label/c.AXF_BankStatement_codeALREADY_LINKED";
import codeOUT_OF_WINDOW from "@salesforce/label/c.AXF_BankStatement_codeOUT_OF_WINDOW";
import codeEXHAUSTED from "@salesforce/label/c.AXF_BankStatement_codeEXHAUSTED";
import codeREVIEW_OPEN from "@salesforce/label/c.AXF_BankStatement_codeREVIEW_OPEN";
import filterPeriodIncomplete from "@salesforce/label/c.AXF_BankStatement_filterPeriodIncomplete";
import filterPeriodOrder from "@salesforce/label/c.AXF_BankStatement_filterPeriodOrder";
import filterPeriodTooLong from "@salesforce/label/c.AXF_BankStatement_filterPeriodTooLong";
import filterAmountOrder from "@salesforce/label/c.AXF_BankStatement_filterAmountOrder";

export default {
  title,
  intro,
  noCapability,
  cardsCaption,
  noCards,
  colCard,
  colCreditLimit,
  colAvailableLimit,
  colClosingDay,
  colDueDay,
  notAvailable,
  viewInvoice,
  viewInvoiceFor,
  defineClosing,
  defineClosingFor,
  closingDayInput,
  dueDayInput,
  dayRange,
  closingSaved,
  invoiceCaption,
  previousInvoice,
  nextInvoice,
  invoiceWindow,
  closingDate,
  dueDate,
  total,
  totalPartial,
  mixedCurrency,
  plannedTotal,
  noCalendar,
  newExpense,
  noLines,
  codeNOT_ACCESSIBLE,
  codeNOT_ALLOWED,
  codeCONFLICT,
  codeINVALID_INPUT,
  codeREJECTED,
  loading,
  colHolder,
  colActions,
  save,
  cancel,
  customPeriod,
  filtersLegend,
  fromDate,
  toDate,
  minAmount,
  maxAmount,
  term,
  applyFilters,
  clearFilters,
  colDate,
  colDescription,
  colOrigin,
  colAmount,
  colStatus,
  statusRECONCILED,
  statusPARTIAL,
  statusUNRECONCILED,
  statusUNVERIFIED,
  originPLUGGY,
  originCSV,
  originMANUAL,
  originPLANNED,
  originACTUAL_ONLY,
  showSuggestions,
  showSuggestionsFor,
  suggestionsCaption,
  noSuggestions,
  suggestionAction,
  tied,
  confirmed,
  truncated,
  error,
  codeUNAVAILABLE,
  codeALREADY_LINKED,
  codeOUT_OF_WINDOW,
  codeEXHAUSTED,
  codeREVIEW_OPEN,
  filterPeriodIncomplete,
  filterPeriodOrder,
  filterPeriodTooLong,
  filterAmountOrder
};
