import {
  romeParts,
  romeWallClockToUtcMillis,
  trialReminderSendAtMillis,
  formatCourseDate,
  formatCourseTime,
} from "../enrollment/notify";
import {
  trialReminderSubject,
  trialReminderBody,
  waitlistSpotAvailableSubject,
  waitlistSpotAvailableBody,
} from "../enrollment/emailTemplates";

// Europe/Rome 2026: CET (UTC+1) d'inverno; CEST (UTC+2) dal 29 mar al 25 ott.

describe("romeParts / romeWallClockToUtcMillis", () => {
  test("inverno (CET, UTC+1): 18:00Z = 19:00 Rome", () => {
    const p = romeParts(Date.UTC(2026, 0, 15, 18, 0));
    expect([p.year, p.month, p.day, p.hour, p.minute]).toEqual([2026, 1, 15, 19, 0]);
  });

  test("estate (CEST, UTC+2): 17:00Z = 19:00 Rome", () => {
    const p = romeParts(Date.UTC(2026, 6, 15, 17, 0));
    expect([p.month, p.day, p.hour]).toEqual([7, 15, 19]);
  });

  test("isoWeekday: 10 giu 2026 è mercoledì (3), 14 giu domenica (7)", () => {
    expect(romeParts(Date.UTC(2026, 5, 10, 8)).isoWeekday).toBe(3);
    expect(romeParts(Date.UTC(2026, 5, 14, 8)).isoWeekday).toBe(7);
  });

  test("round-trip wall-clock → UTC in inverno e in estate", () => {
    expect(romeWallClockToUtcMillis(2026, 1, 15, 19, 0)).toBe(Date.UTC(2026, 0, 15, 18, 0));
    expect(romeWallClockToUtcMillis(2026, 7, 15, 19, 0)).toBe(Date.UTC(2026, 6, 15, 17, 0));
  });

  test("mezzanotte Rome non scivola di giorno (bordo hour24)", () => {
    // 00:30 Rome del 10 giu (CEST) = 22:30Z del 9 giu.
    const p = romeParts(Date.UTC(2026, 5, 9, 22, 30));
    expect([p.day, p.hour, p.minute]).toEqual([10, 0, 30]);
  });
});

describe("trialReminderSendAtMillis (giorno prima, 19:00 Europe/Rome)", () => {
  test("caso base: corso mer 10 giu 10:00 Rome → invio mar 9 giu 19:00 Rome (17:00Z, CEST)", () => {
    const courseStart = Date.UTC(2026, 5, 10, 8); // 10:00 Rome
    expect(trialReminderSendAtMillis(courseStart)).toBe(Date.UTC(2026, 5, 9, 17, 0));
  });

  test("rollover inizio mese: corso 1 lug → invio 30 giu 19:00 Rome", () => {
    const courseStart = Date.UTC(2026, 6, 1, 8); // 1 lug 10:00 Rome
    expect(trialReminderSendAtMillis(courseStart)).toBe(Date.UTC(2026, 5, 30, 17, 0));
  });

  test("rollover febbraio (2026 non bisestile): corso 1 mar → invio 28 feb 19:00 Rome (CET, 18:00Z)", () => {
    const courseStart = Date.UTC(2026, 2, 1, 9); // 1 mar 10:00 Rome (CET)
    expect(trialReminderSendAtMillis(courseStart)).toBe(Date.UTC(2026, 1, 28, 18, 0));
  });

  test("cavallo DST inizio (29 mar): corso 30 mar → invio 29 mar 19:00 Rome = 17:00Z (CEST)", () => {
    const courseStart = Date.UTC(2026, 2, 30, 8); // 30 mar 10:00 Rome (CEST)
    expect(trialReminderSendAtMillis(courseStart)).toBe(Date.UTC(2026, 2, 29, 17, 0));
  });

  test("cavallo DST fine (25 ott): corso 26 ott → invio 25 ott 19:00 Rome = 18:00Z (CET)", () => {
    const courseStart = Date.UTC(2026, 9, 26, 9); // 26 ott 10:00 Rome (CET)
    expect(trialReminderSendAtMillis(courseStart)).toBe(Date.UTC(2026, 9, 25, 18, 0));
  });
});

describe("formatCourseDate / formatCourseTime (wall-clock Rome)", () => {
  test("data in italiano col giorno della settimana", () => {
    expect(formatCourseDate(Date.UTC(2026, 5, 10, 8))).toBe("Mercoledì 10 Giugno");
  });

  test("orario formattato HH:mm - HH:mm in ora di Roma", () => {
    const start = Date.UTC(2026, 5, 10, 8); // 10:00 Rome (CEST)
    const end = Date.UTC(2026, 5, 10, 9); // 11:00 Rome
    expect(formatCourseTime(start, end)).toBe("10:00 - 11:00");
  });

  test("orario invernale usa CET", () => {
    const start = Date.UTC(2026, 0, 15, 18); // 19:00 Rome (CET)
    const end = Date.UTC(2026, 0, 15, 19, 30); // 20:30 Rome
    expect(formatCourseTime(start, end)).toBe("19:00 - 20:30");
  });
});

describe("emailTemplates (mirror del client Dart)", () => {
  test("trial reminder: subject col nome corso, body con data/orario/logo", () => {
    expect(trialReminderSubject("CrossFit")).toBe(
      'Promemoria: la tua lezione di prova "CrossFit" è domani!'
    );
    const body = trialReminderBody({
      courseName: "CrossFit",
      courseDate: "Mercoledì 10 Giugno",
      courseTime: "10:00 - 11:00",
    });
    expect(body).toContain("CrossFit");
    expect(body).toContain("Mercoledì 10 Giugno");
    expect(body).toContain("10:00 - 11:00");
    expect(body).toContain("app.fithousemonza.it");
    expect(body).toContain("<html>");
  });

  test("waitlist: singolare/plurale posti disponibili", () => {
    expect(waitlistSpotAvailableSubject("Open")).toBe(
      'Posto disponibile nel corso "Open"!'
    );
    const single = waitlistSpotAvailableBody({
      courseName: "Open",
      courseDate: "Mercoledì 10 Giugno",
      courseTime: "10:00 - 11:00",
      spotsAvailable: 1,
    });
    expect(single).toContain("1 posto disponibile");
    const plural = waitlistSpotAvailableBody({
      courseName: "Open",
      courseDate: "Mercoledì 10 Giugno",
      courseTime: "10:00 - 11:00",
      spotsAvailable: 3,
    });
    expect(plural).toContain("3 posti disponibili");
  });
});
