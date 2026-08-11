import { Timestamp } from "firebase-admin/firestore";
import {
  deleteCourseHandler,
  recountCourseSubscribedHandler,
} from "../enrollment/admin";
import { unsubscribeFromCourseHandler } from "../enrollment/enrollment";
import { decideAdminRefund } from "../enrollment/refund";
import { makeDb, FakeStore, Data } from "./helpers/fakeDb";

// Mar 9 giu 2026, 12:00 UTC.
const NOW = Date.UTC(2026, 5, 9, 12);
// Corso a 2h (DENTRO le finestre 4h/8h: l'admin deve rimborsare comunque).
const SOON = Date.UTC(2026, 5, 9, 14);

const auth = (uid: string) => ({ auth: { uid } });

async function expectCode(p: Promise<unknown>, code: string) {
  await expect(p).rejects.toMatchObject({ code });
}

function course(over: Data = {}): Data {
  return {
    uid: "c1",
    name: "Corso Open",
    startDate: Timestamp.fromMillis(SOON),
    endDate: Timestamp.fromMillis(SOON + 3600000),
    capacity: 10,
    subscribed: 3,
    tags: ["Open"],
    waitlist: [],
    ...over,
  };
}

function hyroxSubDoc(remaining: number, userId = "u-sub"): Data {
  return {
    userId,
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

function snapshotEntry(id: string, doc: Data): Data {
  const { userId: _u, ...rest } = doc;
  return { id, ...rest };
}

describe("decideAdminRefund (regola admin-rimborsa-sempre)", () => {
  test("ENTRIES: ripristina sempre, mai conferma, mai perdita, mai tracking", () => {
    const sub = decideAdminRefund("ENTRIES_SUB", "s1");
    expect(sub).toMatchObject({
      requiresConfirmation: false,
      restoreSubscriptionEntry: true,
      subscriptionId: "s1",
      entryLost: false,
      trackCancelled: false,
    });
    const legacy = decideAdminRefund("ENTRIES_LEGACY");
    expect(legacy.restoreLegacyEntry).toBe(true);
    expect(legacy.trackCancelled).toBe(false);
  });

  test("FREQUENCY/NONE: nessun ripristino e nessuna voce cancelledEnrollments", () => {
    for (const mode of ["FREQUENCY_SUB", "FREQUENCY_LEGACY", "NONE"] as const) {
      const d = decideAdminRefund(mode);
      expect(d.requiresConfirmation).toBe(false);
      expect(d.restoreLegacyEntry).toBe(false);
      expect(d.restoreSubscriptionEntry).toBe(false);
      expect(d.trackCancelled).toBe(false);
    }
  });
});

describe("unsubscribeFromCourse — semantica ADMIN (actor ≠ target)", () => {
  test("entro finestra con confirmedNoRefund=true: rimborsa COMUNQUE, niente cancelledEnrollments", () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        u1: {
          uid: "u1",
          role: "User",
          courses: ["c1"],
          tipologiaIscrizione: "PACCHETTO_ENTRATE",
          entrateDisponibili: 4,
          enrollmentConsumption: { c1: { kind: "LEGACY_ENTRY", atMillis: NOW - 1000 } },
        },
      },
      courses: { c1: course() }, // a 2h: entro la finestra 8h
      subs: {},
    };
    const db = makeDb(store);
    return unsubscribeFromCourseHandler(
      { ...auth("boss"), data: { courseId: "c1", userId: "u1", confirmedNoRefund: true } },
      db,
      {},
      NOW
    ).then(() => {
      expect(store.users.u1.entrateDisponibili).toBe(5); // rimborsato nonostante la "conferma"
      expect(store.users.u1.cancelledEnrollments).toBeUndefined(); // nessun tracking admin
      expect(store.users.u1.courses).toEqual([]);
      expect(store.courses.c1.subscribed).toBe(2);
    });
  });

  test("entro finestra senza conferma: nessuna richiesta di conferma per l'admin", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        u1: {
          uid: "u1",
          role: "User",
          courses: ["c1"],
          tipologiaIscrizione: "ABBONAMENTO_MENSILE",
          entrateSettimanali: 2,
        },
      },
      courses: { c1: course() },
      subs: {},
    };
    const db = makeDb(store);
    const res = await unsubscribeFromCourseHandler(
      { ...auth("boss"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(res.ok).toBe(true);
    // FREQUENCY + admin: nessuna voce tracciata (non pesa sul limite settimanale).
    expect(store.users.u1.cancelledEnrollments).toBeUndefined();
  });

  test("ripristina remainingEntries dal registro consumi (nuovo modello)", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        "u-sub": {
          uid: "u-sub",
          role: "User",
          courses: ["ch"],
          tipologiaCorsoTags: [],
          activeSubscriptions: [snapshotEntry("sub-1", hyroxSubDoc(9))],
          enrollmentConsumption: {
            ch: { kind: "SUBSCRIPTION_ENTRY", subscriptionId: "sub-1", atMillis: NOW - 1000 },
          },
        },
      },
      courses: { ch: course({ uid: "ch", tags: ["Hyrox"] }) },
      subs: { "sub-1": hyroxSubDoc(9) },
    };
    const db = makeDb(store);
    await unsubscribeFromCourseHandler(
      { ...auth("boss"), data: { courseId: "ch", userId: "u-sub", confirmedNoRefund: true } },
      db,
      {},
      NOW
    );
    expect(store.subs["sub-1"].remainingEntries).toBe(10);
    const snap = store.users["u-sub"].activeSubscriptions as Data[];
    expect(snap[0].remainingEntries).toBe(10);
    expect(store.users["u-sub"].enrollmentConsumption).toEqual({});
  });
});

