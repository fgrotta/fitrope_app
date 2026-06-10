import {
  weekBoundsMillis,
  countWeeklyEntries,
  coveringSubsByType,
  validAtDate,
  evaluateSubscribe,
  SubscribeInput,
  EnrolledCourse,
  CancelledRecord,
} from "../enrollment/eligibility";
import { UserSubscriptionRecord } from "../enrollment/subscription";

// Mer 10 giu 2026, 10:00 UTC. Settimana: lun 8 → dom 14 giu.
const COURSE_AT = Date.UTC(2026, 5, 10, 10);
const WEEK_MON = Date.UTC(2026, 5, 8);
const WEEK_SUN_END = Date.UTC(2026, 5, 15) - 1;
// "Adesso": il giorno prima del corso.
const NOW = Date.UTC(2026, 5, 9, 12);

function sub(over: Partial<UserSubscriptionRecord> = {}): UserSubscriptionRecord {
  return {
    id: "s1",
    planKey: "open_2x_1m",
    family: "OPEN",
    billingMode: "FREQUENCY",
    courseTypeTags: ["Open"],
    weeklyFrequency: 2,
    remainingEntries: null,
    startDateMillis: Date.UTC(2026, 0, 1),
    endDateMillis: Date.UTC(2026, 11, 31),
    ...over,
  };
}

function input(over: Partial<SubscribeInput> = {}): SubscribeInput {
  return {
    force: false,
    alreadySubscribed: false,
    courseFull: false,
    userTags: ["Open"],
    courseTags: ["Open"],
    coursePrimaryTag: "Open",
    courseStartMillis: COURSE_AT,
    nowMillis: NOW,
    activeSubscriptions: [],
    tipologia: null,
    entrateDisponibili: null,
    entrateSettimanali: null,
    fineIscrizioneMillis: null,
    weeklyUsed: 0,
    ...over,
  };
}

describe("weekBoundsMillis", () => {
  test("settimana lun-dom (UTC) del corso", () => {
    const b = weekBoundsMillis(COURSE_AT);
    expect(b.start).toBe(WEEK_MON);
    expect(b.end).toBe(WEEK_SUN_END);
  });

  test("lunedì 00:00 e domenica 23:59 cadono nella stessa settimana", () => {
    expect(weekBoundsMillis(WEEK_MON).start).toBe(WEEK_MON);
    expect(weekBoundsMillis(WEEK_SUN_END).start).toBe(WEEK_MON);
  });
});

describe("countWeeklyEntries", () => {
  const enrolled: EnrolledCourse[] = [
    { uid: "c-open-in-week", startMillis: Date.UTC(2026, 5, 9, 18), primaryTag: "Open" },
    { uid: "c-hyrox-in-week", startMillis: Date.UTC(2026, 5, 11, 18), primaryTag: "Hyrox" },
    { uid: "c-open-other-week", startMillis: Date.UTC(2026, 5, 16, 18), primaryTag: "Open" },
  ];

  test("scope per tipologia: conta solo i corsi della tipologia nella settimana", () => {
    expect(countWeeklyEntries(COURSE_AT, enrolled, [], new Set(["Open"]))).toBe(1);
    expect(countWeeklyEntries(COURSE_AT, enrolled, [], new Set(["Hyrox"]))).toBe(1);
  });

  test("scope globale (legacy): conta tutte le tipologie nella settimana", () => {
    expect(countWeeklyEntries(COURSE_AT, enrolled, [], null)).toBe(2);
  });

  test("disiscrizioni perse contano; non perse no; fuori settimana no", () => {
    const cancelled: CancelledRecord[] = [
      { entryLost: true, courseStartMillis: Date.UTC(2026, 5, 8, 9), primaryTag: "Open" },
      { entryLost: false, courseStartMillis: Date.UTC(2026, 5, 8, 9), primaryTag: "Open" },
      { entryLost: true, courseStartMillis: Date.UTC(2026, 5, 1, 9), primaryTag: "Open" },
    ];
    expect(countWeeklyEntries(COURSE_AT, [], cancelled, new Set(["Open"]))).toBe(1);
    expect(countWeeklyEntries(COURSE_AT, [], cancelled, null)).toBe(1);
  });

  test("disiscrizione persa di corso non risolvibile conta nello scope tipologia", () => {
    const cancelled: CancelledRecord[] = [
      { entryLost: true, courseStartMillis: Date.UTC(2026, 5, 9, 9), primaryTag: null },
    ];
    expect(countWeeklyEntries(COURSE_AT, [], cancelled, new Set(["Open"]))).toBe(1);
  });

  test("disiscrizione persa di ALTRA tipologia non conta nello scope", () => {
    const cancelled: CancelledRecord[] = [
      { entryLost: true, courseStartMillis: Date.UTC(2026, 5, 9, 9), primaryTag: "Hyrox" },
    ];
    expect(countWeeklyEntries(COURSE_AT, [], cancelled, new Set(["Open"]))).toBe(0);
  });
});

