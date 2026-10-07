import { LightningElement, api } from "lwc";
import getMonth from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getMonth";
import saveDay from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.saveDay";
import fillWorkdays from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.fillWorkdays";
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

export default class AXF_LWC_timesheet extends LightningElement {
  @api recordId;

  year;
  month;
  isLoading = false;
  isSaving = false;
  errorMessage;
  settings;
  days = [];
  errors = {};

  connectedCallback() {
    const now = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth() + 1;
    this.load();
  }

  get isBusy() {
    return this.isLoading || this.isSaving;
  }

  get hasMonth() {
    return Boolean(this.settings);
  }

  get monthLabel() {
    return `${MONTHS[this.month - 1]} de ${this.year}`;
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
    return hoursText(totalHours(this.days));
  }

  get monthlyLimitLabel() {
    return hoursText(this.settings.monthlyLimit);
  }

  get dailyLimitLabel() {
    return hoursText(this.settings.dailyLimit);
  }

  get missingLabel() {
    const missing = Math.max(
      this.settings.monthlyLimit - totalHours(this.days),
      0
    );
    return hoursText(missing);
  }

  get planner() {
    if (!this.hasMonth) {
      return {};
    }
    const result = plan({
      days: this.days,
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
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const month = await getMonth({
        contractId: this.recordId,
        year: this.year,
        month: this.month
      });
      this.apply(month);
    } catch (error) {
      this.errorMessage = this.messageOf(error);
      this.settings = undefined;
      this.days = [];
    } finally {
      this.isLoading = false;
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

  shiftMonth(delta) {
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
    this.days = this.days.map((day) =>
      day.workDate === date ? { ...day, [field]: value, dirty: true } : day
    );
  }

  // The day is saved when the user leaves a field, as long as no period is left half filled.
  async handleBlur(event) {
    const { date } = event.target.dataset;
    const day = this.days.find((item) => item.workDate === date);
    if (!day || !day.dirty || this.isSaving) {
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
        this.days,
        this.settings.dailyLimit,
        this.settings.monthlyLimit
      );
    if (problem) {
      this.errors = { ...this.errors, [date]: problem };
      return;
    }
    this.isSaving = true;
    try {
      await saveDay({
        contractId: this.recordId,
        workDate: date,
        in1: day.in1,
        out1: day.out1,
        in2: day.in2,
        out2: day.out2
      });
      const { [date]: removed, ...rest } = this.errors;
      this.errors = rest;
      this.days = this.days.map((item) =>
        item.workDate === date ? { ...item, dirty: false } : item
      );
    } catch (error) {
      this.errors = { ...this.errors, [date]: this.messageOf(error) };
    } finally {
      this.isSaving = false;
    }
  }

  async handleFill() {
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      const month = await fillWorkdays({
        contractId: this.recordId,
        year: this.year,
        month: this.month
      });
      this.apply(month);
    } catch (error) {
      this.errorMessage = this.messageOf(error);
    } finally {
      this.isSaving = false;
    }
  }
}
