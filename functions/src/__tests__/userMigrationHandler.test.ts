import { Timestamp } from "firebase-admin/firestore";
import {
  migrateLegacyUserHandler,
  previewLegacyUserMigrationHandler,
} from "../migration/userHandler";
import { addMonthsInRome } from "../migration/userTransform";

const ADMIN = "admin";
const USER = "user-1";

function legacyUser(extra: Record<string, unknown> = {}) {
  return {
    uid: USER,
    role: "User",
    tipologiaCorsoTags: ["Open"],
    tipologiaIscrizione: "ABBONAMENTO_MENSILE",
    entrateDisponibili: null,
    entrateSettimanali: 2,
    fineIscrizione: Timestamp.fromMillis(Date.now() + 15 * 86400000),
    ...extra,
  };
}

function makeDb(options: {
  adminRole?: string;
  user?: Record<string, unknown>;
  subscriptions?: Record<string, Record<string, unknown>>;
}) {
  const users: Record<string, Record<string, unknown>> = {
    [ADMIN]: { role: options.adminRole ?? "Admin" },
    [USER]: options.user ?? legacyUser(),
  };
  const subscriptions = { ...(options.subscriptions ?? {}) };

  const userDoc = (id: string) => ({ _kind: "user", id });
  const subDoc = (id: string) => ({ _kind: "subscription", id });
  const subQuery = (userId: string) => ({ _kind: "subscriptionQuery", userId });
  const snapshot = (value: Record<string, unknown> | undefined) => ({
    exists: value !== undefined,
    data: () => value,
  });
  const querySnapshot = (userId: string) => ({
    docs: Object.entries(subscriptions)
      .filter(([, data]) => data.userId === userId)
      .map(([id, data]) => ({ id, data: () => data })),
  });

  const read = async (ref: any) => {
    if (ref._kind === "user") return snapshot(users[ref.id]);
    if (ref._kind === "subscription") return snapshot(subscriptions[ref.id]);
    return querySnapshot(ref.userId);
  };

  const db: any = {
    collection(name: string) {
      if (name === "users") {
        return {
          doc: (id: string) => ({
            ...userDoc(id),
            get: () => read(userDoc(id)),
          }),
        };
      }
      if (name === "subscriptions") {
        return {
          doc: (id: string) => subDoc(id),
          where: (_field: string, _op: string, userId: string) => ({
            ...subQuery(userId),
            get: async () => querySnapshot(userId),
          }),
        };
      }
      throw new Error(`collection inattesa: ${name}`);
    },
    runTransaction: async (callback: (tx: any) => Promise<unknown>) =>
      callback({
        get: read,
        create: (
          ref: ReturnType<typeof subDoc>,
          data: Record<string, unknown>,
        ) => {
          if (subscriptions[ref.id]) throw new Error("already exists");
          subscriptions[ref.id] = data;
        },
        update: (
          ref: ReturnType<typeof userDoc>,
          patch: Record<string, unknown>,
        ) => {
          users[ref.id] = { ...users[ref.id], ...patch };
        },
      }),
  };
  return { db, users, subscriptions };
}

async function preview(db: any) {
  return previewLegacyUserMigrationHandler(
    { auth: { uid: ADMIN }, data: { userId: USER } },
    db,
  );
}

