import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getMonth from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getMonth";
import saveDay from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.saveDay";
import fillWorkdays from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.fillWorkdays";
import createTimesheetPdf from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.createTimesheetPdf";
import createInvoicePdf from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.createInvoicePdf";
import {
  dayHours,
  checkDay,
  limitError,
  totalHours,
  plan
} from "./timesheetMath";

const MONTHS = [
  "janeiro",
  "fevereiro",
  "março",
  "abril",
  "maio",
  "junho",
  "julho",
  "agosto",
  "setembro",
  "outubro",
  "novembro",
  "dezembro"
];
const WEEKDAYS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];
const FIELDS = ["in1", "out1", "in2", "out2"];

function pad(value) {
  return String(value).padStart(2, "0");
}

function hoursText(value) {
  return `${value.toFixed(2).replace(".", ",")} h`;
}

export default class AXF_LWC_timesheet extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  year;
  month;
  isLoading = false;
  isSaving = false;
  errorMessage;
  settings;
  days = [];
  errors = {};
  loadSeq = 0;
  pendingDates = [];
  noticeMessage;

  connectedCallback() {
    const now = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth() + 1;
    this.load();
  }

  get isBusy() {
    return this.isLoading || this.isSaving;
  }

  get showInvoiceButton() {
    return (
      this.hasMonth &&
      Boolean(this.settings.currencyCode) &&
      this.settings.currencyCode !== "BRL"
    );
  }

  get hasMonth() {
    return Boolean(this.settings);
  }

  get monthLabel() {
    return `${MONTHS[this.month - 1]} de ${this.year}`;
  }

  // Totals and planner use what is saved: a row that was rejected does not count.
  get countedDays() {
    return this.days.map((day) => {
      const rejected = this.errors[day.workDate] && day.saved;
      return rejected ? { ...day, ...day.saved } : day;
    });
  }

  get todayIso() {
    const now = new Date();
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  }

  get hasMonthlyLimit() {
    return this.hasMonth && this.settings.monthlyLimit != null;
  }

  get hasDailyLimit() {
    return this.hasMonth && this.settings.dailyLimit != null;
  }

  get totalLabel() {
    return hoursText(totalHours(this.countedDays));
  }

  get amountLabel() {
    const amount =
      totalHours(this.countedDays) * (this.settings.hourlyRate || 0);
    return new Intl.NumberFormat("pt-BR", {
      style: "currency",
      currency: this.settings.currencyCode || "BRL"
    }).format(amount);
  }

  get hasRate() {
    return this.hasMonth && this.settings.hourlyRate != null;
  }

  get monthlyLimitLabel() {
    return hoursText(this.settings.monthlyLimit);
  }

  get dailyLimitLabel() {
    return hoursText(this.settings.dailyLimit);
  }

  get missingLabel() {
    const missing = Math.max(
      this.settings.monthlyLimit - totalHours(this.countedDays),
      0
    );
    return hoursText(missing);
  }

  get planner() {
    if (!this.hasMonth) {
      return {};
    }
    const result = plan({
      days: this.countedDays,
      today: this.todayIso,
      dailyLimit: this.settings.dailyLimit,
      monthlyLimit: this.settings.monthlyLimit
    });
    let alert = null;
    if (result.overDailyLimit) {
      alert =
        result.remainingDays === 0
          ? "Não há mais dias úteis neste mês para completar as horas."
          : `A média necessária (${hoursText(result.averagePerDay)}) passa do limite diário de ${hoursText(this.settings.dailyLimit)}.`;
    }
    return {
      untilToday: hoursText(result.hoursUntilToday),
      remainingDays: result.remainingDays,
      hasRemainingHours: result.remainingHours !== null,
      remainingHours:
        result.remainingHours === null ? "" : hoursText(result.remainingHours),
      average:
        result.averagePerDay === null ? "-" : hoursText(result.averagePerDay),
      hasForecast: result.forecast !== null,
      forecast: result.forecast === null ? "" : hoursText(result.forecast),
      alert
    };
  }

  get rows() {
    return this.days.map((day) => {
      const date = new Date(`${day.workDate}T12:00:00`);
      const hours = dayHours(day);
      return {
        ...day,
        label: `${WEEKDAYS[date.getDay()]} ${pad(date.getDate())}/${pad(date.getMonth() + 1)}`,
        rowClass: day.workingDay ? "" : "slds-theme_shade",
        hoursLabel: hours > 0 ? hoursText(hours) : "-",
        error: this.errors[day.workDate]
      };
    });
  }

  async load() {
    const seq = ++this.loadSeq;
    this.isLoading = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      const month = await getMonth({
        contractId: this.recordId,
        year: this.year,
        month: this.month
      });
      if (seq !== this.loadSeq) {
        return;
      }
      this.apply(month);
    } catch (error) {
      if (seq !== this.loadSeq) {
        return;
      }
      this.errorMessage = this.messageOf(error);
      this.settings = undefined;
      this.days = [];
    } finally {
      if (seq === this.loadSeq) {
        this.isLoading = false;
      }
    }
  }

  apply(month) {
    this.settings = {
      dailyLimit: month.dailyLimit,
      monthlyLimit: month.monthlyLimit,
      hourlyRate: month.hourlyRate,
      currencyCode: month.currencyCode
    };
    this.errors = {};
    this.days = month.days.map((day) => ({
      workDate: day.workDate,
      workingDay: day.workingDay,
      in1: day.in1,
      out1: day.out1,
      in2: day.in2,
      out2: day.out2,
      saved: {
        in1: day.in1,
        out1: day.out1,
        in2: day.in2,
        out2: day.out2
      },
      dirty: false
    }));
  }

  messageOf(error) {
    return error?.body?.message || "Não foi possível concluir a operação.";
  }

  handlePrevious() {
    this.shiftMonth(-1);
  }

  handleNext() {
    this.shiftMonth(1);
  }

  get hasUnsavedDays() {
    return this.days.some((day) => day.dirty || this.errors[day.workDate]);
  }

  shiftMonth(delta) {
    if (this.hasUnsavedDays || this.isSaving) {
      this.noticeMessage =
        "Salve ou corrija os horários deste mês antes de mudar de mês.";
      return;
    }
    const moved = new Date(this.year, this.month - 1 + delta, 1);
    this.year = moved.getFullYear();
    this.month = moved.getMonth() + 1;
    this.load();
  }

  handleChange(event) {
    const { date, field } = event.target.dataset;
    if (!FIELDS.includes(field)) {
      return;
    }
    const value = event.detail.value || null;
    this.days = this.days.map((day) => {
      if (day.workDate !== date) {
        return day;
      }
      return { ...day, [field]: value, dirty: true };
    });
  }

  // The day is saved when the user leaves a field, as long as no period is left half filled.
  handleBlur(event) {
    this.saveDate(event.target.dataset.date);
  }

  async saveDate(date) {
    if (this.isSaving) {
      // Another save is running: remember the day and save it right after.
      if (!this.pendingDates.includes(date)) {
        this.pendingDates = [...this.pendingDates, date];
      }
      return;
    }
    const day = this.days.find((item) => item.workDate === date);
    if (!day || !day.dirty) {
      return;
    }
    const check = checkDay(day);
    if (!check.complete) {
      return;
    }
    const problem =
      check.error ||
      limitError(
        day,
        this.countedDays,
        this.settings.dailyLimit,
        this.settings.monthlyLimit
      );
    if (problem) {
      this.errors = { ...this.errors, [date]: problem };
      return;
    }
    const sent = { in1: day.in1, out1: day.out1, in2: day.in2, out2: day.out2 };
    let editedDuringSave = false;
    this.isSaving = true;
    this.noticeMessage = undefined;
    try {
      const result = await saveDay({
        contractId: this.recordId,
        workDate: date,
        ...sent
      });
      const rest = { ...this.errors };
      delete rest[date];
      this.errors = rest;
      this.days = this.days.map((item) => {
        if (item.workDate !== date) {
          return item;
        }
        // An edit made while the call was running keeps the day dirty.
        const same = FIELDS.every((field) => item[field] === sent[field]);
        editedDuringSave = !same;
        return { ...item, saved: sent, dirty: !same };
      });
      if (result && result.entryLocked) {
        this.noticeMessage =
          "O lançamento deste mês já foi realizado: as horas foram gravadas, mas o valor não muda.";
      }
    } catch (error) {
      this.errors = { ...this.errors, [date]: this.messageOf(error) };
    } finally {
      this.isSaving = false;
    }
    const next = this.pendingDates.shift();
    this.pendingDates = [...this.pendingDates];
    if (next) {
      this.saveDate(next);
    } else if (editedDuringSave) {
      this.saveDate(date);
    }
  }

  handleTimesheetPdf() {
    return this.runPdf(createTimesheetPdf);
  }

  handleInvoicePdf() {
    return this.runPdf(createInvoicePdf);
  }

  // Generates the PDF, saves it on the month's entry and opens the download.
  async runPdf(action) {
    if (this.hasUnsavedDays) {
      this.noticeMessage =
        "Salve ou corrija os horários antes de gerar o documento.";
      return;
    }
    this.isSaving = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      const file = await action({
        contractId: this.recordId,
        year: this.year,
        month: this.month
      });
      this.noticeMessage = `${file.title} salvo no lançamento do mês.`;
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: {
          url: `/sfc/servlet.shepherd/document/download/${file.documentId}`
        }
      });
    } catch (error) {
      this.errorMessage = this.messageOf(error);
    } finally {
      this.isSaving = false;
    }
  }

  async handleFill() {
    if (this.hasUnsavedDays) {
      this.noticeMessage =
        "Salve ou corrija os horários antes de preencher os dias úteis.";
      return;
    }
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      const month = await fillWorkdays({
        contractId: this.recordId,
        year: this.year,
        month: this.month
      });
      this.apply(month);
      this.noticeMessage =
        month.skippedDays > 0
          ? `${month.filledDays} dia(s) preenchido(s); ${month.skippedDays} não couberam no limite mensal.`
          : `${month.filledDays} dia(s) preenchido(s).`;
    } catch (error) {
      this.errorMessage = this.messageOf(error);
    } finally {
      this.isSaving = false;
    }
  }
}