describe("coveringSubsByType / validAtDate", () => {
  test("copertura per tag tipologia, validità per finestra date", () => {
    const s1 = sub({ id: "a", courseTypeTags: ["Open"] });
    const s2 = sub({ id: "b", courseTypeTags: ["Hyrox"] });
    const s3 = sub({
      id: "c",
      courseTypeTags: ["Open"],
      endDateMillis: Date.UTC(2026, 4, 1), // scaduto prima del corso
    });
    const covering = coveringSubsByType([s1, s2, s3], "Open");
    expect(covering.map((s) => s.id)).toEqual(["a", "c"]);
    expect(validAtDate(covering, COURSE_AT).map((s) => s.id)).toEqual(["a"]);
  });

  test("corso prima dello startDate dell'abbonamento non è coperto", () => {
    const s = sub({ startDateMillis: Date.UTC(2026, 6, 1) }); // inizia a luglio
    expect(validAtDate([s], COURSE_AT)).toHaveLength(0);
  });
});

describe("evaluateSubscribe — legacy (snapshot vuoto)", () => {
  test("già iscritto → ALREADY_SUBSCRIBED (precede tutto)", () => {
    const d = evaluateSubscribe(input({ alreadySubscribed: true, courseFull: true }));
    expect(d.allowed).toBe(false);
    expect(d.reason).toBe("ALREADY_SUBSCRIBED");
  });

  test("senza accesso tag → NO_ACCESS", () => {
    const d = evaluateSubscribe(
      input({ userTags: ["Open"], courseTags: ["Hyrox"], coursePrimaryTag: "Hyrox" })
    );
    expect(d.reason).toBe("NO_ACCESS");
  });

  test("PACCHETTO_ENTRATE con crediti → OK, consuma LEGACY_ENTRY", () => {
    const d = evaluateSubscribe(
      input({ tipologia: "PACCHETTO_ENTRATE", entrateDisponibili: 3 })
    );
    expect(d.allowed).toBe(true);
    expect(d.consume.kind).toBe("LEGACY_ENTRY");
  });

  test("PACCHETTO_ENTRATE senza crediti → NO_ENTRIES", () => {
    const d = evaluateSubscribe(
      input({ tipologia: "PACCHETTO_ENTRATE", entrateDisponibili: 0 })
    );
    expect(d.reason).toBe("NO_ENTRIES");
  });

  test("ABBONAMENTO_PROVA usa il path entrate", () => {
    const ok = evaluateSubscribe(
      input({ tipologia: "ABBONAMENTO_PROVA", entrateDisponibili: 1 })
    );
    expect(ok.allowed).toBe(true);
    expect(ok.consume.kind).toBe("LEGACY_ENTRY");
    const ko = evaluateSubscribe(
      input({ tipologia: "ABBONAMENTO_PROVA", entrateDisponibili: 0 })
    );
    expect(ko.reason).toBe("NO_ENTRIES");
  });

  test("temporale sotto il limite settimanale → OK senza consumo", () => {
    const d = evaluateSubscribe(
      input({ tipologia: "ABBONAMENTO_MENSILE", entrateSettimanali: 3, weeklyUsed: 2 })
    );
    expect(d.allowed).toBe(true);
    expect(d.consume.kind).toBe("NONE");
  });

  test("temporale al limite settimanale → WEEKLY_LIMIT", () => {
    const d = evaluateSubscribe(
      input({ tipologia: "ABBONAMENTO_ANNUALE", entrateSettimanali: 3, weeklyUsed: 3 })
    );
    expect(d.reason).toBe("WEEKLY_LIMIT");
  });

  test("temporale senza limite (entrateSettimanali null) → OK", () => {
    const d = evaluateSubscribe(
      input({ tipologia: "ABBONAMENTO_TRIMESTRALE", entrateSettimanali: null, weeklyUsed: 99 })
    );
    expect(d.allowed).toBe(true);
  });

  test("fineIscrizione prima del corso → EXPIRED", () => {
    const d = evaluateSubscribe(
      input({
        tipologia: "ABBONAMENTO_MENSILE",
        entrateSettimanali: 3,
        fineIscrizioneMillis: COURSE_AT - 1000,
      })
    );
    expect(d.reason).toBe("EXPIRED");
  });

  test("senza tipologia → NOT_ELIGIBLE", () => {
    const d = evaluateSubscribe(input({ tipologia: null }));
    expect(d.reason).toBe("NOT_ELIGIBLE");
  });

  test("corso pieno (idoneo) → FULL; i limiti precedono FULL", () => {
    const full = evaluateSubscribe(
      input({ tipologia: "PACCHETTO_ENTRATE", entrateDisponibili: 1, courseFull: true })
    );
    expect(full.reason).toBe("FULL");
    const noEntries = evaluateSubscribe(
      input({ tipologia: "PACCHETTO_ENTRATE", entrateDisponibili: 0, courseFull: true })
    );
    expect(noEntries.reason).toBe("NO_ENTRIES");
  });
});