describe("deleteCourseHandler", () => {
  test("non autenticato → unauthenticated; non privilegiato → permission-denied", async () => {
    const mk = (): FakeStore => ({
      users: { u1: { uid: "u1", role: "User", courses: [] } },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      deleteCourseHandler({ auth: null, data: { courseId: "c1" } }, makeDb(mk())),
      "unauthenticated"
    );
    await expectCode(
      deleteCourseHandler({ ...auth("u1"), data: { courseId: "c1" } }, makeDb(mk()), NOW),
      "permission-denied"
    );
  });

  test("corso inesistente → not-found", async () => {
    const db = makeDb({
      users: { boss: { uid: "boss", role: "Admin" } },
      courses: {},
      subs: {},
    });
    await expectCode(
      deleteCourseHandler({ ...auth("boss"), data: { courseId: "nope" } }, db, NOW),
      "not-found"
    );
  });

  test("atomico multi-utente: rimborsi da registro (legacy + abbonamento), waitlist ripulita, corso eliminato", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        "u-legacy": {
          uid: "u-legacy",
          role: "User",
          courses: ["c1", "altro"],
          tipologiaIscrizione: "PACCHETTO_ENTRATE",
          entrateDisponibili: 2,
          enrollmentConsumption: {
            c1: { kind: "LEGACY_ENTRY", atMillis: NOW - 1000 },
            altro: { kind: "LEGACY_ENTRY", atMillis: NOW - 2000 },
          },
        },
        "u-sub": {
          uid: "u-sub",
          role: "User",
          courses: ["c1"],
          tipologiaCorsoTags: [],
          activeSubscriptions: [snapshotEntry("sub-1", hyroxSubDoc(7))],
          enrollmentConsumption: {
            c1: { kind: "SUBSCRIPTION_ENTRY", subscriptionId: "sub-1", atMillis: NOW - 1000 },
          },
        },
        "u-wait": {
          uid: "u-wait",
          role: "User",
          courses: [],
          waitlistCourses: ["c1", "c9"],
        },
      },
      courses: { c1: course({ tags: ["Hyrox"], waitlist: ["u-wait"] }) },
      subs: { "sub-1": hyroxSubDoc(7) },
    };
    const db = makeDb(store);
    const res = await deleteCourseHandler(
      { ...auth("boss"), data: { courseId: "c1" } },
      db,
      NOW
    );
    expect(res).toMatchObject({ ok: true, removedSubscribers: 2, removedWaitlist: 1 });

    expect(store.courses.c1).toBeUndefined(); // corso eliminato
    expect(store.users["u-legacy"].entrateDisponibili).toBe(3); // rimborso legacy
    expect(store.users["u-legacy"].courses).toEqual(["altro"]);
    // La voce di c1 sparisce, quella di "altro" resta.
    expect(Object.keys(store.users["u-legacy"].enrollmentConsumption as Data)).toEqual(["altro"]);
    expect(store.subs["sub-1"].remainingEntries).toBe(8); // rimborso abbonamento
    const snap = store.users["u-sub"].activeSubscriptions as Data[];
    expect(snap[0].remainingEntries).toBe(8);
    expect(store.users["u-wait"].waitlistCourses).toEqual(["c9"]);
  });

  test("fallback senza registro: rimborsa dal modello attuale (fix crash entrate null del legacy)", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        "u-old": {
          uid: "u-old",
          role: "User",
          courses: ["c1"],
          tipologiaIscrizione: "PACCHETTO_ENTRATE",
          entrateDisponibili: null, // il client legacy sarebbe crashato
        },
      },
      courses: { c1: course() },
      subs: {},
    };
    const db = makeDb(store);
    await deleteCourseHandler({ ...auth("boss"), data: { courseId: "c1" } }, db, NOW);
    expect(store.users["u-old"].entrateDisponibili).toBe(1); // null ⇒ 0+1
  });

  test("clamp: il rimborso non supera il massimo del piano", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        "u-sub": {
          uid: "u-sub",
          role: "User",
          courses: ["c1"],
          tipologiaCorsoTags: [],
          activeSubscriptions: [snapshotEntry("sub-1", hyroxSubDoc(10))],
          enrollmentConsumption: {
            c1: { kind: "SUBSCRIPTION_ENTRY", subscriptionId: "sub-1", atMillis: NOW - 1000 },
          },
        },
      },
      courses: { c1: course({ tags: ["Hyrox"] }) },
      subs: { "sub-1": hyroxSubDoc(10) }, // già al massimo (10)
    };
    const db = makeDb(store);
    await deleteCourseHandler({ ...auth("boss"), data: { courseId: "c1" } }, db, NOW);
    expect(store.subs["sub-1"].remainingEntries).toBe(10);
  });
});

