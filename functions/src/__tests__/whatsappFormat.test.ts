import {
  MONTH_NAMES_IT,
  formatGiorno,
  formatOrario,
  isSameRomeDay,
  tomorrowRomeRange,
} from "../whatsapp/format";

// Europe/Rome 2026: CET (UTC+1) d'inverno; CEST (UTC+2) dal 29 mar al 25 ott.

describe("formatGiorno", () => {
  test("mese minuscolo con anno, senza giorno della settimana (inverno)", () => {
    expect(formatGiorno(Date.UTC(2026, 0, 15, 18, 0))).toBe("15 gennaio 2026");
  });

  test("data estiva", () => {
    expect(formatGiorno(Date.UTC(2026, 6, 15, 17, 0))).toBe("15 luglio 2026");
  });

  test("non zero-padda il giorno del mese", () => {
    expect(formatGiorno(Date.UTC(2026, 9, 3, 10, 0))).toBe("3 ottobre 2026");
  });

  test("usa il giorno di Roma, non quello UTC", () => {
    // 22:30 UTC del 1 luglio = 00:30 del 2 luglio a Roma.
    expect(formatGiorno(Date.UTC(2026, 6, 1, 22, 30))).toBe("2 luglio 2026");
  });

  test("copre tutti i dodici mesi", () => {
    expect(MONTH_NAMES_IT).toHaveLength(12);
    for (let m = 1; m <= 12; m++) {
      expect(formatGiorno(Date.UTC(2026, m - 1, 15, 12, 0))).toBe(
        `15 ${MONTH_NAMES_IT[m - 1]} 2026`
      );
    }
  });
});

describe("formatOrario", () => {
  test("mezzanotte è 00:00 e non 24:00", () => {
    expect(formatOrario(Date.UTC(2026, 6, 1, 22, 0))).toBe("00:00");
  });

  test("zero-padda ore e minuti", () => {
    expect(formatOrario(Date.UTC(2026, 0, 15, 8, 5))).toBe("09:05");
  });

  test("usa l'orologio di Roma in estate e in inverno", () => {
    expect(formatOrario(Date.UTC(2026, 6, 15, 16, 30))).toBe("18:30");
    expect(formatOrario(Date.UTC(2026, 0, 15, 17, 30))).toBe("18:30");
  });
});

describe("isSameRomeDay", () => {
  test("vero nello stesso giorno romano", () => {
    expect(isSameRomeDay(Date.UTC(2026, 6, 1, 22, 30), Date.UTC(2026, 6, 2, 20, 0))).toBe(true);
  });

  test("falso a cavallo della mezzanotte romana", () => {
    // 21:30 UTC = 23:30 del 1 luglio; 22:30 UTC = 00:30 del 2 luglio.
    expect(isSameRomeDay(Date.UTC(2026, 6, 1, 21, 30), Date.UTC(2026, 6, 1, 22, 30))).toBe(false);
  });
});

describe("tomorrowRomeRange", () => {
  test("giorno ordinario (CEST)", () => {
    expect(tomorrowRomeRange(Date.UTC(2026, 6, 1, 10))).toEqual({
      startMs: Date.UTC(2026, 6, 1, 22), // 2 luglio 00:00 CEST
      endMs: Date.UTC(2026, 6, 2, 22) - 1,
    });
  });

  test("domani è il giorno del fall-back: comprende la lezione delle 23:30", () => {
    const range = tomorrowRomeRange(Date.UTC(2026, 9, 24, 12));
    expect(range).toEqual({
      startMs: Date.UTC(2026, 9, 24, 22), // 25 ottobre 00:00 CEST
      endMs: Date.UTC(2026, 9, 25, 23) - 1, // 26 ottobre 00:00 CET
    });
    const lezione2330 = Date.UTC(2026, 9, 25, 22, 30); // 23:30 CET del 25
    expect(lezione2330).toBeGreaterThanOrEqual(range.startMs);
    expect(lezione2330).toBeLessThanOrEqual(range.endMs);
  });

  test("domani è il giorno dello spring-forward", () => {
    expect(tomorrowRomeRange(Date.UTC(2026, 2, 28, 12))).toEqual({
      startMs: Date.UTC(2026, 2, 28, 23), // 29 marzo 00:00 CET
      endMs: Date.UTC(2026, 2, 29, 22) - 1, // 30 marzo 00:00 CEST
    });
  });

  test("scavalca la fine del mese", () => {
    expect(tomorrowRomeRange(Date.UTC(2026, 9, 31, 12))).toEqual({
      startMs: Date.UTC(2026, 9, 31, 23), // 1 novembre 00:00 CET
      endMs: Date.UTC(2026, 10, 1, 23) - 1,
    });
  });
});
