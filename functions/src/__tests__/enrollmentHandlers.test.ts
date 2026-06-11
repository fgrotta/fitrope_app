import { Timestamp } from "firebase-admin/firestore";
import {
  subscribeToCourseHandler,
  unsubscribeFromCourseHandler,
  joinWaitlistHandler,
  leaveWaitlistHandler,
  pruneConsumption,
  CONSUMPTION_RETENTION_MILLIS,
  ConsumptionRecord,
} from "../enrollment/enrollment";
import { makeDb, FakeStore, Data } from "./helpers/fakeDb";


// Mar 9 giu 2026, 12:00 UTC — "adesso" per tutti i test.
const NOW = Date.UTC(2026, 5, 9, 12);
// Corso a ~22h (fuori da entrambe le finestre 4h/8h). Mer 10 giu, 10:00 UTC.
const FAR = Date.UTC(2026, 5, 10, 10);
// Corso a 6h (entro 8h, fuori 4h) e corso a 2h (entro entrambe).
const MID = Date.UTC(2026, 5, 9, 18);
const SOON = Date.UTC(2026, 5, 9, 14);



function course(over: Data = {}): Data {
  return {
    uid: "c1",
    name: "Corso Open",
    startDate: Timestamp.fromMillis(FAR),
    endDate: Timestamp.fromMillis(FAR + 3600000),
    capacity: 10,
    subscribed: 5,
    tags: ["Open"],
    waitlist: [],
    ...over,
  };
}

function packUser(over: Data = {}): Data {
  return {
    uid: "u1",
    role: "User",
    courses: [],
    tipologiaIscrizione: "PACCHETTO_ENTRATE",
    entrateDisponibili: 5,
    tipologiaCorsoTags: ["Open"],
    ...over,
  };
}

function tempUser(over: Data = {}): Data {
  return {
    uid: "u1",
    role: "User",
    courses: [],
    tipologiaIscrizione: "ABBONAMENTO_MENSILE",
    entrateSettimanali: 3,
    entrateDisponibili: 2, // NON deve essere toccato dal modello temporale
    fineIscrizione: Timestamp.fromMillis(Date.UTC(2026, 11, 31)),
    tipologiaCorsoTags: ["Open"],
    ...over,
  };
}

function hyroxSubDoc(remaining: number): Data {
  return {
    userId: "u1",
    planKey: "hyrox_10i_3m",
    family: "HYROX",
    billingMode: "ENTRIES",
    courseTypeTags: ["Hyrox"],
    weeklyFrequency: null,
    remainingEntries: remaining,
    startDate: Timestamp.fromMillis(Date.UTC(2026, 0, 1)),
    endDate: Timestamp.fromMillis(Date.UTC(2026, 11, 31)),
  };
}

function openFreqSubDoc(weeklyFrequency: number | null): Data {
  return {
    userId: "u1",
    planKey: weeklyFrequency === null ? "open_unlim_3m" : "open_2x_3m",
    family: "OPEN",
    billingMode: "FREQUENCY",
    courseTypeTags: ["Open"],
    weeklyFrequency,
    remainingEntries: null,
    startDate: Timestamp.fromMillis(Date.UTC(2026, 0, 1)),
    endDate: Timestamp.fromMillis(Date.UTC(2026, 11, 31)),
  };
}

function snapshotEntry(id: string, doc: Data): Data {
  const { userId: _u, ...rest } = doc;
  return { id, ...rest };
}

function subUser(over: Data = {}): Data {
  return {
    uid: "u1",
    role: "User",
    courses: [],
    tipologiaCorsoTags: [],
    activeSubscriptions: [snapshotEntry("sub-hyrox", hyroxSubDoc(10))],
    ...over,
  };
}

const auth = (uid: string) => ({ auth: { uid } });

async function expectCode(p: Promise<unknown>, code: string) {
  await expect(p).rejects.toMatchObject({ code });
}

// ──────────────────────────────────────────────
//  subscribeToCourse
// ──────────────────────────────────────────────

