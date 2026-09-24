// AXF-154: queue-specific texts; statement and invoice texts are shared with AXF-151/152.
import title from "@salesforce/label/c.AXF_ReconciliationQueue_title";
import intro from "@salesforce/label/c.AXF_ReconciliationQueue_intro";
import readOnly from "@salesforce/label/c.AXF_ReconciliationQueue_readOnly";
import noSources from "@salesforce/label/c.AXF_ReconciliationQueue_noSources";
import filterKind from "@salesforce/label/c.AXF_ReconciliationQueue_filterKind";
import kindAll from "@salesforce/label/c.AXF_ReconciliationQueue_kindAll";
import kindBANK from "@salesforce/label/c.AXF_ReconciliationQueue_kindBANK";
import kindCARD from "@salesforce/label/c.AXF_ReconciliationQueue_kindCARD";
import filterSource from "@salesforce/label/c.AXF_ReconciliationQueue_filterSource";
import sourceAll from "@salesforce/label/c.AXF_ReconciliationQueue_sourceAll";
import filterInvoice from "@salesforce/label/c.AXF_ReconciliationQueue_filterInvoice";
import invoiceNone from "@salesforce/label/c.AXF_ReconciliationQueue_invoiceNone";
import invoiceNeedsCard from "@salesforce/label/c.AXF_ReconciliationQueue_invoiceNeedsCard";
import filterStatus from "@salesforce/label/c.AXF_ReconciliationQueue_filterStatus";
import statusAll from "@salesforce/label/c.AXF_ReconciliationQueue_statusAll";
import statusPENDING from "@salesforce/label/c.AXF_ReconciliationQueue_statusPENDING";
import counters from "@salesforce/label/c.AXF_ReconciliationQueue_counters";
import period from "@salesforce/label/c.AXF_ReconciliationQueue_period";
import pendingHeading from "@salesforce/label/c.AXF_ReconciliationQueue_pendingHeading";
import noPending from "@salesforce/label/c.AXF_ReconciliationQueue_noPending";
import showReconciled from "@salesforce/label/c.AXF_ReconciliationQueue_showReconciled";
import hideReconciled from "@salesforce/label/c.AXF_ReconciliationQueue_hideReconciled";
import colSource from "@salesforce/label/c.AXF_ReconciliationQueue_colSource";
import loading from "@salesforce/label/c.AXF_BankStatement_loading";
import colHolder from "@salesforce/label/c.AXF_BankStatement_colHolder";
import colActions from "@salesforce/label/c.AXF_BankStatement_colActions";
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
import colAmount from "@salesforce/label/c.AXF_BankStatement_colAmount";
import colStatus from "@salesforce/label/c.AXF_BankStatement_colStatus";
import statusRECONCILED from "@salesforce/label/c.AXF_BankStatement_statusRECONCILED";
import statusPARTIAL from "@salesforce/label/c.AXF_BankStatement_statusPARTIAL";
import statusUNRECONCILED from "@salesforce/label/c.AXF_BankStatement_statusUNRECONCILED";
import statusUNVERIFIED from "@salesforce/label/c.AXF_BankStatement_statusUNVERIFIED";
import showSuggestions from "@salesforce/label/c.AXF_BankStatement_showSuggestions";
import showSuggestionsFor from "@salesforce/label/c.AXF_BankStatement_showSuggestionsFor";
import suggestionsCaption from "@salesforce/label/c.AXF_BankStatement_suggestionsCaption";
import noSuggestions from "@salesforce/label/c.AXF_BankStatement_noSuggestions";
import suggestionAction from "@salesforce/label/c.AXF_BankStatement_suggestionAction";
import tied from "@salesforce/label/c.AXF_BankStatement_tied";
import confirmed from "@salesforce/label/c.AXF_BankStatement_confirmed";
import truncated from "@salesforce/label/c.AXF_BankStatement_truncated";
import error from "@salesforce/label/c.AXF_BankStatement_error";
import codeNOT_ACCESSIBLE from "@salesforce/label/c.AXF_BankStatement_codeNOT_ACCESSIBLE";
import codeUNAVAILABLE from "@salesforce/label/c.AXF_BankStatement_codeUNAVAILABLE";
import codeINVALID_INPUT from "@salesforce/label/c.AXF_BankStatement_codeINVALID_INPUT";
import codeCONFLICT from "@salesforce/label/c.AXF_BankStatement_codeCONFLICT";
import codeALREADY_LINKED from "@salesforce/label/c.AXF_BankStatement_codeALREADY_LINKED";
import codeNOT_ALLOWED from "@salesforce/label/c.AXF_BankStatement_codeNOT_ALLOWED";
import codeOUT_OF_WINDOW from "@salesforce/label/c.AXF_BankStatement_codeOUT_OF_WINDOW";
import codeEXHAUSTED from "@salesforce/label/c.AXF_BankStatement_codeEXHAUSTED";
import codeREVIEW_OPEN from "@salesforce/label/c.AXF_BankStatement_codeREVIEW_OPEN";
import filterPeriodIncomplete from "@salesforce/label/c.AXF_BankStatement_filterPeriodIncomplete";
import filterPeriodOrder from "@salesforce/label/c.AXF_BankStatement_filterPeriodOrder";
import filterPeriodTooLong from "@salesforce/label/c.AXF_BankStatement_filterPeriodTooLong";
import filterAmountOrder from "@salesforce/label/c.AXF_BankStatement_filterAmountOrder";
import invoiceWindow from "@salesforce/label/c.AXF_CardStatement_invoiceWindow";
import closingDate from "@salesforce/label/c.AXF_CardStatement_closingDate";
import dueDate from "@salesforce/label/c.AXF_CardStatement_dueDate";
import noCalendar from "@salesforce/label/c.AXF_CardStatement_noCalendar";

export default {
  title,
  intro,
  readOnly,
  noSources,
  filterKind,
  kindAll,
  kindBANK,
  kindCARD,
  filterSource,
  sourceAll,
  filterInvoice,
  invoiceNone,
  invoiceNeedsCard,
  filterStatus,
  statusAll,
  statusPENDING,
  counters,
  period,
  pendingHeading,
  noPending,
  showReconciled,
  hideReconciled,
  colSource,
  loading,
  colHolder,
  colActions,
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
  colAmount,
  colStatus,
  statusRECONCILED,
  statusPARTIAL,
  statusUNRECONCILED,
  statusUNVERIFIED,
  showSuggestions,
  showSuggestionsFor,
  suggestionsCaption,
  noSuggestions,
  suggestionAction,
  tied,
  confirmed,
  truncated,
  error,
  codeNOT_ACCESSIBLE,
  codeUNAVAILABLE,
  codeINVALID_INPUT,
  codeCONFLICT,
  codeALREADY_LINKED,
  codeNOT_ALLOWED,
  codeOUT_OF_WINDOW,
  codeEXHAUSTED,
  codeREVIEW_OPEN,
  filterPeriodIncomplete,
  filterPeriodOrder,
  filterPeriodTooLong,
  filterAmountOrder,
  invoiceWindow,
  closingDate,
  dueDate,
  noCalendar
};