describe("evaluateSubscribe — multi-abbonamento", () => {
  test("ENTRIES con ingressi → OK, consuma SUBSCRIPTION_ENTRY dell'abbonamento giusto", () => {
    const d = evaluateSubscribe(
      input({
        userTags: [],
        courseTags: ["Hyrox"],
        coursePrimaryTag: "Hyrox",
        activeSubscriptions: [
          sub({ id: "open-sub" }),
          sub({
            id: "hyrox-sub",
            family: "HYROX",
            billingMode: "ENTRIES",
            courseTypeTags: ["Hyrox"],
            weeklyFrequency: null,
            remainingEntries: 5,
          }),
        ],
      })
    );
    expect(d.allowed).toBe(true);
    expect(d.consume).toEqual({ kind: "SUBSCRIPTION_ENTRY", subscriptionId: "hyrox-sub" });
  });

  test("ENTRIES a zero → NO_ENTRIES", () => {
    const d = evaluateSubscribe(
      input({
        courseTags: ["Hyrox"],
        coursePrimaryTag: "Hyrox",
        userTags: ["Hyrox"],
        activeSubscriptions: [
          sub({
            billingMode: "ENTRIES",
            family: "HYROX",
            courseTypeTags: ["Hyrox"],
            weeklyFrequency: null,
            remainingEntries: 0,
          }),
        ],
      })
    );
    expect(d.reason).toBe("NO_ENTRIES");
  });

  test("FREQUENCY sotto il limite → OK; al limite → WEEKLY_LIMIT", () => {
    const subs = [sub({ weeklyFrequency: 2 })];
    expect(
      evaluateSubscribe(input({ activeSubscriptions: subs, weeklyUsed: 1 })).allowed
    ).toBe(true);
    expect(
      evaluateSubscribe(input({ activeSubscriptions: subs, weeklyUsed: 2 })).reason
    ).toBe("WEEKLY_LIMIT");
  });

  test("FREQUENCY illimitato (null) → sempre OK, consumo NONE", () => {
    const d = evaluateSubscribe(
      input({
        activeSubscriptions: [sub({ weeklyFrequency: null })],
        weeklyUsed: 99,
      })
    );
    expect(d.allowed).toBe(true);
    expect(d.consume.kind).toBe("NONE");
  });

  test("copre la tipologia ma scaduto alla data del corso → EXPIRED", () => {
    const d = evaluateSubscribe(
      input({
        // endDate tra "adesso" e la data del corso: voce viva ma non valida al corso.
        activeSubscriptions: [sub({ endDateMillis: COURSE_AT - 1 })],
      })
    );
    expect(d.reason).toBe("EXPIRED");
  });

  test("snapshot con SOLE voci già scadute → fallback legacy (crediti pagati riutilizzabili)", () => {
    const d = evaluateSubscribe(
      input({
        tipologia: "PACCHETTO_ENTRATE",
        entrateDisponibili: 3,
        // Scaduta PRIMA di adesso: non deve selezionare il modello multi-abbonamento.
        activeSubscriptions: [sub({ endDateMillis: NOW - 1000 })],
      })
    );
    expect(d.allowed).toBe(true);
    expect(d.consume.kind).toBe("LEGACY_ENTRY");
  });

  test("voce scaduta di ALTRA famiglia non blocca il modello (viene scartata)", () => {
    const d = evaluateSubscribe(
      input({
        tipologia: "ABBONAMENTO_MENSILE",
        entrateSettimanali: 3,
        weeklyUsed: 0,
        activeSubscriptions: [
          sub({
            family: "HYROX",
            billingMode: "ENTRIES",
            courseTypeTags: ["Hyrox"],
            weeklyFrequency: null,
            remainingEntries: 0,
            endDateMillis: NOW - 1000,
          }),
        ],
      })
    );
    expect(d.allowed).toBe(true); // legacy temporale sotto il limite
  });

  test("accesso via copertura abbonamento anche senza tag legacy", () => {
    const d = evaluateSubscribe(
      input({
        userTags: [], // nessun tag legacy
        courseTags: ["Hyrox"],
        coursePrimaryTag: "Hyrox",
        activeSubscriptions: [
          sub({
            family: "HYROX",
            billingMode: "ENTRIES",
            courseTypeTags: ["Hyrox"],
            weeklyFrequency: null,
            remainingEntries: 3,
          }),
        ],
      })
    );
    expect(d.allowed).toBe(true);
  });

  test("tag legacy ok ma nessun abbonamento copre tipologia CON famiglia → NOT_ELIGIBLE", () => {
    const d = evaluateSubscribe(
      input({
        userTags: ["Hyrox"],
        courseTags: ["Hyrox"],
        coursePrimaryTag: "Hyrox",
        activeSubscriptions: [sub()], // copre solo Open
      })
    );
    expect(d.reason).toBe("NOT_ELIGIBLE");
  });

  test("tipologia SENZA famiglia (Hey Mamma) accessibile via tag → OK senza limiti", () => {
    const d = evaluateSubscribe(
      input({
        userTags: ["Hey Mamma"],
        courseTags: ["Hey Mamma"],
        coursePrimaryTag: "Hey Mamma",
        activeSubscriptions: [sub()], // ha un abbonamento Open, non copre Hey Mamma
      })
    );
    expect(d.allowed).toBe(true);
    expect(d.consume.kind).toBe("NONE");
  });

  test("né tag né copertura → NO_ACCESS", () => {
    const d = evaluateSubscribe(
      input({
        userTags: ["Open"],
        courseTags: ["Hyrox"],
        coursePrimaryTag: "Hyrox",
        activeSubscriptions: [sub()],
      })
    );
    expect(d.reason).toBe("NO_ACCESS");
  });

  test("idoneo se ALMENO un abbonamento valido consente (ENTRIES esaurito + FREQUENCY ok)", () => {
    // Caso multi-abbonamento sulla stessa tipologia (non più creabile via vincolo
    // max-1-per-famiglia, ma lo snapshot può contenerlo: la regola resta 'OR').
    const d = evaluateSubscribe(
      input({
        activeSubscriptions: [
          sub({
            id: "entries-open",
            billingMode: "ENTRIES",
            weeklyFrequency: null,
            remainingEntries: 0,
          }),
          sub({ id: "freq-open", weeklyFrequency: 3 }),
        ],
        weeklyUsed: 1,
      })
    );
    expect(d.allowed).toBe(true);
    // L'idoneità viene dal FREQUENCY: il consumo NON deve puntare all'ENTRIES
    // esaurito (l'handler rifiuterebbe un'iscrizione consentita).
    expect(d.consume.kind).toBe("NONE");
  });

  test("misto ENTRIES con ingressi + FREQUENCY: consuma l'ENTRIES", () => {
    const d = evaluateSubscribe(
      input({
        activeSubscriptions: [
          sub({
            id: "entries-open",
            billingMode: "ENTRIES",
            weeklyFrequency: null,
            remainingEntries: 2,
          }),
          sub({ id: "freq-open", weeklyFrequency: 3 }),
        ],
        weeklyUsed: 0,
      })
    );
    expect(d.allowed).toBe(true);
    expect(d.consume).toEqual({ kind: "SUBSCRIPTION_ENTRY", subscriptionId: "entries-open" });
  });
});

