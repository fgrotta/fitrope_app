import { Timestamp } from "firebase-admin/firestore";
import {
  scheduleTrialReminder,
  notifyWaitlistUsers,
} from "../enrollment/notify";


// Mar 9 giu 2026, 12:00 UTC (14:00 Rome).
const NOW = Date.UTC(2026, 5, 9, 12);
// Corso mer 10 giu 10:00 Rome (08:00Z): promemoria 9 giu 19:00 Rome (17:00Z) > NOW.
const COURSE_START = Date.UTC(2026, 5, 10, 8);
const COURSE_END = Date.UTC(2026, 5, 10, 9);

type Data = Record<string, unknown>;

interface NotifyStore {
  users: Record<string, Data>;
  courses: Record<string, Data>;
}

interface BatchUpdate {
  refId: string;
  refKind: string;
  data: Data;
}

function makeNotifyDb(store: NotifyStore) {
  const batchUpdates: BatchUpdate[] = [];
  let batchCommits = 0;

  const db = {
    collection(name: string) {
      if (name === "courses") {
        return {
          where: (_f: string, _op: string, v: unknown) => ({
            limit: () => ({
              get: async () => {
                const entries = Object.entries(store.courses).filter(
                  ([, d]) => d.uid === v
                );
                return {
                  empty: entries.length === 0,
                  docs: entries.map(([id, d]) => ({
                    id,
                    data: () => d,
                    ref: { _kind: "courseDoc", _id: id },
                  })),
                };
              },
            }),
          }),
        };
      }
      if (name === "users") {
        return {
          doc: (id: string) => ({
            _kind: "userDoc",
            _id: id,
            get: async () => ({
              exists: store.users[id] !== undefined,
              data: () => store.users[id],
            }),
          }),
          where: (_f: string, _op: string, ids: unknown) => ({
            get: async () => {
              const wanted = new Set(ids as string[]);
              const docs = Object.entries(store.users)
                .filter(([, d]) => wanted.has(d.uid as string))
                .map(([id, d]) => ({ id, data: () => d }));
              return { docs };
            },
          }),
        };
      }
      throw new Error(`collezione non gestita: ${name}`);
    },
    batch: () => ({
      update: (ref: { _kind: string; _id: string }, data: Data) => {
        batchUpdates.push({ refId: ref._id, refKind: ref._kind, data });
      },
      commit: async () => {
        batchCommits += 1;
      },
    }),
  };
  return { db: db as never, batchUpdates, commits: () => batchCommits };
}

function courseDoc(over: Data = {}): Data {
  return {
    uid: "c1",
    name: "Corso Open",
    startDate: Timestamp.fromMillis(COURSE_START),
    endDate: Timestamp.fromMillis(COURSE_END),
    capacity: 10,
    subscribed: 5,
    waitlist: [],
    ...over,
  };
}

let fetchMock: jest.Mock;

beforeEach(() => {
  fetchMock = jest.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => ({}),
  });
  (global as Record<string, unknown>).fetch = fetchMock;
});

function sentPayloads(): Data[] {
  return fetchMock.mock.calls.map((c) => JSON.parse(c[1].body as string));
}

