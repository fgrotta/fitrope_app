import { Timestamp } from "firebase-admin/firestore";
import { assignSubscriptionHandler } from "../enrollment/assignSubscription";

const ADMIN_UID = "admin-uid";

interface FakeOpts {
  callerRole?: string | null; // ruolo del chiamante (ADMIN_UID); undefined = doc inesistente
  existingSubs?: Array<Record<string, unknown>>; // doc esistenti in `subscriptions`
  targetUserExists?: boolean;
  targetUser?: Record<string, unknown>;
}

function makeFakeDb(opts: FakeOpts) {
  const users: Record<string, Record<string, unknown>> = {};
  if (opts.callerRole !== undefined && opts.callerRole !== null) {
    users[ADMIN_UID] = { role: opts.callerRole };
  }
  if (opts.targetUserExists !== false) {
    users.u1 = { uid: "u1", role: "User", ...(opts.targetUser ?? {}) };
  }
  const subs: Record<string, Record<string, unknown>> = {};
  (opts.existingSubs ?? []).forEach((s, i) => (subs[`existing-${i}`] = s));

  const writes = {
    subs: {} as Record<string, unknown>,
    subUpdates: {} as Record<string, Record<string, unknown>>,
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
          if (q._kind === "userDoc") {
            return {
              exists: users[q._id] !== undefined,
              data: () => users[q._id],
            };
          }
          if (q._kind === "subQuery") {
            const docs = Object.entries(subs)
              .filter(([, v]) => v.userId === q._userId)
              .map(([id, v]) => ({
                id,
                data: () => v,
                ref: { _kind: "subDoc", _id: id },
              }));
            return { docs };
          }
          return { exists: false, data: () => undefined };
        },
        set: (ref: any, data: Record<string, unknown>) => {
          if (ref._kind === "subDoc") writes.subs[ref._id] = data;
          else if (ref._kind === "userDoc") writes.users[ref._id] = data;
        },
        update: (ref: any, data: Record<string, unknown>) => {
          if (ref._kind === "subDoc") writes.subUpdates[ref._id] = data;
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

const DAY = 86400000;

function subDoc(
  userId: string,
  planKey: string,
  startMillis: number,
  endMillis: number,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  const entries = planKey === "open_trial_1i_30d" ? 1 : planKey.includes("_10i_") ? 10 : null;
  const family = planKey.startsWith("pt_") ? "PT" : "OPEN";
  return {
    userId,
    planKey,
    family,
    billingMode: entries !== null ? "ENTRIES" : "FREQUENCY",
    courseTypeTags: [family === "PT" ? "Personal Trainer" : "Open"],
    weeklyFrequency: entries !== null ? null : planKey.startsWith("open_3x") ? 3 : 2,
    remainingEntries: entries,
    startDate: Timestamp.fromMillis(startMillis),
    endDate: Timestamp.fromMillis(endMillis),
    ...extra,
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

  test("utente target inesistente -> not-found senza scritture", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      targetUserExists: false,
    });
    await expectCode(
      assignSubscriptionHandler(
        { auth, data: { userId: "u1", planKey: "open_2x_1m" } },
        db
      ),
      "not-found"
    );
    expect(writes.subs).toEqual({});
    expect(writes.users).toEqual({});
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
      { auth, data: { userId: "u1", planKey: "open_10i_1m", startDateMillis: Date.now() } },
      db
    );
    expect(res.ok).toBe(true);
    expect(Object.keys(writes.subs).length).toBe(1);

    const snap = writes.users["u1"] as {
      activeSubscriptions: any[];
      subscriptionModelVersion: number;
    };
    expect(snap.activeSubscriptions.length).toBe(1);
    expect(snap.activeSubscriptions[0].family).toBe("OPEN");
    expect(snap.activeSubscriptions[0].remainingEntries).toBe(10);
    expect(snap.activeSubscriptions[0].id).toBe(res.subscriptionId);
    expect(snap.subscriptionModelVersion).toBe(2);
  });

  test("utente legacy con crediti o consumi legacy -> failed-precondition", async () => {
    const { db } = makeFakeDb({
      callerRole: "Admin",
      targetUser: {
        tipologiaIscrizione: "PACCHETTO_ENTRATE",
        enrollmentConsumption: { c1: { kind: "LEGACY_ENTRY" } },
      },
    });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { userId: "u1", planKey: "open_2x_1m" } }, db),
      "failed-precondition",
    );
  });

  test("anche un profilo marcato V2 ma misto resta bloccato", async () => {
    const { db } = makeFakeDb({
      callerRole: "Admin",
      targetUser: {
        subscriptionModelVersion: 2,
        fineIscrizione: { toMillis: () => Date.now() + 86400000 },
      },
    });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { userId: "u1", planKey: "open_2x_1m" } }, db),
      "failed-precondition",
    );
  });

  test("famiglia diversa da una già attiva -> consentito, snapshot fonde entrambi", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [activeOpenDoc("u1")],
    });
    await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "pt_10i_1m" } },
      db
    );
    const snap = writes.users["u1"] as { activeSubscriptions: any[] };
    const families = snap.activeSubscriptions.map((s) => s.family).sort();
    expect(families).toEqual(["OPEN", "PT"]);
  });

  test("date personalizzate: inizio e fine rispettate", async () => {
    const { db, writes } = makeFakeDb({ callerRole: "Admin" });
    const start = Date.now() + 2 * DAY;
    const end = start + 5 * DAY;
    const res = await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "open_2x_1m", startDateMillis: start, endDateMillis: end } },
      db
    );
    const doc = writes.subs[res.subscriptionId as string] as any;
    expect(doc.startDate.toMillis()).toBe(start);
    expect(doc.endDate.toMillis()).toBe(end);
    // Inizio futuro: entra comunque nello snapshot.
    const snap = writes.users["u1"] as { activeSubscriptions: any[] };
    expect(snap.activeSubscriptions).toHaveLength(1);
  });

  test.each([
    ["fine prima dell'inizio", Date.now(), Date.now() - DAY],
    ["inizio NaN", NaN, Date.now()],
    ["fine non numerica", Date.now(), "domani"],
  ])("finestra non valida (%s) -> invalid-argument", async (_l, start, end) => {
    const { db, writes } = makeFakeDb({ callerRole: "Admin" });
    await expectCode(
      assignSubscriptionHandler(
        { auth, data: { userId: "u1", planKey: "open_2x_1m", startDateMillis: start, endDateMillis: end } },
        db
      ),
      "invalid-argument"
    );
    expect(writes.subs).toEqual({});
  });

  test("abbonamento successivo alla scadenza dell'attuale -> consentito", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [activeOpenDoc("u1")],
    });
    const start = Date.now() + 2 * DAY;
    await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "open_3x_3m", startDateMillis: start } },
      db
    );
    const snap = writes.users["u1"] as { activeSubscriptions: any[] };
    expect(snap.activeSubscriptions).toHaveLength(2);
  });

  test("conflitto con un abbonamento futuro -> already-exists", async () => {
    const future = Date.now() + 10 * DAY;
    const { db } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [subDoc("u1", "open_2x_1m", future, future + 30 * DAY)],
    });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { userId: "u1", planKey: "open_3x_3m" } }, db),
      "already-exists"
    );
  });

  test("abbonamento revocato sovrapposto -> nessun conflitto", async () => {
    const { db } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [{ ...activeOpenDoc("u1"), revokedAt: Timestamp.fromMillis(Date.now()) }],
    });
    const res = await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "open_3x_3m" } }, db
    );
    expect(res.ok).toBe(true);
  });

  test("Prova V2 in corso -> revocata e sostituita", async () => {
    const trial = subDoc("u1", "open_trial_1i_30d", Date.now() - DAY, Date.now() + 29 * DAY, {
      remainingEntries: 0,
    });
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [trial],
      targetUser: { subscriptionModelVersion: 2 },
    });
    const res = await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "open_2x_1m" } }, db
    );
    expect(res.replacedTrialIds).toEqual(["existing-0"]);
    const revoked = writes.subUpdates["existing-0"];
    expect(revoked.revokedAt).toBeDefined();
    expect(revoked.revokedBy).toBe(ADMIN_UID);
    expect(revoked.revokedReason).toBe("REPLACED_BY_ASSIGNMENT");
    expect(revoked.replacedBy).toBe(res.subscriptionId);
    const snap = writes.users["u1"] as { activeSubscriptions: any[] };
    expect(snap.activeSubscriptions.map((s) => s.planKey)).toEqual(["open_2x_1m"]);
  });

  test("Prova + abbonamento non-Prova in conflitto -> already-exists, Prova intatta", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [
        subDoc("u1", "open_trial_1i_30d", Date.now() - DAY, Date.now() + 29 * DAY),
        subDoc("u1", "open_2x_1m", Date.now() + 5 * DAY, Date.now() + 35 * DAY),
      ],
    });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { userId: "u1", planKey: "open_3x_3m" } }, db),
      "already-exists"
    );
    expect(writes.subUpdates).toEqual({});
  });

  test("assegnare PT non tocca la Prova Open", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      existingSubs: [subDoc("u1", "open_trial_1i_30d", Date.now() - DAY, Date.now() + 29 * DAY)],
    });
    const res = await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "pt_10i_1m" } }, db
    );
    expect(res.replacedTrialIds).toEqual([]);
    expect(writes.subUpdates).toEqual({});
    const snap = writes.users["u1"] as { activeSubscriptions: any[] };
    expect(snap.activeSubscriptions.map((s) => s.planKey).sort())
      .toEqual(["open_trial_1i_30d", "pt_10i_1m"]);
  });

  test("Prova V1 non migrata -> legacy azzerato, LEGACY_ENTRY -> NONE, marker scritto", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      targetUser: {
        tipologiaIscrizione: "ABBONAMENTO_PROVA",
        entrateDisponibili: 0,
        entrateSettimanali: null,
        fineIscrizione: Timestamp.fromMillis(Date.now() + 10 * DAY),
        enrollmentConsumption: {
          c1: { kind: "LEGACY_ENTRY", atMillis: 1, courseStartMillis: Date.now() + DAY },
          c2: { kind: "NONE", atMillis: 2 },
        },
      },
    });
    const res = await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "open_2x_1m" } }, db
    );
    const u = writes.users["u1"] as Record<string, any>;
    expect(u.tipologiaIscrizione).toBeNull();
    expect(u.entrateDisponibili).toBeNull();
    expect(u.entrateSettimanali).toBeNull();
    expect(u.fineIscrizione).toBeNull();
    expect(u.enrollmentConsumption.c1.kind).toBe("NONE");
    expect(u.enrollmentConsumption.c1.courseStartMillis).toBeDefined();
    expect(u.enrollmentConsumption.c2).toEqual({ kind: "NONE", atMillis: 2 });
    expect(u.legacySubscriptionMigration).toMatchObject({
      version: 2,
      source: "ADMIN_TRIAL_REPLACED",
      subscriptionId: res.subscriptionId,
      planKey: "open_2x_1m",
      actor: ADMIN_UID,
    });
    expect(u.subscriptionModelVersion).toBe(2);
    expect(res.replacedTrialIds).toEqual([]);
    expect(res.replacedLegacyTrial).toBe(true);
  });

  const liveV1Trial = () => ({
    tipologiaIscrizione: "ABBONAMENTO_PROVA",
    entrateDisponibili: 1,
    fineIscrizione: Timestamp.fromMillis(Date.now() + 10 * DAY),
  });

  test("Prova V1 ancora valida + PT -> failed-precondition, legacy intatto", async () => {
    const { db, writes } = makeFakeDb({ callerRole: "Admin", targetUser: liveV1Trial() });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { userId: "u1", planKey: "pt_10i_1m" } }, db),
      "failed-precondition",
    );
    expect(writes.users).toEqual({});
    expect(writes.subs).toEqual({});
  });

  test("Prova V1 ancora valida + Open che inizia dopo la scadenza -> failed-precondition", async () => {
    const { db, writes } = makeFakeDb({ callerRole: "Admin", targetUser: liveV1Trial() });
    await expectCode(
      assignSubscriptionHandler(
        { auth, data: { userId: "u1", planKey: "open_2x_1m", startDateMillis: Date.now() + 20 * DAY } },
        db,
      ),
      "failed-precondition",
    );
    expect(writes.users).toEqual({});
  });

  test("Prova V1 già scaduta + PT -> consentito, residui azzerati", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      targetUser: { ...liveV1Trial(), fineIscrizione: Timestamp.fromMillis(Date.now() - DAY) },
    });
    const res = await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "pt_10i_1m" } }, db
    );
    const u = writes.users["u1"] as Record<string, any>;
    expect(u.tipologiaIscrizione).toBeNull();
    expect(u.legacySubscriptionMigration.source).toBe("ADMIN_TRIAL_REPLACED");
    expect(res.replacedLegacyTrial).toBe(false);
  });

  test("utente già migrato con residui legacy -> residui azzerati, marker invariato", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      targetUser: {
        subscriptionModelVersion: 2,
        tipologiaIscrizione: "ABBONAMENTO_MENSILE",
        entrateSettimanali: 2,
        fineIscrizione: Timestamp.fromMillis(Date.now() - DAY),
        legacySubscriptionMigration: { version: 2, source: "BATCH" },
      },
    });
    await assignSubscriptionHandler(
      { auth, data: { userId: "u1", planKey: "open_2x_1m" } }, db
    );
    const u = writes.users["u1"] as Record<string, any>;
    expect(u.tipologiaIscrizione).toBeNull();
    expect(u.entrateSettimanali).toBeNull();
    expect(u.legacySubscriptionMigration).toBeUndefined();
  });

  test("legacy non-Prova non migrato -> ancora failed-precondition", async () => {
    const { db, writes } = makeFakeDb({
      callerRole: "Admin",
      targetUser: {
        tipologiaIscrizione: "PACCHETTO_ENTRATE",
        entrateDisponibili: 5,
      },
    });
    await expectCode(
      assignSubscriptionHandler({ auth, data: { userId: "u1", planKey: "open_2x_1m" } }, db),
      "failed-precondition",
    );
    expect(writes.users).toEqual({});
  });
});