describe("subscribeToCourseHandler", () => {
  test("non autenticato → unauthenticated", async () => {
    const db = makeDb({ users: {}, courses: {}, subs: {} });
    await expectCode(
      subscribeToCourseHandler({ auth: null, data: { courseId: "c1", userId: "u1" } }, db),
      "unauthenticated"
    );
  });

  test("argomenti mancanti → invalid-argument", async () => {
    const db = makeDb({ users: { u1: packUser() }, courses: {}, subs: {} });
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "c1" } }, db),
      "invalid-argument"
    );
  });

  test("Admin/Trainer non possono iscriversi (self) → permission-denied", async () => {
    for (const role of ["Admin", "Trainer"]) {
      const db = makeDb({
        users: { boss: { uid: "boss", role } },
        courses: { c1: course() },
        subs: {},
      });
      await expectCode(
        subscribeToCourseHandler(
          { ...auth("boss"), data: { courseId: "c1", userId: "boss" } },
          db
        ),
        "permission-denied"
      );
    }
  });

  test("utente normale non può iscrivere un altro → permission-denied", async () => {
    const db = makeDb({
      users: { u1: packUser(), u2: packUser({ uid: "u2" }) },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u2" } }, db),
      "permission-denied"
    );
  });

  test("corso inesistente → not-found", async () => {
    const db = makeDb({ users: { u1: packUser() }, courses: {}, subs: {} });
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "nope", userId: "u1" } }, db),
      "not-found"
    );
  });

  test("PACCHETTO_ENTRATE: iscrive, decrementa entrate, incrementa subscribed", async () => {
    const store: FakeStore = {
      users: { u1: packUser() },
      courses: { c1: course() },
      subs: {},
    };
    const db = makeDb(store);
    const res = await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(res.ok).toBe(true);
    expect(store.courses.c1.subscribed).toBe(6);
    expect(store.users.u1.courses).toEqual(["c1"]);
    expect(store.users.u1.entrateDisponibili).toBe(4);
  });

  test("PACCHETTO_ENTRATE senza crediti → failed-precondition (Ingressi esauriti)", async () => {
    const db = makeDb({
      users: { u1: packUser({ entrateDisponibili: 0 }) },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db, {}, NOW),
      "failed-precondition"
    );
  });

  test("temporale: iscrive SENZA toccare entrateDisponibili (fix del bug legacy)", async () => {
    const store: FakeStore = {
      users: { u1: tempUser() },
      courses: { c1: course() },
      subs: {},
    };
    const db = makeDb(store);
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.users.u1.courses).toEqual(["c1"]);
    expect(store.users.u1.entrateDisponibili).toBe(2); // invariato
  });

  test("temporale al limite settimanale → failed-precondition", async () => {
    // Due corsi Open già frequentati nella stessa settimana del corso target.
    const store: FakeStore = {
      users: { u1: tempUser({ entrateSettimanali: 2, courses: ["c-mon", "c-tue"] }) },
      courses: {
        c1: course(),
        "c-mon": course({ uid: "c-mon", startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 8, 10)) }),
        "c-tue": course({ uid: "c-tue", startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 9, 8)) }),
      },
      subs: {},
    };
    const db = makeDb(store);
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db, {}, NOW),
      "failed-precondition"
    );
  });

  test("temporale sotto il limite settimanale → ok", async () => {
    const store: FakeStore = {
      users: { u1: tempUser({ entrateSettimanali: 3, courses: ["c-mon"] }) },
      courses: {
        c1: course(),
        "c-mon": course({ uid: "c-mon", startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 8, 10)) }),
      },
      subs: {},
    };
    const db = makeDb(store);
    const res = await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(res.ok).toBe(true);
  });

  test("fineIscrizione prima del corso → failed-precondition (scaduto)", async () => {
    const db = makeDb({
      users: { u1: tempUser({ fineIscrizione: Timestamp.fromMillis(FAR - 1000) }) },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db, {}, NOW),
      "failed-precondition"
    );
  });

  test("corso pieno → failed-precondition; force admin su altro utente → ok oltre capienza", async () => {
    const fullStore = (): FakeStore => ({
      users: { u1: packUser(), boss: { uid: "boss", role: "Admin" } },
      courses: { c1: course({ subscribed: 10 }) },
      subs: {},
    });

    const s1 = fullStore();
    await expectCode(
      subscribeToCourseHandler(
        { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
        makeDb(s1),
        {},
        NOW
      ),
      "failed-precondition"
    );

    const s2 = fullStore();
    const res = await subscribeToCourseHandler(
      { ...auth("boss"), data: { courseId: "c1", userId: "u1", force: true } },
      makeDb(s2),
      {},
      NOW
    );
    expect(res.ok).toBe(true);
    expect(s2.courses.c1.subscribed).toBe(11);
    expect(s2.users.u1.courses).toEqual(["c1"]);
  });

  test("force richiesto da utente NON privilegiato viene ignorato", async () => {
    const db = makeDb({
      users: { u1: packUser() },
      courses: { c1: course({ subscribed: 10 }) },
      subs: {},
    });
    await expectCode(
      subscribeToCourseHandler(
        { ...auth("u1"), data: { courseId: "c1", userId: "u1", force: true } },
        db,
        {},
        NOW
      ),
      "failed-precondition"
    );
  });

  test("già iscritto → already-exists", async () => {
    const db = makeDb({
      users: { u1: packUser({ courses: ["c1"] }) },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db, {}, NOW),
      "already-exists"
    );
  });

  test("multi-abbonamento ENTRIES: decrementa il doc subscription e aggiorna lo snapshot", async () => {
    const store: FakeStore = {
      users: { u1: subUser() },
      courses: { ch: course({ uid: "ch", tags: ["Hyrox"] }) },
      subs: { "sub-hyrox": hyroxSubDoc(10) },
    };
    const db = makeDb(store);
    const res = await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "ch", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(res.ok).toBe(true);
    expect(store.subs["sub-hyrox"].remainingEntries).toBe(9);
    const snap = store.users.u1.activeSubscriptions as Data[];
    expect(snap).toHaveLength(1);
    expect(snap[0].remainingEntries).toBe(9);
    expect(snap[0].id).toBe("sub-hyrox");
    // Il registro consumi DEVE puntare all'abbonamento decrementato: senza
    // subscriptionId il rimborso futuro non ripristinerebbe nulla.
    expect(store.users.u1.enrollmentConsumption).toEqual({
      ch: { kind: "SUBSCRIPTION_ENTRY", subscriptionId: "sub-hyrox", atMillis: NOW, courseStartMillis: FAR },
    });
  });

  test("round-trip subscribe→unsubscribe su abbonamento ENTRIES: l'ingresso torna (10→9→10)", async () => {
    const store: FakeStore = {
      users: { u1: subUser() },
      courses: { ch: course({ uid: "ch", tags: ["Hyrox"] }) },
      subs: { "sub-hyrox": hyroxSubDoc(10) },
    };
    const db = makeDb(store);
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "ch", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.subs["sub-hyrox"].remainingEntries).toBe(9);

    // Disiscrizione fuori finestra sullo STESSO store: il registro scritto dal
    // handler (non pre-seedato) guida il ripristino.
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "ch", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.subs["sub-hyrox"].remainingEntries).toBe(10);
    const snap = store.users.u1.activeSubscriptions as Data[];
    expect(snap[0].remainingEntries).toBe(10);
    expect(store.users.u1.enrollmentConsumption).toEqual({});
    expect(store.users.u1.courses).toEqual([]);
    expect(store.courses.ch.subscribed).toBe(5); // 5→6→5
  });

  test("misto ENTRIES esaurito + FREQUENCY idoneo (stessa tipologia): iscrive SENZA decrementare", async () => {
    // Stato non creabile via assignSubscription (max 1 per famiglia) ma
    // possibile in snapshot storici/scritture dirette pre-PR6: la regola OR
    // consente, il consumo deve essere NONE (non l'ENTRIES a zero).
    const zeroEntries: Data = {
      ...openFreqSubDoc(2),
      planKey: "open_entries_test",
      billingMode: "ENTRIES",
      weeklyFrequency: null,
      remainingEntries: 0,
    };
    const store: FakeStore = {
      users: {
        u1: subUser({
          activeSubscriptions: [
            snapshotEntry("sub-open-entries", zeroEntries),
            snapshotEntry("sub-open-freq", openFreqSubDoc(2)),
          ],
        }),
      },
      courses: { c1: course() },
      subs: {
        "sub-open-entries": zeroEntries,
        "sub-open-freq": openFreqSubDoc(2),
      },
    };
    const db = makeDb(store);
    const res = await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(res.ok).toBe(true);
    expect(store.subs["sub-open-entries"].remainingEntries).toBe(0); // intatto
    expect(store.users.u1.enrollmentConsumption).toEqual({
      c1: { kind: "NONE", atMillis: NOW, courseStartMillis: FAR },
    });
  });

  test("multi-abbonamento ENTRIES a zero → failed-precondition", async () => {
    const db = makeDb({
      users: {
        u1: subUser({ activeSubscriptions: [snapshotEntry("sub-hyrox", hyroxSubDoc(0))] }),
      },
      courses: { ch: course({ uid: "ch", tags: ["Hyrox"] }) },
      subs: { "sub-hyrox": hyroxSubDoc(0) },
    });
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "ch", userId: "u1" } }, db, {}, NOW),
      "failed-precondition"
    );
  });

  test("race: snapshot dice 1 ingresso ma il doc è a 0 → failed-precondition", async () => {
    const db = makeDb({
      users: {
        u1: subUser({ activeSubscriptions: [snapshotEntry("sub-hyrox", hyroxSubDoc(1))] }),
      },
      courses: { ch: course({ uid: "ch", tags: ["Hyrox"] }) },
      subs: { "sub-hyrox": hyroxSubDoc(0) }, // fonte di verità già consumata
    });
    await expectCode(
      subscribeToCourseHandler({ ...auth("u1"), data: { courseId: "ch", userId: "u1" } }, db, {}, NOW),
      "failed-precondition"
    );
  });

  test("iscrizione rimuove l'utente dalla waitlist (corso e utente)", async () => {
    const store: FakeStore = {
      users: { u1: packUser({ waitlistCourses: ["c1", "altro"] }) },
      courses: { c1: course({ waitlist: ["u1", "u2"] }) },
      subs: {},
    };
    const db = makeDb(store);
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.courses.c1.waitlist).toEqual(["u2"]);
    expect(store.users.u1.waitlistCourses).toEqual(["altro"]);
  });

  test("utente ABBONAMENTO_PROVA: parte il promemoria prova", async () => {
    const calls: Array<[string, string]> = [];
    const store: FakeStore = {
      users: { u1: packUser({ tipologiaIscrizione: "ABBONAMENTO_PROVA", entrateDisponibili: 1 }) },
      courses: { c1: course() },
      subs: {},
    };
    const db = makeDb(store);
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      { notifyTrialReminder: async (u, c) => void calls.push([u, c]) },
      NOW
    );
    expect(calls).toEqual([["u1", "c1"]]);
    expect(store.users.u1.entrateDisponibili).toBe(0);
  });

  test("utente non PROVA: nessun promemoria", async () => {
    const calls: string[] = [];
    const db = makeDb({
      users: { u1: packUser() },
      courses: { c1: course() },
      subs: {},
    });
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      { notifyTrialReminder: async (u) => void calls.push(u) },
      NOW
    );
    expect(calls).toEqual([]);
  });

  test("PROVA convertito al multi-abbonamento: NESSUN promemoria prova", async () => {
    const calls: string[] = [];
    const store: FakeStore = {
      users: {
        u1: subUser({
          tipologiaIscrizione: "ABBONAMENTO_PROVA", // campo legacy stantio
          activeSubscriptions: [snapshotEntry("sub-open", openFreqSubDoc(2))],
        }),
      },
      courses: { c1: course() },
      subs: { "sub-open": openFreqSubDoc(2) },
    };
    const db = makeDb(store);
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      { notifyTrialReminder: async (u) => void calls.push(u) },
      NOW
    );
    expect(calls).toEqual([]);
    expect(store.users.u1.courses).toEqual(["c1"]);
  });

  test("corso già iniziato → failed-precondition; force admin lo consente", async () => {
    const mk = (): FakeStore => ({
      users: { u1: packUser(), boss: { uid: "boss", role: "Admin" } },
      courses: {
        "c-past": course({
          uid: "c-past",
          startDate: Timestamp.fromMillis(NOW - 3600000), // iniziato 1h fa
        }),
      },
      subs: {},
    });
    await expectCode(
      subscribeToCourseHandler(
        { ...auth("u1"), data: { courseId: "c-past", userId: "u1" } },
        makeDb(mk()),
        {},
        NOW
      ),
      "failed-precondition"
    );
    const store = mk();
    const res = await subscribeToCourseHandler(
      { ...auth("boss"), data: { courseId: "c-past", userId: "u1", force: true } },
      makeDb(store),
      {},
      NOW
    );
    expect(res.ok).toBe(true);
  });

  test("FREQUENCY multi-abbonamento: scope per tipologia (lo Hyrox in settimana non conta sul limite Open)", async () => {
    const store: FakeStore = {
      users: {
        u1: subUser({
          courses: ["c-open-w", "c-hyrox-w"],
          activeSubscriptions: [snapshotEntry("sub-open", openFreqSubDoc(2))],
        }),
      },
      courses: {
        c1: course(), // target Open, stessa settimana
        "c-open-w": course({
          uid: "c-open-w",
          startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 8, 10)),
        }),
        "c-hyrox-w": course({
          uid: "c-hyrox-w",
          tags: ["Hyrox"],
          startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 9, 8)),
        }),
      },
      subs: { "sub-open": openFreqSubDoc(2) },
    };
    const db = makeDb(store);
    // 1 solo corso Open usato (lo Hyrox non rientra nello scope) → sotto il limite 2x.
    const res = await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(res.ok).toBe(true);
  });

  test("FREQUENCY multi-abbonamento al limite settimanale → failed-precondition", async () => {
    const store: FakeStore = {
      users: {
        u1: subUser({
          courses: ["c-mon", "c-tue"],
          activeSubscriptions: [snapshotEntry("sub-open", openFreqSubDoc(2))],
        }),
      },
      courses: {
        c1: course(),
        "c-mon": course({
          uid: "c-mon",
          startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 8, 10)),
        }),
        "c-tue": course({
          uid: "c-tue",
          startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 9, 8)),
        }),
      },
      subs: { "sub-open": openFreqSubDoc(2) },
    };
    await expectCode(
      subscribeToCourseHandler(
        { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
        makeDb(store),
        {},
        NOW
      ),
      "failed-precondition"
    );
  });

  test("disiscrizione persa (entryLost) conta verso il limite settimanale", async () => {
    const store: FakeStore = {
      users: {
        u1: subUser({
          courses: ["c-mon"],
          cancelledEnrollments: [
            {
              courseId: "c-lost",
              cancelledAt: Timestamp.fromMillis(NOW - 86400000),
              entryLost: true,
              courseStartDate: Timestamp.fromMillis(Date.UTC(2026, 5, 9, 9)),
            },
          ],
          activeSubscriptions: [snapshotEntry("sub-open", openFreqSubDoc(2))],
        }),
      },
      courses: {
        c1: course(),
        "c-mon": course({
          uid: "c-mon",
          startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 8, 10)),
        }),
        "c-lost": course({
          uid: "c-lost",
          startDate: Timestamp.fromMillis(Date.UTC(2026, 5, 9, 9)),
        }),
      },
      subs: { "sub-open": openFreqSubDoc(2) },
    };
    // 1 corso attivo + 1 ingresso perso = 2 ≥ limite 2x → rifiuto.
    await expectCode(
      subscribeToCourseHandler(
        { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
        makeDb(store),
        {},
        NOW
      ),
      "failed-precondition"
    );
  });

  test("registra il consumo per prenotazione (enrollmentConsumption)", async () => {
    const store: FakeStore = {
      users: { u1: packUser() },
      courses: { c1: course() },
      subs: {},
    };
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      makeDb(store),
      {},
      NOW
    );
    expect(store.users.u1.enrollmentConsumption).toEqual({
      c1: { kind: "LEGACY_ENTRY", atMillis: NOW, courseStartMillis: FAR },
    });
  });

  test("force a 0 ingressi: nessun decremento e consumo registrato come NONE", async () => {
    const store: FakeStore = {
      users: {
        u1: packUser({ entrateDisponibili: 0 }),
        boss: { uid: "boss", role: "Admin" },
      },
      courses: { c1: course() },
      subs: {},
    };
    await subscribeToCourseHandler(
      { ...auth("boss"), data: { courseId: "c1", userId: "u1", force: true } },
      makeDb(store),
      {},
      NOW
    );
    expect(store.users.u1.entrateDisponibili).toBe(0);
    expect(store.users.u1.enrollmentConsumption).toEqual({
      c1: { kind: "NONE", atMillis: NOW, courseStartMillis: FAR },
    });
  });
});

