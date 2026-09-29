import { Timestamp } from "firebase-admin/firestore";
import {
  revokeSubscriptionHandler,
  updateSubscriptionHandler,
} from "../enrollment/manageSubscription";
import { FakeStore, makeDb } from "./helpers/fakeDb";

const DAY = 86400000;
const NOW = Date.UTC(2026, 8, 28, 10);
const ADMIN = "admin-uid";
const auth = { uid: ADMIN };

function sub(planKey: string, startMillis: number, endMillis: number, extra: Record<string, unknown> = {}) {
  const entries = planKey === "open_trial_1i_30d" ? 1 : planKey.includes("_10i_") ? 10 : null;
  const family = planKey.startsWith("pt_") ? "PT" : "OPEN";
  return {
    userId: "u1",
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

function makeStore(subs: Record<string, Record<string, unknown>>, role = "Admin"): FakeStore {
  return {
    users: {
      [ADMIN]: { role },
      u1: { uid: "u1", role: "User", subscriptionModelVersion: 2, activeSubscriptions: [] },
    },
    courses: {},
    subs,
  };
}

const window = { startDateMillis: NOW - DAY, endDateMillis: NOW + 30 * DAY };

async function expectCode(p: Promise<unknown>, code: string) {
  await expect(p).rejects.toMatchObject({ code });
}

describe("updateSubscriptionHandler", () => {
  test("non autenticato -> unauthenticated", async () => {
    const store = makeStore({ s1: sub("open_2x_1m", NOW - DAY, NOW + DAY) });
    await expectCode(updateSubscriptionHandler(
      { auth: null, data: { subscriptionId: "s1", planKey: "open_2x_1m", ...window } },
      makeDb(store), NOW), "unauthenticated");
  });

  test("non Admin -> permission-denied", async () => {
    const store = makeStore({ s1: sub("open_2x_1m", NOW - DAY, NOW + DAY) }, "Trainer");
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_2x_1m", ...window } },
      makeDb(store), NOW), "permission-denied");
  });

  test("abbonamento inesistente -> not-found", async () => {
    const store = makeStore({});
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "nope", planKey: "open_2x_1m", ...window } },
      makeDb(store), NOW), "not-found");
  });

  test("abbonamento revocato -> failed-precondition", async () => {
    const store = makeStore({
      s1: sub("open_2x_1m", NOW - DAY, NOW + DAY, { revokedAt: Timestamp.fromMillis(NOW) }),
    });
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_2x_1m", ...window } },
      makeDb(store), NOW), "failed-precondition");
  });

  test.each([
    ["fine prima dell'inizio", NOW, NOW - DAY],
    ["NaN", NaN, NOW],
    ["mancanti", undefined, undefined],
  ])("finestra non valida (%s) -> invalid-argument", async (_l, s, e) => {
    const store = makeStore({ s1: sub("open_2x_1m", NOW - DAY, NOW + DAY) });
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_2x_1m", startDateMillis: s, endDateMillis: e } },
      makeDb(store), NOW), "invalid-argument");
  });

  test("sovrapposizione sulla nuova famiglia -> already-exists", async () => {
    const store = makeStore({
      s1: sub("open_2x_1m", NOW - DAY, NOW + DAY),
      s2: sub("pt_10i_1m", NOW - DAY, NOW + 20 * DAY),
    });
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "pt_10i_3m", ...window, remainingEntries: 10 } },
      makeDb(store), NOW), "already-exists");
  });

  test("una Prova sovrapposta resta un errore (nessuna chiusura automatica)", async () => {
    const store = makeStore({
      s1: sub("open_2x_1m", NOW - 60 * DAY, NOW - 31 * DAY),
      trial: sub("open_trial_1i_30d", NOW - DAY, NOW + 29 * DAY),
    });
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_2x_1m", ...window } },
      makeDb(store), NOW), "already-exists");
    expect(store.subs.trial.revokedAt).toBeUndefined();
  });

  test.each([
    ["negativi", -1],
    ["oltre il massimo", 11],
    ["non interi", 2.5],
    ["mancanti", undefined],
  ])("ingressi %s -> invalid-argument", async (_l, remaining) => {
    const store = makeStore({ s1: sub("open_10i_1m", NOW - DAY, NOW + DAY) });
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_10i_1m", ...window, remainingEntries: remaining } },
      makeDb(store), NOW), "invalid-argument");
  });

  test("Prova come piano di destinazione -> invalid-argument", async () => {
    const store = makeStore({ s1: sub("open_2x_1m", NOW - DAY, NOW + DAY) });
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_trial_1i_30d", ...window, remainingEntries: 1 } },
      makeDb(store), NOW), "invalid-argument");
  });

  test("ENTRIES -> FREQUENCY: ingressi a null, campi dal nuovo piano", async () => {
    const store = makeStore({ s1: sub("open_10i_1m", NOW - DAY, NOW + DAY, { remainingEntries: 4 }) });
    await updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_3x_3m", ...window, remainingEntries: 7 } },
      makeDb(store), NOW);
    const s = store.subs.s1 as Record<string, any>;
    expect(s.planKey).toBe("open_3x_3m");
    expect(s.billingMode).toBe("FREQUENCY");
    expect(s.weeklyFrequency).toBe(3);
    expect(s.remainingEntries).toBeNull();
    expect(s.startDate.toMillis()).toBe(window.startDateMillis);
    expect(s.endDate.toMillis()).toBe(window.endDateMillis);
  });

  test("FREQUENCY -> ENTRIES: ingressi obbligatori e salvati", async () => {
    const store = makeStore({ s1: sub("open_2x_1m", NOW - DAY, NOW + DAY) });
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_10i_1m", ...window } },
      makeDb(store), NOW), "invalid-argument");
    await updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_10i_1m", ...window, remainingEntries: 0 } },
      makeDb(store), NOW);
    const s = store.subs.s1 as Record<string, any>;
    expect(s.billingMode).toBe("ENTRIES");
    expect(s.weeklyFrequency).toBeNull();
    expect(s.remainingEntries).toBe(0);
  });

  test("cambio famiglia Open -> PT", async () => {
    const store = makeStore({ s1: sub("open_2x_1m", NOW - DAY, NOW + DAY) });
    await updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "pt_10i_1m", ...window, remainingEntries: 10 } },
      makeDb(store), NOW);
    const s = store.subs.s1 as Record<string, any>;
    expect(s.family).toBe("PT");
    expect(s.courseTypeTags).toEqual(["Personal Trainer"]);
  });

  test("Prova convertita in abbonamento normale", async () => {
    const store = makeStore({ trial: sub("open_trial_1i_30d", NOW - DAY, NOW + 29 * DAY) });
    await updateSubscriptionHandler(
      { auth, data: { subscriptionId: "trial", planKey: "open_10i_1m", ...window, remainingEntries: 10 } },
      makeDb(store), NOW);
    expect(store.subs.trial.planKey).toBe("open_10i_1m");
    const snap = store.users.u1.activeSubscriptions as Array<Record<string, unknown>>;
    expect(snap.map((e) => e.planKey)).toEqual(["open_10i_1m"]);
  });

  test("ingressi cambiati nel frattempo (expectedRemainingEntries) -> aborted, nessuna scrittura", async () => {
    const store = makeStore({ s1: sub("open_10i_1m", NOW - DAY, NOW + DAY, { remainingEntries: 4 }) });
    const before = JSON.stringify(store);
    await expectCode(updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_10i_1m", ...window, remainingEntries: 5, expectedRemainingEntries: 5 } },
      makeDb(store), NOW), "aborted");
    expect(JSON.stringify(store)).toBe(before);

    await updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_10i_1m", ...window, remainingEntries: 6, expectedRemainingEntries: 4 } },
      makeDb(store), NOW);
    expect(store.subs.s1.remainingEntries).toBe(6);
  });

  test("voce editHistory con lo stato precedente, accodata", async () => {
    const store = makeStore({
      s1: sub("open_10i_1m", NOW - DAY, NOW + DAY, {
        remainingEntries: 4,
        editHistory: [{ at: Timestamp.fromMillis(1), by: "x", before: {} }],
      }),
    });
    await updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_10i_1m", ...window, remainingEntries: 8 } },
      makeDb(store), NOW);
    const s = store.subs.s1 as Record<string, any>;
    expect(s.updatedBy).toBe(ADMIN);
    expect(s.updatedAt.toMillis()).toBe(NOW);
    expect(s.editHistory).toHaveLength(2);
    const entry = s.editHistory[1];
    expect(entry.by).toBe(ADMIN);
    expect(entry.at.toMillis()).toBe(NOW);
    expect(entry.before.planKey).toBe("open_10i_1m");
    expect(entry.before.remainingEntries).toBe(4);
    expect(entry.before.startDate.toMillis()).toBe(NOW - DAY);
    expect(entry.before.endDate.toMillis()).toBe(NOW + DAY);
  });

  test("ricalcolo snapshot con gli altri abbonamenti", async () => {
    const store = makeStore({
      s1: sub("open_10i_1m", NOW - DAY, NOW + DAY),
      p1: sub("pt_10i_1m", NOW - DAY, NOW + DAY),
      old: sub("open_2x_1m", NOW - 90 * DAY, NOW - 60 * DAY),
    });
    await updateSubscriptionHandler(
      { auth, data: { subscriptionId: "s1", planKey: "open_10i_1m", ...window, remainingEntries: 3 } },
      makeDb(store), NOW);
    const snap = store.users.u1.activeSubscriptions as Array<Record<string, unknown>>;
    expect(snap.map((e) => e.id).sort()).toEqual(["p1", "s1"]);
    expect(snap.find((e) => e.id === "s1")!.remainingEntries).toBe(3);
  });

  test("modifica di uno scaduto: rientra nello snapshot se la nuova fine è futura", async () => {
    const store = makeStore({ old: sub("open_2x_1m", NOW - 90 * DAY, NOW - 60 * DAY) });
    await updateSubscriptionHandler(
      { auth, data: { subscriptionId: "old", planKey: "open_2x_1m", startDateMillis: NOW - 90 * DAY, endDateMillis: NOW + DAY } },
      makeDb(store), NOW);
    const snap = store.users.u1.activeSubscriptions as Array<Record<string, unknown>>;
    expect(snap.map((e) => e.id)).toEqual(["old"]);
  });
});

