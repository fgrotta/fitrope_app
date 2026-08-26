import { decideRefund } from "../enrollment/refund";

describe("decideRefund — finestre e rimborso", () => {
  test("ENTRIES oltre la finestra (>8h): ripristina ingresso, nessuna conferma", () => {
    const r = decideRefund({
      creditMode: "ENTRIES_SUB",
      subscriptionId: "s1",
      minutesToStart: 9 * 60,
      confirmedNoRefund: false,
    });
    expect(r.requiresConfirmation).toBe(false);
    expect(r.restoreSubscriptionEntry).toBe(true);
    expect(r.subscriptionId).toBe("s1");
    expect(r.entryLost).toBe(false);
  });

  test("ENTRIES entro 8h senza conferma → requiresConfirmation", () => {
    const r = decideRefund({
      creditMode: "ENTRIES_SUB",
      subscriptionId: "s1",
      minutesToStart: 2 * 60,
      confirmedNoRefund: false,
    });
    expect(r.requiresConfirmation).toBe(true);
    expect(r.restoreSubscriptionEntry).toBe(false);
  });

  test("ENTRIES entro 8h con conferma → ingresso perso, nessun ripristino", () => {
    const r = decideRefund({
      creditMode: "ENTRIES_SUB",
      subscriptionId: "s1",
      minutesToStart: 2 * 60,
      confirmedNoRefund: true,
    });
    expect(r.requiresConfirmation).toBe(false);
    expect(r.restoreSubscriptionEntry).toBe(false);
    expect(r.entryLost).toBe(true);
  });

  test("ENTRIES_LEGACY oltre finestra ripristina entrateDisponibili", () => {
    const r = decideRefund({
      creditMode: "ENTRIES_LEGACY",
      minutesToStart: 10 * 60,
      confirmedNoRefund: false,
    });
    expect(r.restoreLegacyEntry).toBe(true);
    expect(r.trackCancelled).toBe(false);
  });

  test("FREQUENCY oltre 4h: traccia disiscrizione non persa", () => {
    const r = decideRefund({
      creditMode: "FREQUENCY_SUB",
      minutesToStart: 5 * 60,
      confirmedNoRefund: false,
    });
    expect(r.requiresConfirmation).toBe(false);
    expect(r.trackCancelled).toBe(true);
    expect(r.entryLost).toBe(false);
    expect(r.restoreSubscriptionEntry).toBe(false);
    expect(r.restoreLegacyEntry).toBe(false);
  });

  test("FREQUENCY entro 4h senza conferma → requiresConfirmation", () => {
    const r = decideRefund({
      creditMode: "FREQUENCY_LEGACY",
      minutesToStart: 1 * 60,
      confirmedNoRefund: false,
    });
    expect(r.requiresConfirmation).toBe(true);
  });

  test("FREQUENCY entro 4h con conferma → ingresso settimanale perso", () => {
    const r = decideRefund({
      creditMode: "FREQUENCY_LEGACY",
      minutesToStart: 1 * 60,
      confirmedNoRefund: true,
    });
    expect(r.trackCancelled).toBe(true);
    expect(r.entryLost).toBe(true);
  });

  test("NONE: nessuna finestra, nessuna conferma, nessun effetto", () => {
    const r = decideRefund({
      creditMode: "NONE",
      minutesToStart: 0,
      confirmedNoRefund: false,
    });
    expect(r.requiresConfirmation).toBe(false);
    expect(r.restoreLegacyEntry).toBe(false);
    expect(r.restoreSubscriptionEntry).toBe(false);
    expect(r.trackCancelled).toBe(false);
  });

  test("limite esatto della finestra è incluso (entro)", () => {
    const r = decideRefund({
      creditMode: "ENTRIES_SUB",
      minutesToStart: 8 * 60,
      confirmedNoRefund: true,
    });
    expect(r.entryLost).toBe(true); // 8h esatte = entro finestra
  });
});

describe("decideRefund — cosa si perde (lostKind), base del recupero in giornata", () => {
  test("ENTRIES con ingresso scalato: si perde un INGRESSO, e va tracciato", () => {
    const r = decideRefund({
      creditMode: "ENTRIES_SUB",
      subscriptionId: "s1",
      minutesToStart: 2 * 60,
      confirmedNoRefund: true,
      consumedEntry: true,
    });
    expect(r.entryLost).toBe(true);
    expect(r.lostKind).toBe("ENTRY");
    // Serve la voce di storico: è ciò che rende l'ingresso recuperabile in giornata.
    expect(r.trackCancelled).toBe(true);
  });

  test("FREQUENCY senza consumo: si perde uno SLOT settimanale", () => {
    const r = decideRefund({
      creditMode: "FREQUENCY_SUB",
      minutesToStart: 2 * 60,
      confirmedNoRefund: true,
      consumedEntry: false,
    });
    expect(r.entryLost).toBe(true);
    expect(r.lostKind).toBe("WEEKLY_SLOT");
    expect(r.trackCancelled).toBe(true);
  });

  test("misto legacy→FREQUENCY: la penalità segue la fonte consumata (ENTRY, non slot)", () => {
    // Prenotazione fatta con un ingresso legacy, utente ora su piano a frequenza:
    // se la registrassimo come WEEKLY_SLOT peserebbe ANCHE sul limite settimanale.
    const r = decideRefund({
      creditMode: "FREQUENCY_SUB",
      minutesToStart: 2 * 60,
      confirmedNoRefund: true,
      consumedEntry: true,
    });
    expect(r.lostKind).toBe("ENTRY");
  });

  test("niente consumato (force-subscribe a credito zero): nessuna perdita da registrare", () => {
    const r = decideRefund({
      creditMode: "ENTRIES_SUB",
      minutesToStart: 2 * 60,
      confirmedNoRefund: true,
      consumedEntry: false,
    });
    expect(r.entryLost).toBe(false);
    expect(r.lostKind).toBeNull();
    expect(r.trackCancelled).toBe(false);
    expect(r.restoreSubscriptionEntry).toBe(false);
  });

  test("registro assente (prenotazione pre-registro): si deduce dal creditMode", () => {
    const entries = decideRefund({
      creditMode: "ENTRIES_LEGACY",
      minutesToStart: 2 * 60,
      confirmedNoRefund: true,
      consumedEntry: null,
    });
    expect(entries.lostKind).toBe("ENTRY");

    const freq = decideRefund({
      creditMode: "FREQUENCY_LEGACY",
      minutesToStart: 2 * 60,
      confirmedNoRefund: true,
    });
    expect(freq.lostKind).toBe("WEEKLY_SLOT");
  });

  test("fuori finestra non si perde nulla, ma la frequenza traccia comunque lo storico", () => {
    const freq = decideRefund({
      creditMode: "FREQUENCY_SUB",
      minutesToStart: 10 * 60,
      confirmedNoRefund: true,
    });
    expect(freq.entryLost).toBe(false);
    expect(freq.lostKind).toBeNull();
    expect(freq.trackCancelled).toBe(true);

    const entries = decideRefund({
      creditMode: "ENTRIES_SUB",
      minutesToStart: 10 * 60,
      confirmedNoRefund: true,
      consumedEntry: true,
    });
    expect(entries.lostKind).toBeNull();
    expect(entries.trackCancelled).toBe(false);
  });
});