// ──────────────────────────────────────────────
//  unsubscribeFromCourse
// ──────────────────────────────────────────────

describe("unsubscribeFromCourseHandler", () => {
  test("non iscritto → failed-precondition", async () => {
    const db = makeDb({
      users: { u1: packUser() },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      unsubscribeFromCourseHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db, {}, NOW),
      "failed-precondition"
    );
  });

  test("pacchetto, fuori finestra 8h: rimborsa il credito", async () => {
    const store: FakeStore = {
      users: { u1: packUser({ courses: ["c1"], entrateDisponibili: 4 }) },
      courses: { c1: course() }, // FAR = ~22h
      subs: {},
    };
    const db = makeDb(store);
    const res = await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(res.ok).toBe(true);
    expect(store.users.u1.entrateDisponibili).toBe(5);
    expect(store.users.u1.courses).toEqual([]);
    expect(store.courses.c1.subscribed).toBe(4);
    expect(store.users.u1.cancelledEnrollments).toBeUndefined(); // entrate: non tracciato
  });

  test("pacchetto, entro 8h senza conferma → failed-precondition (conferma richiesta)", async () => {
    const db = makeDb({
      users: { u1: packUser({ courses: ["c-mid"] }) },
      courses: { "c-mid": course({ uid: "c-mid", startDate: Timestamp.fromMillis(MID) }) },
      subs: {},
    });
    await expectCode(
      unsubscribeFromCourseHandler(
        { ...auth("u1"), data: { courseId: "c-mid", userId: "u1" } },
        db,
        {},
        NOW
      ),
      "failed-precondition"
    );
  });

  test("pacchetto, entro 8h con conferma → credito perso", async () => {
    const store: FakeStore = {
      users: { u1: packUser({ courses: ["c-mid"], entrateDisponibili: 4 }) },
      courses: { "c-mid": course({ uid: "c-mid", startDate: Timestamp.fromMillis(MID) }) },
      subs: {},
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "c-mid", userId: "u1", confirmedNoRefund: true } },
      db,
      {},
      NOW
    );
    expect(store.users.u1.entrateDisponibili).toBe(4); // NON rimborsato
    expect(store.users.u1.courses).toEqual([]);
  });

  test("temporale, fuori finestra 4h: traccia disiscrizione con entryLost=false", async () => {
    const store: FakeStore = {
      users: { u1: tempUser({ courses: ["c-mid"] }) },
      courses: { "c-mid": course({ uid: "c-mid", startDate: Timestamp.fromMillis(MID) }) }, // 6h
      subs: {},
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "c-mid", userId: "u1" } },
      db,
      {},
      NOW
    );
    const cancelled = store.users.u1.cancelledEnrollments as Data[];
    expect(cancelled).toHaveLength(1);
    expect(cancelled[0].entryLost).toBe(false);
    expect(cancelled[0].courseId).toBe("c-mid");
    expect(store.users.u1.entrateDisponibili).toBe(2); // mai toccato
  });

  test("temporale, entro 4h senza conferma → failed-precondition", async () => {
    const db = makeDb({
      users: { u1: tempUser({ courses: ["c-soon"] }) },
      courses: { "c-soon": course({ uid: "c-soon", startDate: Timestamp.fromMillis(SOON) }) },
      subs: {},
    });
    await expectCode(
      unsubscribeFromCourseHandler(
        { ...auth("u1"), data: { courseId: "c-soon", userId: "u1" } },
        db,
        {},
        NOW
      ),
      "failed-precondition"
    );
  });

  test("temporale, entro 4h con conferma → entryLost=true", async () => {
    const store: FakeStore = {
      users: { u1: tempUser({ courses: ["c-soon"] }) },
      courses: { "c-soon": course({ uid: "c-soon", startDate: Timestamp.fromMillis(SOON) }) },
      subs: {},
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "c-soon", userId: "u1", confirmedNoRefund: true } },
      db,
      {},
      NOW
    );
    const cancelled = store.users.u1.cancelledEnrollments as Data[];
    expect(cancelled).toHaveLength(1);
    expect(cancelled[0].entryLost).toBe(true);
  });

  test("multi-abbonamento ENTRIES fuori finestra: ripristina ingresso doc + snapshot", async () => {
    const store: FakeStore = {
      users: {
        u1: subUser({
          courses: ["ch"],
          activeSubscriptions: [snapshotEntry("sub-hyrox", hyroxSubDoc(9))],
        }),
      },
      courses: { ch: course({ uid: "ch", tags: ["Hyrox"] }) },
      subs: { "sub-hyrox": hyroxSubDoc(9) },
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "ch", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.subs["sub-hyrox"].remainingEntries).toBe(10);
    const snap = store.users.u1.activeSubscriptions as Data[];
    expect(snap[0].remainingEntries).toBe(10);
  });

  test("FREQUENCY multi-abbonamento fuori 4h: traccia cancelled, NON tocca subscriptions/entrate", async () => {
    const store: FakeStore = {
      users: {
        u1: subUser({
          courses: ["c1"],
          entrateDisponibili: 2,
          activeSubscriptions: [snapshotEntry("sub-open", openFreqSubDoc(2))],
        }),
      },
      courses: { c1: course() }, // FAR (~22h)
      subs: { "sub-open": openFreqSubDoc(2) },
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    const cancelled = store.users.u1.cancelledEnrollments as Data[];
    expect(cancelled).toHaveLength(1);
    expect(cancelled[0].entryLost).toBe(false);
    expect(store.users.u1.entrateDisponibili).toBe(2); // non toccato
    expect(store.subs["sub-open"].weeklyFrequency).toBe(2); // doc intatto
  });

  test("transizione legacy→abbonamento: il rimborso ripristina la fonte CONSUMATA (registro), non il modello attuale", async () => {
    // Prenotazione fatta da legacy (registro: LEGACY_ENTRY), poi l'admin assegna
    // un abbonamento ENTRIES. Alla disiscrizione: +1 a entrateDisponibili,
    // l'abbonamento resta intatto (niente ingressi coniati).
    const store: FakeStore = {
      users: {
        u1: subUser({
          courses: ["ch"],
          entrateDisponibili: 4,
          enrollmentConsumption: { ch: { kind: "LEGACY_ENTRY" } },
          activeSubscriptions: [snapshotEntry("sub-hyrox", hyroxSubDoc(10))],
        }),
      },
      courses: { ch: course({ uid: "ch", tags: ["Hyrox"] }) },
      subs: { "sub-hyrox": hyroxSubDoc(10) },
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "ch", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.users.u1.entrateDisponibili).toBe(5); // fonte legacy ripristinata
    expect(store.subs["sub-hyrox"].remainingEntries).toBe(10); // MAI 11
    expect(store.users.u1.enrollmentConsumption).toEqual({}); // registro ripulito
  });

  test("prenotazione con consumo NONE (force a credito esaurito): nessun ripristino", async () => {
    const store: FakeStore = {
      users: {
        u1: packUser({
          courses: ["c1"],
          entrateDisponibili: 0,
          enrollmentConsumption: { c1: { kind: "NONE" } },
        }),
      },
      courses: { c1: course() },
      subs: {},
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.users.u1.entrateDisponibili).toBe(0); // niente ingressi dal nulla
    expect(store.users.u1.courses).toEqual([]);
  });

  test("clamp difensivo: il ripristino non supera mai gli ingressi del piano", async () => {
    const store: FakeStore = {
      users: {
        u1: subUser({
          courses: ["ch"],
          // Registro corrotto/anomalo: dice SUBSCRIPTION_ENTRY ma il doc è già al massimo.
          enrollmentConsumption: {
            ch: { kind: "SUBSCRIPTION_ENTRY", subscriptionId: "sub-hyrox" },
          },
          activeSubscriptions: [snapshotEntry("sub-hyrox", hyroxSubDoc(10))],
        }),
      },
      courses: { ch: course({ uid: "ch", tags: ["Hyrox"] }) },
      subs: { "sub-hyrox": hyroxSubDoc(10) }, // piano hyrox_10i_3m → max 10
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "ch", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.subs["sub-hyrox"].remainingEntries).toBe(10); // clampato
  });

  test("entro finestra con conferma: il registro è ripulito ma la fonte NON è ripristinata", async () => {
    const store: FakeStore = {
      users: {
        u1: packUser({
          courses: ["c-mid"],
          entrateDisponibili: 4,
          enrollmentConsumption: { "c-mid": { kind: "LEGACY_ENTRY" } },
        }),
      },
      courses: { "c-mid": course({ uid: "c-mid", startDate: Timestamp.fromMillis(MID) }) },
      subs: {},
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "c-mid", userId: "u1", confirmedNoRefund: true } },
      db,
      {},
      NOW
    );
    expect(store.users.u1.entrateDisponibili).toBe(4); // perso
    expect(store.users.u1.enrollmentConsumption).toEqual({});
  });

  test("utente normale non può disiscrivere un altro → permission-denied", async () => {
    const db = makeDb({
      users: { u1: packUser(), u2: packUser({ uid: "u2", courses: ["c1"] }) },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      unsubscribeFromCourseHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u2" } }, db, {}, NOW),
      "permission-denied"
    );
  });

  test("corso già iniziato: self bloccato; admin su altri può (senza notifica waitlist)", async () => {
    const pastCourse = () =>
      course({ uid: "c-past", startDate: Timestamp.fromMillis(NOW - 3600000) });

    const db1 = makeDb({
      users: { u1: packUser({ courses: ["c-past"] }) },
      courses: { "c-past": pastCourse() },
      subs: {},
    });
    await expectCode(
      unsubscribeFromCourseHandler(
        { ...auth("u1"), data: { courseId: "c-past", userId: "u1", confirmedNoRefund: true } },
        db1,
        {},
        NOW
      ),
      "failed-precondition"
    );

    // Correzione admin a posteriori: consentita, ma nessuna email waitlist.
    const notified: string[] = [];
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        u2: packUser({ uid: "u2", courses: ["c-past"] }),
      },
      courses: { "c-past": pastCourse() },
      subs: {},
    };
    await unsubscribeFromCourseHandler(
      { ...auth("boss"), data: { courseId: "c-past", userId: "u2", confirmedNoRefund: true } },
      makeDb(store),
      { notifyWaitlist: async (c) => void notified.push(c) },
      NOW
    );
    expect(store.users.u2.courses).toEqual([]);
    expect(notified).toEqual([]);
  });

  test("admin disiscrive un altro utente → ok, notifica waitlist", async () => {
    const notified: string[] = [];
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        u2: packUser({ uid: "u2", courses: ["c1"] }),
      },
      courses: { c1: course() },
      subs: {},
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("boss"), data: { courseId: "c1", userId: "u2" } },
      db,
      { notifyWaitlist: async (c) => void notified.push(c) },
      NOW
    );
    expect(store.users.u2.courses).toEqual([]);
    expect(notified).toEqual(["c1"]);
  });
});

