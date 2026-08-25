import { buildCourseIcs, escapeIcsText, foldLine } from "../enrollment/ics";
import { GYM_ADDRESS } from "../enrollment/calendarLinks";

describe("escapeIcsText", () => {
  test("escapa virgole, punti e virgola e backslash", () => {
    expect(escapeIcsText("Hey Mamma, sala 2")).toBe("Hey Mamma\\, sala 2");
    expect(escapeIcsText("a;b")).toBe("a\\;b");
    expect(escapeIcsText("a\\b")).toBe("a\\\\b");
  });

  test("il backslash è escapato prima degli altri (nessun doppio escaping)", () => {
    expect(escapeIcsText("a\\,b")).toBe("a\\\\\\,b");
  });

  test("i newline diventano \\n letterali", () => {
    expect(escapeIcsText("riga1\r\nriga2\nriga3")).toBe("riga1\\nriga2\\nriga3");
  });
});

describe("foldLine", () => {
  test("righe corte invariate", () => {
    expect(foldLine("SUMMARY:Open")).toBe("SUMMARY:Open");
  });

  test("righe lunghe piegate a 75 ottetti con continuazione indentata", () => {
    const folded = foldLine(`SUMMARY:${"a".repeat(200)}`);
    const parts = folded.split("\r\n");
    expect(parts.length).toBeGreaterThan(1);
    expect(Buffer.from(parts[0], "utf8").length).toBe(75);
    for (const part of parts.slice(1)) {
      expect(part.startsWith(" ")).toBe(true);
      expect(Buffer.from(part, "utf8").length).toBeLessThanOrEqual(75);
    }
    // Nessun contenuto perso nel folding.
    expect(parts.join("").replace(/^ | /g, "").length).toBeGreaterThan(0);
    expect(folded.replace(/\r\n /g, "")).toBe(`SUMMARY:${"a".repeat(200)}`);
  });

  test("non spezza a metà una sequenza UTF-8 multi-byte", () => {
    const line = `SUMMARY:${"à".repeat(80)}`;
    const folded = foldLine(line);
    expect(folded.replace(/\r\n /g, "")).toBe(line);
    expect(folded).not.toContain("�");
  });
});

describe("buildCourseIcs", () => {
  const args = {
    courseId: "c1",
    courseName: "Hey Mamma, sala 2",
    startMillis: Date.UTC(2026, 6, 10, 8, 0),
    endMillis: Date.UTC(2026, 6, 10, 9, 0),
    sala: "Sala 2",
    nowMillis: Date.UTC(2026, 6, 1, 12, 0),
  };

  test("struttura VCALENDAR/VEVENT con date UTC corrette", () => {
    const ics = buildCourseIcs(args);
    expect(ics.startsWith("BEGIN:VCALENDAR\r\n")).toBe(true);
    expect(ics.endsWith("END:VCALENDAR\r\n")).toBe(true);
    expect(ics).toContain("VERSION:2.0");
    expect(ics).toContain("UID:course-c1@fithousemonza.it");
    expect(ics).toContain("DTSTAMP:20260701T120000Z");
    expect(ics).toContain("DTSTART:20260710T080000Z");
    expect(ics).toContain("DTEND:20260710T090000Z");
  });

  test("promemoria a -4h nel VALARM", () => {
    const ics = buildCourseIcs(args);
    expect(ics).toContain("BEGIN:VALARM");
    expect(ics).toContain("ACTION:DISPLAY");
    expect(ics).toContain("TRIGGER:-PT4H");
    expect(ics).toContain("END:VALARM");
  });

  test("nome corso con virgola escapato nel SUMMARY", () => {
    expect(buildCourseIcs(args)).toContain("SUMMARY:Hey Mamma\\, sala 2");
  });

  test("LOCATION: sala + indirizzo palestra, virgole escapate", () => {
    // La riga LOCATION supera i 75 ottetti: va srotolata prima di confrontarla.
    const unfold = (ics: string) => ics.replace(/\r\n /g, "");
    const escaped = GYM_ADDRESS.replace(/,/g, "\\,");
    expect(unfold(buildCourseIcs(args))).toContain(
      `LOCATION:Sala 2 — ${escaped}\r\n`
    );
    // Le virgole dell'indirizzo non devono restare nude: separerebbero valori.
    expect(escaped).toContain("Monza\\, Via Giuseppe Ferrari\\, 6");

    const noSala = unfold(buildCourseIcs({ ...args, sala: null }));
    expect(noSala).toContain(`LOCATION:${escaped}\r\n`);
    expect(noSala).not.toContain("Sala 2");
  });

  test("tutte le righe terminano con CRLF", () => {
    const ics = buildCourseIcs(args);
    expect(ics.includes("\n\n")).toBe(false);
    for (const line of ics.split("\r\n")) {
      expect(line.includes("\n")).toBe(false);
    }
  });
});
