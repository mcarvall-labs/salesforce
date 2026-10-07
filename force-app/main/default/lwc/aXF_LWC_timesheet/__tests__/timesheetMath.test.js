import {
  dayHours,
  checkDay,
  limitError,
  totalHours,
  plan
} from "../timesheetMath";

function day(workDate, times = {}, workingDay = true) {
  return { workDate, workingDay, ...times };
}

describe("timesheetMath", () => {
  it("sums one and two periods", () => {
    expect(dayHours(day("2026-09-01", { in1: "09:00", out1: "17:00" }))).toBe(
      8
    );
    expect(
      dayHours(
        day("2026-09-01", {
          in1: "09:00:00.000",
          out1: "12:30:00.000",
          in2: "13:30:00.000",
          out2: "18:00:00.000"
        })
      )
    ).toBe(8);
    expect(dayHours(day("2026-09-01"))).toBe(0);
    expect(dayHours(day("2026-09-01", { in1: "09:00", out1: "09:20" }))).toBe(
      0.33
    );
  });

  it("waits for half filled periods and rejects reversed ones", () => {
    expect(checkDay(day("d", { in1: "09:00" })).complete).toBe(false);
    expect(
      checkDay(day("d", { in1: "09:00", out1: "12:00", in2: "13:00" })).complete
    ).toBe(false);
    expect(checkDay(day("d")).complete).toBe(true);
    expect(checkDay(day("d", { in1: "17:00", out1: "09:00" })).error).toContain(
      "saída"
    );
    expect(
      checkDay(
        day("d", { in1: "09:00", out1: "13:00", in2: "12:00", out2: "18:00" })
      ).error
    ).toContain("entrada 2");
    expect(
      checkDay(day("d", { in1: "09:00", out1: "17:00" })).error
    ).toBeNull();
  });

  it("blocks above the daily and the monthly limit", () => {
    const saved = day("2026-09-01", { in1: "09:00", out1: "17:00" });
    const target = day("2026-09-02", { in1: "08:00", out1: "18:00" });
    expect(limitError(target, [saved, target], 8, null)).toContain("diário");
    const small = day("2026-09-02", { in1: "09:00", out1: "13:00" });
    expect(limitError(small, [saved, small], null, 10)).toContain("mensal");
    expect(limitError(small, [saved, small], 8, 12)).toBeNull();
    // Editing the saved day itself does not count it twice.
    const edited = day("2026-09-01", { in1: "09:00", out1: "13:00" });
    expect(limitError(edited, [edited], 8, 4)).toBeNull();
  });

  it("totals the month", () => {
    expect(
      totalHours([
        day("a", { in1: "09:00", out1: "17:00" }),
        day("b", { in1: "09:00", out1: "13:00" })
      ])
    ).toBe(12);
  });

  describe("planner", () => {
    const days = [
      day("2026-09-01", { in1: "09:00", out1: "17:00" }),
      day("2026-09-02", { in1: "09:00", out1: "17:00" }),
      day("2026-09-03"),
      day("2026-09-04"),
      day("2026-09-05", {}, false),
      day("2026-09-06", {}, false),
      day("2026-09-07")
    ];

    it("says how many hours per day are still needed", () => {
      const result = plan({
        days,
        today: "2026-09-02",
        dailyLimit: 8,
        monthlyLimit: 40
      });
      expect(result.hoursUntilToday).toBe(16);
      expect(result.remainingDays).toBe(3);
      expect(result.remainingHours).toBe(24);
      expect(result.averagePerDay).toBe(8);
      expect(result.overDailyLimit).toBe(false);
    });

    it("alerts when the average passes the daily limit", () => {
      const result = plan({
        days,
        today: "2026-09-02",
        dailyLimit: 6,
        monthlyLimit: 40
      });
      expect(result.averagePerDay).toBe(8);
      expect(result.overDailyLimit).toBe(true);
    });

    it("alerts when hours are missing and no working day is left", () => {
      const result = plan({
        days,
        today: "2026-09-07",
        dailyLimit: 8,
        monthlyLimit: 40
      });
      expect(result.remainingDays).toBe(0);
      expect(result.remainingHours).toBe(24);
      expect(result.overDailyLimit).toBe(true);
    });

    it("finishes when the monthly limit is reached", () => {
      const result = plan({
        days,
        today: "2026-09-02",
        dailyLimit: 8,
        monthlyLimit: 16
      });
      expect(result.remainingHours).toBe(0);
      expect(result.finished).toBe(true);
      expect(result.overDailyLimit).toBe(false);
    });

    it("forecasts the month with a daily limit only", () => {
      const result = plan({
        days,
        today: "2026-09-02",
        dailyLimit: 8,
        monthlyLimit: null
      });
      expect(result.forecast).toBe(40);
      expect(result.remainingHours).toBeNull();
    });

    it("counts every working day of a future month and none of a past one", () => {
      expect(
        plan({ days, today: "2026-08-31", dailyLimit: 8, monthlyLimit: 40 })
          .remainingDays
      ).toBe(5);
      expect(
        plan({ days, today: "2026-10-01", dailyLimit: 8, monthlyLimit: 40 })
          .remainingDays
      ).toBe(0);
    });

    it("forecasts the month also when both limits exist", () => {
      const result = plan({
        days,
        today: "2026-09-02",
        dailyLimit: 8,
        monthlyLimit: 40
      });
      expect(result.forecast).toBe(40);
      expect(result.remainingHours).toBe(24);
    });

    it("does not alert or forecast for a month that is over", () => {
      const result = plan({
        days,
        today: "2026-10-01",
        dailyLimit: 8,
        monthlyLimit: 80
      });
      expect(result.isPastMonth).toBe(true);
      expect(result.remainingDays).toBe(0);
      expect(result.overDailyLimit).toBe(false);
      expect(result.forecast).toBeNull();
    });
  });
});