// ──────────────────────────────────────────────
//  joinWaitlist / leaveWaitlist
// ──────────────────────────────────────────────

describe("joinWaitlistHandler", () => {
  test("corso non pieno → failed-precondition", async () => {
    const db = makeDb({
      users: { u1: packUser() },
      courses: { c1: course({ subscribed: 5 }) },
      subs: {},
    });
    await expectCode(
      joinWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db, NOW),
      "failed-precondition"
    );
  });

  test("waitlist disabilitata sul corso → failed-precondition (mirror FULL di getCourseState)", async () => {
    const db = makeDb({
      users: { u1: packUser() },
      courses: { c1: course({ subscribed: 10, waitlistEnabled: false }) },
      subs: {},
    });
    await expectCode(
      joinWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db, NOW),
      "failed-precondition"
    );
  });

  test("corso già iniziato → failed-precondition (simmetrico a subscribe)", async () => {
    const db = makeDb({
      users: { u1: packUser() },
      courses: {
        c1: course({
          subscribed: 10,
          startDate: Timestamp.fromMillis(NOW - 3600000),
        }),
      },
      subs: {},
    });
    await expectCode(
      joinWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db, NOW),
      "failed-precondition"
    );
  });

  test("happy path: aggiunge a waitlist corso + waitlistCourses utente", async () => {
    const store: FakeStore = {
      users: { u1: packUser() },
      courses: { c1: course({ subscribed: 10, waitlist: ["w0"] }) },
      subs: {},
    };
    const db = makeDb(store);
    const res = await joinWaitlistHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      NOW
    );
    expect(res.ok).toBe(true);
    expect(store.courses.c1.waitlist).toEqual(["w0", "u1"]);
    expect(store.users.u1.waitlistCourses).toEqual(["c1"]);
  });

  test("già in waitlist → already-exists; già iscritto → already-exists", async () => {
    const db1 = makeDb({
      users: { u1: packUser() },
      courses: { c1: course({ subscribed: 10, waitlist: ["u1"] }) },
      subs: {},
    });
    await expectCode(
      joinWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db1, NOW),
      "already-exists"
    );

    const db2 = makeDb({
      users: { u1: packUser({ courses: ["c1"] }) },
      courses: { c1: course({ subscribed: 10 }) },
      subs: {},
    });
    await expectCode(
      joinWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db2, NOW),
      "already-exists"
    );
  });

  test("utente normale non può aggiungere altri → permission-denied; admin sì", async () => {
    const mk = (): FakeStore => ({
      users: {
        u1: packUser(),
        u2: packUser({ uid: "u2" }),
        boss: { uid: "boss", role: "Admin" },
      },
      courses: { c1: course({ subscribed: 10 }) },
      subs: {},
    });
    await expectCode(
      joinWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u2" } }, makeDb(mk()), NOW),
      "permission-denied"
    );
    const store = mk();
    const res = await joinWaitlistHandler(
      { ...auth("boss"), data: { courseId: "c1", userId: "u2" } },
      makeDb(store),
      NOW
    );
    expect(res.ok).toBe(true);
    expect(store.courses.c1.waitlist).toEqual(["u2"]);
  });
});