describe("recountCourseSubscribedHandler", () => {
  test("non privilegiato → permission-denied", async () => {
    const db = makeDb({
      users: { u1: { uid: "u1", role: "User", courses: [] } },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      recountCourseSubscribedHandler({ ...auth("u1"), data: { courseId: "c1" } }, db),
      "permission-denied"
    );
  });

  test("ricalcola subscribed dalla fonte di verità (utenti con il corso in courses[])", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        a: { uid: "a", role: "User", courses: ["c1"] },
        b: { uid: "b", role: "User", courses: ["c1", "c2"] },
        c: { uid: "c", role: "User", courses: ["c2"] },
      },
      courses: { c1: course({ subscribed: 7 }) }, // contatore gonfio (bug legacy)
      subs: {},
    };
    const db = makeDb(store);
    const res = await recountCourseSubscribedHandler(
      { ...auth("boss"), data: { courseId: "c1" } },
      db
    );
    expect(res).toMatchObject({ ok: true, subscribed: 2 });
    expect(store.courses.c1.subscribed).toBe(2);
  });
});

describe("deleteCourseHandler — casi limite (gate PR5)", () => {
  test("Trainer NON può cancellare (UI riserva all'Admin) → permission-denied", async () => {
    const db = makeDb({
      users: { coach: { uid: "coach", role: "Trainer" } },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      deleteCourseHandler({ ...auth("coach"), data: { courseId: "c1" } }, db, NOW),
      "permission-denied"
    );
  });

  test("courseId mancante → invalid-argument", async () => {
    const db = makeDb({
      users: { boss: { uid: "boss", role: "Admin" } },
      courses: {},
      subs: {},
    });
    await expectCode(
      deleteCourseHandler({ ...auth("boss"), data: {} }, db, NOW),
      "invalid-argument"
    );
  });

  test("corso GIÀ INIZIATO (pulizia storico): NESSUN rimborso, iscrizioni/waitlist rimosse", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        "u-att": {
          uid: "u-att",
          role: "User",
          courses: ["c-past"],
          tipologiaIscrizione: "PACCHETTO_ENTRATE",
          entrateDisponibili: 2,
          enrollmentConsumption: {
            "c-past": {
              kind: "LEGACY_ENTRY",
              atMillis: NOW - 7 * 24 * 3600 * 1000,
              courseStartMillis: NOW - 3600 * 1000,
            },
          },
        },
        "u-w": { uid: "u-w", role: "User", courses: [], waitlistCourses: ["c-past"] },
      },
      courses: {
        "c-past": course({
          uid: "c-past",
          startDate: Timestamp.fromMillis(NOW - 3600 * 1000), // iniziato 1h fa
          waitlist: ["u-w"],
        }),
      },
      subs: {},
    };
    const db = makeDb(store);
    const res = await deleteCourseHandler(
      { ...auth("boss"), data: { courseId: "c-past" } },
      db,
      NOW
    );
    expect(res).toMatchObject({ ok: true, removedSubscribers: 1, removedWaitlist: 1 });
    expect(store.courses["c-past"]).toBeUndefined();
    expect(store.users["u-att"].entrateDisponibili).toBe(2); // ha frequentato: NIENTE rimborso
    expect(store.users["u-att"].courses).toEqual([]);
    expect(store.users["u-w"].waitlistCourses).toEqual([]);
  });

  test("fallback SENZA registro per utente nuovo modello: rimborsa l'abbonamento dal modello attuale", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        "u-sub": {
          uid: "u-sub",
          role: "User",
          courses: ["c1"],
          tipologiaCorsoTags: [],
          activeSubscriptions: [snapshotEntry("sub-1", hyroxSubDoc(5))],
          // NESSUN enrollmentConsumption (prenotazione pre-registro)
        },
      },
      courses: { c1: course({ tags: ["Hyrox"] }) },
      subs: { "sub-1": hyroxSubDoc(5) },
    };
    const db = makeDb(store);
    await deleteCourseHandler({ ...auth("boss"), data: { courseId: "c1" } }, db, NOW);
    expect(store.subs["sub-1"].remainingEntries).toBe(6);
  });

  test("merge difensivo: utente sia iscritto SIA in waitlist → un solo update coerente", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        "u-both": {
          uid: "u-both",
          role: "User",
          courses: ["c1"],
          waitlistCourses: ["c1"],
          tipologiaIscrizione: "PACCHETTO_ENTRATE",
          entrateDisponibili: 1,
          enrollmentConsumption: {
            c1: { kind: "LEGACY_ENTRY", atMillis: NOW - 1000, courseStartMillis: SOON },
          },
        },
      },
      courses: { c1: course({ waitlist: ["u-both"] }) },
      subs: {},
    };
    const db = makeDb(store);
    await deleteCourseHandler({ ...auth("boss"), data: { courseId: "c1" } }, db, NOW);
    expect(store.users["u-both"].courses).toEqual([]);
    expect(store.users["u-both"].waitlistCourses).toEqual([]);
    expect(store.users["u-both"].entrateDisponibili).toBe(2); // corso futuro: rimborsato
  });

  test("guardia MAX_AFFECTED_USERS: oltre il limite → failed-precondition, nessuna modifica", async () => {
    const users: Record<string, Data> = { boss: { uid: "boss", role: "Admin" } };
    for (let i = 0; i < 201; i++) {
      users[`u${i}`] = { uid: `u${i}`, role: "User", courses: ["c1"] };
    }
    const store: FakeStore = { users, courses: { c1: course() }, subs: {} };
    const db = makeDb(store);
    await expectCode(
      deleteCourseHandler({ ...auth("boss"), data: { courseId: "c1" } }, db, NOW),
      "failed-precondition"
    );
    expect(store.courses.c1).toBeDefined(); // niente cancellazione parziale
  });
});

