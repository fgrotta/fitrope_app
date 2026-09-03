import {
  MONTH_NAMES_IT,
  formatGiorno,
  formatOrario,
  isSameRomeDay,
  romeDayWindow,
  romeDayWindowPadded,
  romeWallClock,
} from "../romeTime";

const iso = (ms: number) => new Date(ms).toISOString();

describe("romeWallClock", () => {
  it("applica l'offset CET in inverno", () => {
    expect(romeWallClock(new Date("2026-01-15T18:00:00Z"))).toEqual({
      year: 2026,
      month: 1,
      day: 15,
      hour: 19,
      minute: 0,
    });
  });

  it("applica l'offset CEST in estate", () => {
    expect(romeWallClock(new Date("2026-07-15T17:00:00Z"))).toEqual({
      year: 2026,
      month: 7,
      day: 15,
      hour: 19,
      minute: 0,
    });
  });

  it("avanza al giorno successivo quando l'offset scavalca la mezzanotte", () => {
    // 22:30 UTC del 1 luglio = 00:30 del 2 luglio a Roma (CEST, +2).
    expect(romeWallClock(new Date("2026-07-01T22:30:00Z"))).toMatchObject({
      month: 7,
      day: 2,
      hour: 0,
      minute: 30,
    });
  });
});

describe("formatGiorno", () => {
  it("usa il mese minuscolo con l'anno, senza giorno della settimana", () => {
    expect(formatGiorno(new Date("2026-01-15T18:00:00Z"))).toBe("15 gennaio 2026");
  });

  it("formatta correttamente una data estiva", () => {
    expect(formatGiorno(new Date("2026-07-15T17:00:00Z"))).toBe("15 luglio 2026");
  });

  it("non zero-padda il giorno del mese", () => {
    expect(formatGiorno(new Date("2026-10-03T10:00:00Z"))).toBe("3 ottobre 2026");
  });

  it("usa il giorno di Roma, non quello UTC", () => {
    expect(formatGiorno(new Date("2026-07-01T22:30:00Z"))).toBe("2 luglio 2026");
  });

  it("copre tutti i dodici mesi", () => {
    expect(MONTH_NAMES_IT).toHaveLength(12);
    for (let m = 1; m <= 12; m++) {
      const d = new Date(Date.UTC(2026, m - 1, 15, 12, 0, 0));
      expect(formatGiorno(d)).toBe(`15 ${MONTH_NAMES_IT[m - 1]} 2026`);
    }
  });
});

describe("formatOrario", () => {
  it("rende la mezzanotte come 00:00 e non come 24:00", () => {
    // Il bug classico di Intl con hour12:false.
    expect(formatOrario(new Date("2026-07-01T22:00:00Z"))).toBe("00:00");
  });

  it("zero-padda ore e minuti a una cifra", () => {
    expect(formatOrario(new Date("2026-01-15T08:05:00Z"))).toBe("09:05");
  });

  it("usa l'orologio di Roma in estate", () => {
    expect(formatOrario(new Date("2026-07-15T16:30:00Z"))).toBe("18:30");
  });

  it("usa l'orologio di Roma in inverno", () => {
    expect(formatOrario(new Date("2026-01-15T17:30:00Z"))).toBe("18:30");
  });
});

describe("isSameRomeDay", () => {
  it("è vero per due istanti dello stesso giorno romano", () => {
    expect(
      isSameRomeDay(new Date("2026-07-01T22:30:00Z"), new Date("2026-07-02T20:00:00Z"))
    ).toBe(true);
  });

  it("è falso a cavallo della mezzanotte romana", () => {
    // 21:30 UTC = 23:30 del 1 luglio; 22:30 UTC = 00:30 del 2 luglio.
    expect(
      isSameRomeDay(new Date("2026-07-01T21:30:00Z"), new Date("2026-07-01T22:30:00Z"))
    ).toBe(false);
  });
});