describe("leaveWaitlistHandler", () => {
  test("rimuove da entrambi i lati quando coerenti", async () => {
    const store: FakeStore = {
      users: { u1: packUser({ waitlistCourses: ["c1", "c3"] }) },
      courses: { c1: course({ subscribed: 10, waitlist: ["u1", "u2"] }) },
      subs: {},
    };
    const db = makeDb(store);
    await leaveWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db);
    expect(store.courses.c1.waitlist).toEqual(["u2"]);
    expect(store.users.u1.waitlistCourses).toEqual(["c3"]);
  });

  test("incoerenza: presente solo lato utente → ripulisce comunque", async () => {
    const store: FakeStore = {
      users: { u1: packUser({ waitlistCourses: ["c1"] }) },
      courses: { c1: course({ subscribed: 10, waitlist: [] }) },
      subs: {},
    };
    const db = makeDb(store);
    const res = await leaveWaitlistHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db
    );
    expect(res.ok).toBe(true);
    expect(store.users.u1.waitlistCourses).toEqual([]);
  });

  test("nessun legame waitlist → failed-precondition", async () => {
    const db = makeDb({
      users: { u1: packUser({ waitlistCourses: ["c3"] }) },
      courses: { c1: course({ subscribed: 10, waitlist: ["u2"] }) },
      subs: {},
    });
    await expectCode(
      leaveWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u1" } }, db),
      "failed-precondition"
    );
  });

  test("admin rimuove un altro utente → ok; utente normale → permission-denied", async () => {
    const mk = (): FakeStore => ({
      users: {
        u1: packUser(),
        u2: packUser({ uid: "u2", waitlistCourses: ["c1"] }),
        boss: { uid: "boss", role: "Admin" },
      },
      courses: { c1: course({ subscribed: 10, waitlist: ["u2"] }) },
      subs: {},
    });
    await expectCode(
      leaveWaitlistHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u2" } }, makeDb(mk())),
      "permission-denied"
    );
    const store = mk();
    await leaveWaitlistHandler({ ...auth("boss"), data: { courseId: "c1", userId: "u2" } }, makeDb(store));
    expect(store.courses.c1.waitlist).toEqual([]);
    expect(store.users.u2.waitlistCourses).toEqual([]);
  });
});