describe("rimozione admin con contatore corrotto", () => {
  test("subscribed=0 ma utente iscritto: l'admin può sanare, contatore resta 0", async () => {
    const store: FakeStore = {
      users: {
        boss: { uid: "boss", role: "Admin" },
        u1: {
          uid: "u1",
          role: "User",
          courses: ["c1"],
          tipologiaIscrizione: "PACCHETTO_ENTRATE",
          entrateDisponibili: 1,
        },
      },
      courses: { c1: course({ subscribed: 0 }) }, // contatore corrotto
      subs: {},
    };
    const db = makeDb(store);
    const res = await unsubscribeFromCourseHandler(
      { ...auth("boss"), data: { courseId: "c1", userId: "u1" } },
      db,
      {},
      NOW
    );
    expect(res.ok).toBe(true);
    expect(store.users.u1.courses).toEqual([]);
    expect(store.courses.c1.subscribed).toBe(0); // clampato, non -1
    expect(store.users.u1.entrateDisponibili).toBe(2); // rimborso admin
  });
});

describe("recountCourseSubscribedHandler — authz Trainer", () => {
  test("Trainer → permission-denied (operazione riservata agli Admin)", async () => {
    const db = makeDb({
      users: { coach: { uid: "coach", role: "Trainer" } },
      courses: { c1: course() },
      subs: {},
    });
    await expectCode(
      recountCourseSubscribedHandler({ ...auth("coach"), data: { courseId: "c1" } }, db),
      "permission-denied"
    );
  });
});