describe("romeDayWindow", () => {
  it("seleziona il giorno successivo e non oggi né dopodomani", () => {
    const now = new Date("2026-07-01T10:00:00Z"); // 12:00 del 1 luglio a Roma
    const w = romeDayWindow(now, 1);

    const oggi19 = new Date("2026-07-01T17:00:00Z").getTime();
    const domani19 = new Date("2026-07-02T17:00:00Z").getTime();
    const dopodomani19 = new Date("2026-07-03T17:00:00Z").getTime();

    expect(domani19).toBeGreaterThanOrEqual(w.startMs);
    expect(domani19).toBeLessThanOrEqual(w.endMs);
    expect(oggi19).toBeLessThan(w.startMs);
    expect(dopodomani19).toBeGreaterThan(w.endMs);
  });

  it("parte dalla mezzanotte CET il giorno dello spring-forward", () => {
    // Il 29/03/2026 l'ora legale scatta alle 02:00: a mezzanotte si è ancora CET.
    const w = romeDayWindow(new Date("2026-03-28T12:00:00Z"), 1);
    expect(iso(w.startMs)).toBe("2026-03-28T23:00:00.000Z");
  });

  it("parte dalla mezzanotte CEST il giorno del fall-back", () => {
    const w = romeDayWindow(new Date("2026-10-24T12:00:00Z"), 1);
    expect(iso(w.startMs)).toBe("2026-10-24T22:00:00.000Z");
  });

  // I due test seguenti fissano un'asimmetria NOTA e VOLUTA: romeDayWindow usa
  // l'offset della mezzanotte del giorno target anche per l'estremo superiore.
  // Non è un bug da correggere qui (cambierebbe il comportamento delle email
  // certificati, salvate a 23:59): chi ha bisogno di precisione al minuto usa
  // romeDayWindowPadded + isSameRomeDay.
  it("sfora di un'ora nel giorno dopo lo spring-forward", () => {
    const w = romeDayWindow(new Date("2026-03-28T12:00:00Z"), 1);
    // 00:59:59.999 del 30 marzo, non 23:59:59.999 del 29.
    expect(iso(w.endMs)).toBe("2026-03-29T22:59:59.999Z");
  });

  it("si chiude un'ora prima nel giorno del fall-back", () => {
    const w = romeDayWindow(new Date("2026-10-24T12:00:00Z"), 1);
    // 22:59:59.999 ora di Roma: l'ultima ora del giorno resta fuori.
    expect(iso(w.endMs)).toBe("2026-10-25T21:59:59.999Z");
  });
});

describe("romeDayWindowPadded", () => {
  it("allarga la finestra di due ore per lato", () => {
    const now = new Date("2026-07-01T10:00:00Z");
    const w = romeDayWindow(now, 1);
    const p = romeDayWindowPadded(now, 1);
    expect(p.startMs).toBe(w.startMs - 120 * 60000);
    expect(p.endMs).toBe(w.endMs + 120 * 60000);
  });

  it("comprende l'ultima ora del giorno del fall-back, che romeDayWindow perde", () => {
    const now = new Date("2026-10-24T12:00:00Z");
    // 23:30 ora di Roma del 25 ottobre (CET, +1).
    const tardi = new Date("2026-10-25T22:30:00Z").getTime();

    expect(tardi).toBeGreaterThan(romeDayWindow(now, 1).endMs);

    const p = romeDayWindowPadded(now, 1);
    expect(tardi).toBeGreaterThanOrEqual(p.startMs);
    expect(tardi).toBeLessThanOrEqual(p.endMs);
    // …e il filtro in memoria conferma che è davvero il giorno target.
    expect(isSameRomeDay(new Date(tardi), new Date("2026-10-25T12:00:00Z"))).toBe(true);
  });

  it("include istanti fuori dal giorno target, che isSameRomeDay deve scartare", () => {
    const now = new Date("2026-07-01T10:00:00Z");
    const p = romeDayWindowPadded(now, 1);
    // 23:00 ora di Roma del 1 luglio: dentro la finestra allargata, ma è oggi.
    const oggiTardi = new Date("2026-07-01T21:00:00Z");
    expect(oggiTardi.getTime()).toBeGreaterThanOrEqual(p.startMs);
    expect(isSameRomeDay(oggiTardi, new Date("2026-07-02T12:00:00Z"))).toBe(false);
  });
});