// ──────────────────────────────────────────────
//  Registro consumi: retention e pruning
// ──────────────────────────────────────────────

describe("pruneConsumption (retention 90gg ancorata all'inizio del corso)", () => {
  const CUTOFF = NOW - CONSUMPTION_RETENTION_MILLIS;
  const rec = (courseStartMillis?: number): ConsumptionRecord => ({
    kind: "LEGACY_ENTRY",
    atMillis: NOW - 200 * 24 * 3600 * 1000, // prenotata 200 giorni fa: irrilevante
    ...(courseStartMillis !== undefined ? { courseStartMillis } : {}),
  });

  test("boundary: corso a cutoff esatto mantenuto, a cutoff-1ms rimosso", () => {
    const pruned = pruneConsumption(
      { keep: rec(CUTOFF), drop: rec(CUTOFF - 1) },
      NOW
    );
    expect(Object.keys(pruned)).toEqual(["keep"]);
  });

  test("prenotazione APERTA per un corso futuro (anche a 4 mesi) non è MAI prunata", () => {
    const pruned = pruneConsumption(
      { future: rec(NOW + 120 * 24 * 3600 * 1000) },
      NOW
    );
    expect(pruned.future).toBeDefined();
  });

  test("voce senza alcuna àncora (shape pre-retention) viene rimossa", () => {
    const pruned = pruneConsumption(
      { legacyShape: { kind: "LEGACY_ENTRY" } },
      NOW
    );
    expect(pruned).toEqual({});
  });

  test("subscribe: le voci di corsi frequentati >90gg fa spariscono, quelle aperte/recenti restano", async () => {
    const store: FakeStore = {
      users: {
        u1: packUser({
          enrollmentConsumption: {
            "c-antico": {
              kind: "LEGACY_ENTRY",
              atMillis: NOW - 100 * 24 * 3600 * 1000,
              courseStartMillis: NOW - 95 * 24 * 3600 * 1000, // frequentato 95gg fa
            },
            "c-aperto": {
              kind: "LEGACY_ENTRY",
              atMillis: NOW - 100 * 24 * 3600 * 1000, // prenotato 100gg fa…
              courseStartMillis: NOW + 30 * 24 * 3600 * 1000, // …per un corso futuro
            },
          },
        }),
      },
      courses: { c1: course() },
      subs: {},
    };
    const db = makeDb(store);
    await subscribeToCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    const consumption = store.users.u1.enrollmentConsumption as Record<string, unknown>;
    expect(Object.keys(consumption).sort()).toEqual(["c-aperto", "c1"]);
  });

  test("unsubscribe: la voce stantia del corso TARGET viene comunque rimborsata (lettura pre-pruning)", async () => {
    // Corso passato? No: per il rimborso fuori finestra serve un corso futuro
    // ma con voce dalla shape antica (atMillis nullo) → il rimborso usa il
    // record letto PRIMA del pruning.
    const store: FakeStore = {
      users: {
        u1: packUser({
          courses: ["c1"],
          entrateDisponibili: 4,
          enrollmentConsumption: {
            c1: { kind: "LEGACY_ENTRY" }, // nessuna àncora: prunabile
          },
        }),
      },
      courses: { c1: course() }, // FAR: fuori finestra → rimborso dovuto
      subs: {},
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("u1"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(store.users.u1.entrateDisponibili).toBe(5); // rimborsata
    expect(store.users.u1.enrollmentConsumption).toEqual({}); // e ripulita
  });
});