describe("evaluateSubscribe — force (admin)", () => {
  test("force bypassa pieno/accesso/limiti ma NON già-iscritto", () => {
    const full = evaluateSubscribe(
      input({
        force: true,
        courseFull: true,
        userTags: [],
        courseTags: ["Hyrox"],
        coursePrimaryTag: "Hyrox",
        tipologia: null,
      })
    );
    expect(full.allowed).toBe(true);

    const already = evaluateSubscribe(input({ force: true, alreadySubscribed: true }));
    expect(already.allowed).toBe(false);
  });

  test("force consuma comunque il credito (LEGACY_ENTRY)", () => {
    const d = evaluateSubscribe(
      input({ force: true, tipologia: "PACCHETTO_ENTRATE", entrateDisponibili: 2 })
    );
    expect(d.consume.kind).toBe("LEGACY_ENTRY");
  });

  test("force su abbonamento ENTRIES valido consuma SUBSCRIPTION_ENTRY", () => {
    const d = evaluateSubscribe(
      input({
        force: true,
        courseFull: true,
        activeSubscriptions: [
          sub({
            id: "e1",
            billingMode: "ENTRIES",
            weeklyFrequency: null,
            remainingEntries: 4,
          }),
        ],
      })
    );
    expect(d.consume).toEqual({ kind: "SUBSCRIPTION_ENTRY", subscriptionId: "e1" });
  });
});
