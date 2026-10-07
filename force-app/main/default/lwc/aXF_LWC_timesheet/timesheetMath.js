// Pure rules of the timesheet (hours of a day, valid periods, limits and the hour planner).
// Times are the lightning-input text ("HH:mm" or "HH:mm:ss.SSS"); dates are "YYYY-MM-DD".

export function toMinutes(time) {
  if (!time) {
    return null;
  }
  const [hours, minutes] = time.split(":");
  return Number(hours) * 60 + Number(minutes);
}

function periodMinutes(start, end) {
  const from = toMinutes(start);
  const to = toMinutes(end);
  return from === null || to === null ? 0 : to - from;
}

export function round2(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

// Hours of one day with up to two periods, rounded to 2 places like the server.
export function dayHours(day) {
  const minutes =
    periodMinutes(day.in1, day.out1) + periodMinutes(day.in2, day.out2);
  return round2(minutes / 60);
}

// A day can be saved when each period is either empty or complete and in order.
export function checkDay(day) {
  const first = [day.in1, day.out1].filter(Boolean).length;
  const second = [day.in2, day.out2].filter(Boolean).length;
  if (first === 1 || second === 1) {
    return { complete: false, error: null };
  }
  if (
    periodMinutes(day.in1, day.out1) < 0 ||
    periodMinutes(day.in2, day.out2) < 0
  ) {
    return { complete: true, error: "A saída deve ser depois da entrada." };
  }
  if (day.out1 && day.in2 && toMinutes(day.in2) < toMinutes(day.out1)) {
    return {
      complete: true,
      error: "A entrada 2 não pode ser antes da saída 1."
    };
  }
  return { complete: true, error: null };
}

export function limitError(day, days, dailyLimit, monthlyLimit) {
  const hours = dayHours(day);
  if (dailyLimit !== null && dailyLimit !== undefined && hours > dailyLimit) {
    return `Passa do limite diário de ${dailyLimit} h.`;
  }
  if (monthlyLimit !== null && monthlyLimit !== undefined) {
    const others = days
      .filter((other) => other.workDate !== day.workDate)
      .reduce((sum, other) => sum + dayHours(other), 0);
    if (round2(others + hours) > monthlyLimit) {
      return `Passa do limite mensal de ${monthlyLimit} h.`;
    }
  }
  return null;
}

export function totalHours(days) {
  return round2(days.reduce((sum, day) => sum + dayHours(day), 0));
}

// "Hoje trabalhei 8 h, restam X h em Y dias = Z h/dia".
// Hours up to today count today; the remaining working days are the ones after today.
export function plan({ days, today, dailyLimit, monthlyLimit }) {
  const hoursUntilToday = round2(
    days
      .filter((day) => day.workDate <= today)
      .reduce((sum, day) => sum + dayHours(day), 0)
  );
  const remainingDays = days.filter(
    (day) => day.workingDay && day.workDate > today
  ).length;
  const lastDay = days.length ? days[days.length - 1].workDate : null;
  const isPastMonth = lastDay !== null && today > lastDay;
  const hasDaily = dailyLimit !== null && dailyLimit !== undefined;
  const hasMonthly = monthlyLimit !== null && monthlyLimit !== undefined;
  const result = {
    hoursUntilToday,
    remainingDays,
    remainingHours: null,
    averagePerDay: null,
    forecast: null,
    overDailyLimit: false,
    finished: false,
    isPastMonth
  };
  if (hasDaily && !isPastMonth) {
    // Working days left x daily limit, on top of what is already logged.
    result.forecast = round2(hoursUntilToday + remainingDays * dailyLimit);
  }
  if (hasMonthly) {
    result.remainingHours = round2(Math.max(monthlyLimit - hoursUntilToday, 0));
    result.finished = result.remainingHours === 0;
    if (remainingDays > 0) {
      result.averagePerDay = round2(result.remainingHours / remainingDays);
      result.overDailyLimit = hasDaily && result.averagePerDay > dailyLimit;
    } else if (result.remainingHours > 0 && !isPastMonth) {
      // No working day is left in the current month but hours are: the target cannot be met.
      result.overDailyLimit = true;
    }
  }
  return result;
}