describe("scheduleTrialReminder (orchestrazione)", () => {
  test("reminderEnabled=false → nessun invio", async () => {
    const { db } = makeNotifyDb({
      users: { u1: { uid: "u1" } },
      courses: { c1: courseDoc({ reminderEnabled: false }) },
    });
    await scheduleTrialReminder(db, "key", "u1", "c1", NOW);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("data di invio già passata → nessun invio", async () => {
    // NOW dopo le 19:00 Rome del giorno prima (9 giu 20:00 Rome = 18:00Z).
    const { db } = makeNotifyDb({
      users: { u1: { uid: "u1" } },
      courses: { c1: courseDoc() },
    });
    await scheduleTrialReminder(db, "key", "u1", "c1", Date.UTC(2026, 5, 9, 18));
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("corso inesistente → nessun invio (no throw)", async () => {
    const { db } = makeNotifyDb({ users: {}, courses: {} });
    await scheduleTrialReminder(db, "key", "u1", "manca", NOW);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("invia push+email schedulate alle 19:00 Rome del giorno prima", async () => {
    const { db } = makeNotifyDb({
      users: { u1: { uid: "u1" } }, // preferenze default = entrambe attive
      courses: { c1: courseDoc() },
    });
    await scheduleTrialReminder(db, "key", "u1", "c1", NOW);
    const payloads = sentPayloads();
    expect(payloads).toHaveLength(2);
    const channels = payloads.map((p) => p.target_channel).sort();
    expect(channels).toEqual(["email", "push"]);
    for (const p of payloads) {
      expect(p.send_after).toBe(new Date(Date.UTC(2026, 5, 9, 17)).toISOString());
      expect((p.include_aliases as Data).external_id).toEqual(["u1"]);
      expect(p.app_id).toBeDefined(); // iniettato server-side
    }
  });

  test("rispetta le preferenze: solo email se push disabilitata", async () => {
    const { db } = makeNotifyDb({
      users: { u1: { uid: "u1", pushNotificationsEnabled: false } },
      courses: { c1: courseDoc() },
    });
    await scheduleTrialReminder(db, "key", "u1", "c1", NOW);
    const payloads = sentPayloads();
    expect(payloads).toHaveLength(1);
    expect(payloads[0].target_channel).toBe("email");
  });
});

describe("notifyWaitlistUsers (orchestrazione)", () => {
  test("waitlistEnabled=false → nessun invio", async () => {
    const { db } = makeNotifyDb({
      users: { u1: { uid: "u1" } },
      courses: {
        c1: courseDoc({ waitlistEnabled: false, waitlist: ["u1"], subscribed: 5 }),
      },
    });
    await notifyWaitlistUsers(db, "key", "c1");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("corso ancora pieno → nessun invio", async () => {
    const { db } = makeNotifyDb({
      users: { u1: { uid: "u1" } },
      courses: { c1: courseDoc({ waitlist: ["u1"], subscribed: 10 }) },
    });
    await notifyWaitlistUsers(db, "key", "c1");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("utente legacy con fineIscrizione scaduta: RIMOSSO dalla waitlist, nessuna email", async () => {
    const { db, batchUpdates, commits } = makeNotifyDb({
      users: {
        "u-expired": {
          uid: "u-expired",
          fineIscrizione: Timestamp.fromMillis(COURSE_START - 86400000),
        },
      },
      courses: { c1: courseDoc({ waitlist: ["u-expired"], subscribed: 5 }) },
    });
    await notifyWaitlistUsers(db, "key", "c1");
    expect(fetchMock).not.toHaveBeenCalled(); // nessun destinatario rimasto
    expect(commits()).toBe(1);
    // Batch: rimozione da course.waitlist + user.waitlistCourses.
    expect(batchUpdates.map((u) => u.refKind).sort()).toEqual([
      "courseDoc",
      "userDoc",
    ]);
    expect(
      batchUpdates.find((u) => u.refKind === "userDoc")?.refId
    ).toBe("u-expired");
  });

  test("utente NUOVO MODELLO con fineIscrizione stantia: NON rimosso, email inviata", async () => {
    const { db, commits } = makeNotifyDb({
      users: {
        "u-converted": {
          uid: "u-converted",
          fineIscrizione: Timestamp.fromMillis(COURSE_START - 86400000), // stantia
          activeSubscriptions: [{ id: "s1", family: "OPEN" }], // snapshot vivo
        },
      },
      courses: { c1: courseDoc({ waitlist: ["u-converted"], subscribed: 5 }) },
    });
    await notifyWaitlistUsers(db, "key", "c1");
    expect(commits()).toBe(0); // nessuna rimozione
    const payloads = sentPayloads();
    expect(payloads).toHaveLength(1);
    expect((payloads[0].include_aliases as Data).external_id).toEqual([
      "u-converted",
    ]);
    expect(payloads[0].target_channel).toBe("email");
  });

  test("rispetta emailNotificationsEnabled=false (nessun destinatario → nessun invio)", async () => {
    const { db } = makeNotifyDb({
      users: { u1: { uid: "u1", emailNotificationsEnabled: false } },
      courses: { c1: courseDoc({ waitlist: ["u1"], subscribed: 5 }) },
    });
    await notifyWaitlistUsers(db, "key", "c1");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("mix: scaduto rimosso, convertito ed eleggibile notificati", async () => {
    const { db, batchUpdates } = makeNotifyDb({
      users: {
        "u-expired": {
          uid: "u-expired",
          fineIscrizione: Timestamp.fromMillis(COURSE_START - 1000),
        },
        "u-converted": {
          uid: "u-converted",
          fineIscrizione: Timestamp.fromMillis(COURSE_START - 1000),
          activeSubscriptions: [{ id: "s1" }],
        },
        "u-ok": { uid: "u-ok" },
      },
      courses: {
        c1: courseDoc({
          waitlist: ["u-expired", "u-converted", "u-ok"],
          subscribed: 8,
        }),
      },
    });
    await notifyWaitlistUsers(db, "key", "c1");
    const payloads = sentPayloads();
    expect(payloads).toHaveLength(1);
    const recipients = (payloads[0].include_aliases as Data).external_id as string[];
    expect(recipients.sort()).toEqual(["u-converted", "u-ok"]);
    expect(
      batchUpdates.filter((u) => u.refKind === "userDoc").map((u) => u.refId)
    ).toEqual(["u-expired"]);
  });
});