describe("migrazione puntuale utente legacy", () => {
  test("richiede autenticazione e ruolo Admin", async () => {
    const { db } = makeDb({});
    await expect(
      previewLegacyUserMigrationHandler(
        { auth: null, data: { userId: USER } },
        db,
      ),
    ).rejects.toMatchObject({ code: "unauthenticated" });
    const nonAdmin = makeDb({ adminRole: "Trainer" });
    await expect(preview(nonAdmin.db)).rejects.toMatchObject({
      code: "permission-denied",
    });
  });

  test("classifica correttamente automatico, manuale e non applicabile", async () => {
    expect(await preview(makeDb({}).db)).toMatchObject({
      status: "AUTO_CONVERTIBLE",
      target: { planKey: "open_2x_1m" },
    });
    const manual = makeDb({
      user: legacyUser({ tipologiaIscrizione: "PACCHETTO_ENTRATE" }),
    });
    expect(await preview(manual.db)).toMatchObject({
      status: "MANUAL_REQUIRED",
    });
    const trainer = makeDb({ user: legacyUser({ role: "Trainer" }) });
    expect(await preview(trainer.db)).toMatchObject({
      status: "NOT_APPLICABLE",
    });
  });

  test("la preview segnala conflitto per la famiglia automatica", async () => {
    const { db } = makeDb({
      subscriptions: {
        existing: { userId: USER, family: "OPEN" },
      },
    });
    expect(await preview(db)).toMatchObject({
      status: "CONFLICT",
      reasonCode: "EXISTING_SUBSCRIPTION_CONFLICT",
    });
  });

  test("AUTO crea subscription, snapshot e marker condiviso", async () => {
    const state = makeDb({});
    const before = await preview(state.db);
    const result = await migrateLegacyUserHandler(
      {
        auth: { uid: ADMIN },
        data: {
          userId: USER,
          mode: "AUTO",
          expectedFingerprint: before.expectedFingerprint,
        },
      },
      state.db,
    );
    expect(result).toMatchObject({ status: "MIGRATED" });
    expect(Object.keys(state.subscriptions)).toHaveLength(1);
    expect(state.users[USER].activeSubscriptions).toEqual(
      expect.arrayContaining([expect.objectContaining({ family: "OPEN" })]),
    );
    expect(state.users[USER].legacySubscriptionMigration).toEqual(
      expect.objectContaining({
        version: 1,
        source: "ADMIN_AUTO",
        planKey: "open_2x_1m",
        actor: ADMIN,
      }),
    );

    const repeated = await migrateLegacyUserHandler(
      {
        auth: { uid: ADMIN },
        data: {
          userId: USER,
          mode: "AUTO",
          expectedFingerprint: before.expectedFingerprint,
        },
      },
      state.db,
    );
    expect(repeated).toEqual({ status: "MIGRATED", alreadyApplied: true });
  });

  test("GUIDED valida durata Europe/Rome e credito ENTRIES", async () => {
    const state = makeDb({
      user: legacyUser({ tipologiaIscrizione: "PACCHETTO_ENTRATE" }),
    });
    const before = await preview(state.db);
    const start = Date.parse("2026-01-31T17:00:00.000Z");
    const end = addMonthsInRome(start, 1);
    await migrateLegacyUserHandler(
      {
        auth: { uid: ADMIN },
        data: {
          userId: USER,
          mode: "GUIDED",
          expectedFingerprint: before.expectedFingerprint,
          target: {
            planKey: "pt_10i_1m",
            startDateMillis: start,
            endDateMillis: end,
            remainingEntries: 7,
          },
        },
      },
      state.db,
    );
    expect(Object.values(state.subscriptions)[0]).toEqual(
      expect.objectContaining({ family: "PT", remainingEntries: 7 }),
    );
  });

  test("rifiuta durata guidata errata e source drift", async () => {
    const state = makeDb({
      user: legacyUser({ tipologiaIscrizione: "PACCHETTO_ENTRATE" }),
    });
    const before = await preview(state.db);
    const base = {
      userId: USER,
      mode: "GUIDED",
      expectedFingerprint: before.expectedFingerprint,
      target: {
        planKey: "open_10i_1m",
        startDateMillis: Date.parse("2026-01-01T17:00:00.000Z"),
        endDateMillis: Date.parse("2026-01-15T17:00:00.000Z"),
        remainingEntries: 4,
      },
    };
    await expect(
      migrateLegacyUserHandler({ auth: { uid: ADMIN }, data: base }, state.db),
    ).rejects.toMatchObject({ code: "invalid-argument" });
    state.users[USER].entrateDisponibili = 3;
    await expect(
      migrateLegacyUserHandler(
        {
          auth: { uid: ADMIN },
          data: {
            ...base,
            target: {
              ...base.target,
              endDateMillis: addMonthsInRome(base.target.startDateMillis, 1),
            },
          },
        },
        state.db,
      ),
    ).rejects.toMatchObject({ code: "aborted" });
  });
});