describe("revokeSubscriptionHandler", () => {
  test("non Admin -> permission-denied", async () => {
    const store = makeStore({ s1: sub("open_2x_1m", NOW - DAY, NOW + DAY) }, "User");
    await expectCode(revokeSubscriptionHandler(
      { auth, data: { subscriptionId: "s1" } }, makeDb(store), NOW), "permission-denied");
  });

  test("inesistente -> not-found", async () => {
    const store = makeStore({});
    await expectCode(revokeSubscriptionHandler(
      { auth, data: { subscriptionId: "s1" } }, makeDb(store), NOW), "not-found");
  });

  test("revoca: storico conservato e snapshot ricalcolato", async () => {
    const store = makeStore({
      s1: sub("open_2x_1m", NOW - DAY, NOW + DAY),
      p1: sub("pt_10i_1m", NOW - DAY, NOW + DAY),
    });
    const res = await revokeSubscriptionHandler(
      { auth, data: { subscriptionId: "s1" } }, makeDb(store), NOW);
    expect(res.alreadyRevoked).toBe(false);
    const s = store.subs.s1 as Record<string, any>;
    expect(s.revokedAt.toMillis()).toBe(NOW);
    expect(s.revokedBy).toBe(ADMIN);
    expect(s.revokedReason).toBe("ADMIN");
    expect(s.planKey).toBe("open_2x_1m");
    const snap = store.users.u1.activeSubscriptions as Array<Record<string, unknown>>;
    expect(snap.map((e) => e.id)).toEqual(["p1"]);
  });

  test("idempotente: già revocato -> alreadyRevoked, nessuna scrittura", async () => {
    const revokedAt = Timestamp.fromMillis(NOW - DAY);
    const store = makeStore({
      s1: sub("open_2x_1m", NOW - DAY, NOW + DAY, { revokedAt, revokedReason: "ADMIN" }),
    });
    const before = JSON.stringify(store);
    const res = await revokeSubscriptionHandler(
      { auth, data: { subscriptionId: "s1" } }, makeDb(store), NOW);
    expect(res.alreadyRevoked).toBe(true);
    expect(JSON.stringify(store)).toBe(before);
  });
});
