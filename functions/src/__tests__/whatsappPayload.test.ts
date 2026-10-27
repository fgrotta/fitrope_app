import {
  buildDemoLessonPayload,
  sanitizeTemplateParam,
} from "../whatsapp/payload";

const base = {
  phoneE164: "+393331234567",
  lezione: "Corso Excel Avanzato",
  // 15 ottobre 2026, 18:00 ora di Roma (CEST).
  startAtMillis: Date.UTC(2026, 9, 15, 16),
};

describe("sanitizeTemplateParam", () => {
  test("collassa spazi, newline e tab", () => {
    expect(sanitizeTemplateParam("  Pole\n  Dance\tBase    ")).toBe("Pole Dance Base");
  });

  test("gestisce null e undefined", () => {
    expect(sanitizeTemplateParam(null)).toBe("");
    expect(sanitizeTemplateParam(undefined)).toBe("");
  });
});

describe("buildDemoLessonPayload", () => {
  test("produce esattamente il body atteso dallo scenario Make", () => {
    expect(buildDemoLessonPayload(base)).toEqual({
      numero_di_telefono: "+393331234567",
      lezione: "Corso Excel Avanzato",
      giorno_lezione: "15 Ottobre",
      orario_lezione: "18:00",
    });
  });

  test("espone esattamente quattro chiavi, le variabili del template più il destinatario", () => {
    expect(Object.keys(buildDemoLessonPayload(base)).sort()).toEqual([
      "giorno_lezione",
      "lezione",
      "numero_di_telefono",
      "orario_lezione",
    ]);
  });

  test("non contiene credenziali né i vecchi campi", () => {
    const payload = buildDemoLessonPayload(base) as unknown as Record<string, unknown>;
    expect(payload.token).toBeUndefined();
    expect(payload.apiKey).toBeUndefined();
    expect(payload["Demo-Reminder"]).toBeUndefined();
    for (const old of ["tipo", "nome", "corso", "giorno", "orario"]) {
      expect(payload).not.toHaveProperty(old);
    }
  });

  test("sanifica il nome della lezione per i parametri del template", () => {
    const payload = buildDemoLessonPayload({ ...base, lezione: "Pole\tDance    Base\n" });
    expect(payload.lezione).toBe("Pole Dance Base");
    for (const value of Object.values(payload)) {
      expect(value).not.toMatch(/[\n\t]| {4}/);
    }
  });

  test("usa giorno e orario passati esplicitamente (callable di prova)", () => {
    const payload = buildDemoLessonPayload({
      ...base,
      giornoLezione: "28 Ottobre",
      orarioLezione: "19:00",
    });
    expect(payload.giorno_lezione).toBe("28 Ottobre");
    expect(payload.orario_lezione).toBe("19:00");
  });

  test("ricade sulla data della lezione se giorno e orario sono vuoti", () => {
    const payload = buildDemoLessonPayload({ ...base, giornoLezione: " ", orarioLezione: "" });
    expect(payload.giorno_lezione).toBe("15 Ottobre");
    expect(payload.orario_lezione).toBe("18:00");
  });

  test("rifiuta un campo vuoto invece di mandarlo a Make", () => {
    expect(() => buildDemoLessonPayload({ ...base, lezione: "   " })).toThrow(/lezione/);
    expect(() => buildDemoLessonPayload({ ...base, phoneE164: "" })).toThrow(/numero_di_telefono/);
  });
});
