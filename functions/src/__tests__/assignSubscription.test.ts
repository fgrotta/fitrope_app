import { Timestamp } from "firebase-admin/firestore";
import { assignSubscriptionHandler } from "../enrollment/assignSubscription";

const ADMIN_UID = "admin-uid";

interface FakeOpts {
  callerRole?: string | null; // ruolo del chiamante (ADMIN_UID); undefined = doc inesistente
  existingSubs?: Array<Record<string, unknown>>; // doc esistenti in `subscriptions`
}

function makeFakeDb(opts: FakeOpts) {
  const users: Record<string, Record<string, unknown>> = {};
  if (opts.callerRole !== undefined && opts.callerRole !== null) {
    users[ADMIN_UID] = { role: opts.callerRole };
  }
  const subs: Record<string, Record<string, unknown>> = {};
  (opts.existingSubs ?? []).forEach((s, i) => (subs[`existing-${i}`] = s));

  const writes = {
    subs: {} as Record<string, unknown>,
    users: {} as Record<string, unknown>,
  };
  let counter = 0;

  const db: any = {
    collection(name: string) {
      if (name === "users") {
        return {
          doc: (id: string) => ({
            _kind: "userDoc",
            _id: id,
            get: async () => ({
              exists: users[id] !== undefined,
              data: () => users[id],
            }),
          }),
        };
      }
      if (name === "subscriptions") {
        return {
          doc: () => {
            const id = `new-${counter++}`;
            return { _kind: "subDoc", _id: id, id };
          },
          where: (_f: string, _o: string, val: unknown) => ({
            _kind: "subQuery",
            _userId: val,
          }),
        };
      }
      throw new Error(`collezione non gestita: ${name}`);
    },
    runTransaction: async (fn: (tx: unknown) => Promise<void>) => {
      const tx = {
        get: async (q: any) => {
          if (q._kind === "subQuery") {
            const docs = Object.entries(subs)
              .filter(([, v]) => v.userId === q._userId)
              .map(([id, v]) => ({ id, data: () => v }));
            return { docs };
          }
          return { exists: false, data: () => undefined };
        },
        set: (ref: any, data: Record<string, unknown>) => {
          if (ref._kind === "subDoc") writes.subs[ref._id] = data;
          else if (ref._kind === "userDoc") writes.users[ref._id] = data;
        },
      };
      await fn(tx);
    },
  };
  return { db, writes };
}

function activeOpenDoc(userId: string): Record<string, unknown> {
  return {
    userId,
    family: "OPEN",
    billingMode: "FREQUENCY",
    courseTypeTags: ["Open"],
    weeklyFrequency: 2,
    remainingEntries: null,
    startDate: Timestamp.fromMillis(Date.now() - 86400000),
    endDate: Timestamp.fromMillis(Date.now() + 86400000),
    planKey: "open_2x_1m",
  };
}

async function expectCode(p: Promise<unknown>, code: string) {
  await expect(p).rejects.toMatchObject({ code });
}

describe("assignSubscriptionHandler", () => {
  const auth = { uid: ADMIN_UID };

  test("non autenticato -> unauthenticated", async () => {
    const { db } = makeFakeDb({ callerRole: "Admin" });
    await expectCode(
      assignSubscriptionHandler({ auth: null, data: { userId: "u1", planKey: "open_2x_1m" } }, db),
      "unauthenticated"
    );
  });

  test("chiamante non Admin -> permission-denied", async () => {
    const { db } = makeFakeDb({ callerRole: "User" });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { userId: "u1", planKey: "open_2x_1m" } }, db),
      "permission-denied"
    );
  });

  test("argomenti mancanti -> invalid-argument", async () => {
    const { db } = makeFakeDb({ callerRole: "Admin" });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { planKey: "open_2x_1m" } }, db),
      "invalid-argument"
    );
  });

  test("piano sconosciuto -> invalid-argument", async () => {
    const { db } = makeFakeDb({ callerRole: "Admin" });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { userId: "u1", planKey: "inesistente" } }, db),
      "invalid-argument"
    );
  });

  test("famiglia già attiva -> already-exists", async () => {
    const { db } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [activeOpenDoc("u1")],
    });
    await expectCode(
      assignSubscriptionHandler(
        { auth, data: { userId: "u1", planKey: "open_3x_3m" } },
        db
      ),
      "already-exists"
    );
  });

  test("happy path: crea doc subscription + snapshot sul doc utente", async () => {
    const { db, writes } = makeFakeDb({ callerRole: "Admin" });
    const res = await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "hyrox_10i_1m", startDateMillis: Date.now() } },
      db
    );
    expect(res.ok).toBe(true);
    expect(Object.keys(writes.subs).length).toBe(1);

    const snap = writes.users["u1"] as { activeSubscriptions: any[] };
    expect(snap.activeSubscriptions.length).toBe(1);
    expect(snap.activeSubscriptions[0].family).toBe("HYROX");
    expect(snap.activeSubscriptions[0].remainingEntries).toBe(10);
    expect(snap.activeSubscriptions[0].id).toBe(res.subscriptionId);
  });

  test("famiglia diversa da una già attiva -> consentito, snapshot fonde entrambi", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [activeOpenDoc("u1")],
    });
    await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "hyrox_10i_1m" } },
      db
    );
    const snap = writes.users["u1"] as { activeSubscriptions: any[] };
    const families = snap.activeSubscriptions.map((s) => s.family).sort();
    expect(families).toEqual(["HYROX", "OPEN"]);
  });
});
