import {
  buildDemoLessonPayload,
  buildNome,
  sanitizeTemplateParam,
} from "../whatsapp/payload";

const base = {
  nome: "Mario Rossi",
  phoneE164: "+393331234567",
  corso: "Corso Excel Avanzato",
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

describe("buildNome", () => {
  test("unisce nome e cognome", () => {
    expect(buildNome("Mario", "Rossi")).toBe("Mario Rossi");
  });

  test("non lascia spazi con il cognome vuoto", () => {
    expect(buildNome("Mario", "")).toBe("Mario");
    expect(buildNome("Mario", null)).toBe("Mario");
  });

  test("è vuoto se mancano entrambi", () => {
    expect(buildNome(null, undefined)).toBe("");
  });
});

describe("buildDemoLessonPayload", () => {
  test("produce esattamente il body atteso dallo scenario Make", () => {
    expect(buildDemoLessonPayload(base)).toEqual({
      nome: "Mario Rossi",
      numero_di_telefono: "+393331234567",
      corso: "Corso Excel Avanzato",
      giorno: "15 ottobre 2026",
      orario: "18:00",
    });
  });

  test("espone esattamente cinque chiavi, senza tipo (Make impara lo schema dal primo payload)", () => {
    expect(Object.keys(buildDemoLessonPayload(base)).sort()).toEqual([
      "corso",
      "giorno",
      "nome",
      "numero_di_telefono",
      "orario",
    ]);
  });

  test("non contiene credenziali né il vecchio campo tipo", () => {
    const payload = buildDemoLessonPayload(base) as unknown as Record<string, unknown>;
    expect(payload.token).toBeUndefined();
    expect(payload.apiKey).toBeUndefined();
    expect(payload["Demo-Reminder"]).toBeUndefined();
    expect(payload).not.toHaveProperty("tipo");
  });

  test("sanifica nome e corso per i parametri del template", () => {
    const payload = buildDemoLessonPayload({
      ...base,
      nome: "  Mario   Rossi \n",
      corso: "Pole\tDance    Base",
    });
    expect(payload.nome).toBe("Mario Rossi");
    expect(payload.corso).toBe("Pole Dance Base");
    for (const value of Object.values(payload)) {
      expect(value).not.toMatch(/[\n\t]| {4}/);
    }
  });

  test("usa giorno e orario passati esplicitamente (callable di prova)", () => {
    const payload = buildDemoLessonPayload({
      ...base,
      giorno: "28 aprile 2026",
      orario: "10:00",
    });
    expect(payload.giorno).toBe("28 aprile 2026");
    expect(payload.orario).toBe("10:00");
  });

  test("ricade sulla data della lezione se giorno e orario sono vuoti", () => {
    const payload = buildDemoLessonPayload({ ...base, giorno: " ", orario: "" });
    expect(payload.giorno).toBe("15 ottobre 2026");
    expect(payload.orario).toBe("18:00");
  });

  test("rifiuta un campo vuoto invece di mandarlo a Make", () => {
    expect(() => buildDemoLessonPayload({ ...base, nome: "" })).toThrow(/nome/);
    expect(() => buildDemoLessonPayload({ ...base, corso: "   " })).toThrow(/corso/);
  });
});
