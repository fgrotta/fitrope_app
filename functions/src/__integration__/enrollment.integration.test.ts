// Test di INTEGRAZIONE sulle callable enrollment, eseguiti contro la Firebase
// Emulator Suite REALE (categoria C del piano §8): transazioni a 3 documenti,
// atomicità, concorrenza/contention con retry — ciò che il fake in-memory degli
// unit test non può coprire (esegue la closure una sola volta, senza conflitti).
//
// Esecuzione: `npm run test:integration` (avvia gli emulatori via
// emulators:exec su un project demo-* offline-only). NON girano con `npm test`.

import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

// emulators:exec esporta FIRESTORE_EMULATOR_HOST/FIREBASE_AUTH_EMULATOR_HOST e
// GCLOUD_PROJECT per il processo figlio: l'Admin SDK punta agli emulatori.
const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "demo-fitrope";
const FUNCTIONS_BASE = `http://127.0.0.1:5001/${PROJECT_ID}/europe-west8`;
const AUTH_BASE = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099"}`;

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: PROJECT_ID });
}
const db = admin.firestore();

const PASSWORD = "test1234";
let seq = 0;
/** Id univoci per run (i dati restano nell'emulatore tra i test della suite). */
const uniq = (prefix: string) => `${prefix}-${process.pid}-${++seq}`;

// ---------- helper ----------

async function createUser(
  uid: string,
  doc: Record<string, unknown>
): Promise<string> {
  await admin.auth().createUser({ uid, email: `${uid}@test.it`, password: PASSWORD });
  await db.collection("users").doc(uid).set({
    uid,
    email: `${uid}@test.it`,
    name: uid,
    lastName: "Test",
    role: "User",
    courses: [],
    tipologiaCorsoTags: ["Open"],
    emailNotificationsEnabled: false,
    pushNotificationsEnabled: false,
    ...doc,
  });
  const res = await fetch(
    `${AUTH_BASE}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: `${uid}@test.it`, password: PASSWORD, returnSecureToken: true }),
    }
  );
  const data = (await res.json()) as { idToken?: string };
  if (!data.idToken) throw new Error(`login emulatore fallito per ${uid}`);
  return data.idToken;
}

async function createCourse(
  uid: string,
  over: Record<string, unknown> = {}
): Promise<void> {
  const start = Date.now() + 48 * 3600 * 1000; // tra 2 giorni (fuori finestre)
  await db
    .collection("courses")
    .doc(uid)
    .set({
      id: uid,
      uid,
      name: uid,
      startDate: Timestamp.fromMillis(start),
      endDate: Timestamp.fromMillis(start + 3600 * 1000),
      capacity: 10,
      subscribed: 0,
      tags: ["Open"],
      waitlist: [],
      reminderEnabled: false,
      waitlistEnabled: true,
      ...over,
    });
}

interface CallResult {
  ok: boolean;
  status: number;
  result?: Record<string, unknown>;
  errorStatus?: string;
  errorMessage?: string;
}

async function call(
  fn: string,
  token: string,
  data: Record<string, unknown>
): Promise<CallResult> {
  const res = await fetch(`${FUNCTIONS_BASE}/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ data }),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, never>;
  return {
    ok: res.ok,
    status: res.status,
    result: body.result,
    errorStatus: body.error?.["status"],
    errorMessage: body.error?.["message"],
  };
}

const userDoc = async (uid: string) =>
  (await db.collection("users").doc(uid).get()).data() ?? {};
const courseDoc = async (uid: string) =>
  (await db.collection("courses").doc(uid).get()).data();

// ---------- suite ----------

describe("integrazione emulatore — write-path enrollment", () => {
  test("round-trip subscribe/unsubscribe legacy: transazione a 2 doc + registro consumi", async () => {
    const u = uniq("u-pack");
    const c = uniq("c-rt");
    const token = await createUser(u, {
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 5,
    });
    await createCourse(c);

    const sub = await call("subscribeToCourse", token, { courseId: c, userId: u });
    expect(sub.ok).toBe(true);

    let user = await userDoc(u);
    expect(user.entrateDisponibili).toBe(4);
    expect(user.courses).toEqual([c]);
    const consumption = user.enrollmentConsumption as Record<string, { kind: string }>;
    expect(consumption[c].kind).toBe("LEGACY_ENTRY");
    expect((await courseDoc(c))?.subscribed).toBe(1);

    const unsub = await call("unsubscribeFromCourse", token, { courseId: c, userId: u });
    expect(unsub.ok).toBe(true);

    user = await userDoc(u);
    expect(user.entrateDisponibili).toBe(5); // rimborsato
    expect(user.courses).toEqual([]);
    expect(user.enrollmentConsumption).toEqual({});
    expect((await courseDoc(c))?.subscribed).toBe(0);
  });

  test("CONCORRENZA capienza: due subscribe paralleli sull'ultimo posto → esattamente uno passa", async () => {
    const c = uniq("c-race");
    await createCourse(c, { capacity: 1 });
    const u1 = uniq("u-r1");
    const u2 = uniq("u-r2");
    const [t1, t2] = await Promise.all([
      createUser(u1, { tipologiaIscrizione: "PACCHETTO_ENTRATE", entrateDisponibili: 3 }),
      createUser(u2, { tipologiaIscrizione: "PACCHETTO_ENTRATE", entrateDisponibili: 3 }),
    ]);

    const [r1, r2] = await Promise.all([
      call("subscribeToCourse", t1, { courseId: c, userId: u1 }),
      call("subscribeToCourse", t2, { courseId: c, userId: u2 }),
    ]);

    const successes = [r1, r2].filter((r) => r.ok);
    const failures = [r1, r2].filter((r) => !r.ok);
    expect(successes).toHaveLength(1);
    expect(failures).toHaveLength(1);
    expect(failures[0].errorStatus).toBe("FAILED_PRECONDITION"); // corso al completo

    // Invarianti post-race: il contatore riflette UN solo iscritto e solo il
    // vincitore ha consumato l'entrata.
    expect((await courseDoc(c))?.subscribed).toBe(1);
    const d1 = await userDoc(u1);
    const d2 = await userDoc(u2);
    const enrolled = [d1, d2].filter((d) => (d.courses as string[]).includes(c));
    expect(enrolled).toHaveLength(1);
    expect(enrolled[0].entrateDisponibili).toBe(2);
    const loser = d1 === enrolled[0] ? d2 : d1;
    expect(loser.entrateDisponibili).toBe(3); // niente decremento per chi ha perso
  });

  test("CONCORRENZA limite settimanale: doppio tap su due corsi della stessa settimana → max 1 iscrizione", async () => {
    const u = uniq("u-weekly");
    const token = await createUser(u, {
      tipologiaIscrizione: "ABBONAMENTO_MENSILE",
      entrateSettimanali: 1,
      fineIscrizione: Timestamp.fromMillis(Date.now() + 60 * 86400 * 1000),
    });
    // Due corsi DETERMINISTICAMENTE nella stessa settimana lun-dom UTC:
    // martedì e mercoledì della settimana dopo la prossima (sempre nel futuro,
    // mai a cavallo del bordo settimana — niente flakiness da orologio).
    const d = new Date();
    const isoDow = (d.getUTCDay() + 6) % 7; // 0=lun
    const nextNextMonday = Date.UTC(
      d.getUTCFullYear(),
      d.getUTCMonth(),
      d.getUTCDate() - isoDow + 14,
      10
    );
    const ca = uniq("c-wa");
    const cb = uniq("c-wb");
    await createCourse(ca, {
      startDate: Timestamp.fromMillis(nextNextMonday + 24 * 3600 * 1000), // martedì
      endDate: Timestamp.fromMillis(nextNextMonday + 25 * 3600 * 1000),
    });
    await createCourse(cb, {
      startDate: Timestamp.fromMillis(nextNextMonday + 48 * 3600 * 1000), // mercoledì
      endDate: Timestamp.fromMillis(nextNextMonday + 49 * 3600 * 1000),
    });

    const [ra, rb] = await Promise.all([
      call("subscribeToCourse", token, { courseId: ca, userId: u }),
      call("subscribeToCourse", token, { courseId: cb, userId: u }),
    ]);

    // Era il bypass adversariale di PR4: con la valutazione in transazione le
    // richieste si serializzano sul doc utente → al più 1 iscrizione.
    const okCount = [ra, rb].filter((r) => r.ok).length;
    expect(okCount).toBe(1);
    const user = await userDoc(u);
    expect((user.courses as string[]).length).toBe(1);
  });

  test("deleteCourse atomico: rimborsi (legacy + abbonamento via registro), waitlist pulita, corso eliminato", async () => {
    const boss = uniq("u-boss");
    const bossToken = await createUser(boss, { role: "Admin" });

    const c = uniq("c-del");
    await createCourse(c, { tags: ["Hyrox"], capacity: 5 });

    // Iscritto legacy (via callable, così il registro consumi è reale).
    const uLegacy = uniq("u-dl");
    const tLegacy = await createUser(uLegacy, {
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 2,
      tipologiaCorsoTags: ["Hyrox"],
    });
    expect((await call("subscribeToCourse", tLegacy, { courseId: c, userId: uLegacy })).ok).toBe(true);

    // Iscritto nuovo modello: abbonamento Hyrox via assignSubscription + subscribe.
    const uSub = uniq("u-ds");
    const tSub = await createUser(uSub, { tipologiaCorsoTags: [] });
    const assign = await call("assignSubscription", bossToken, {
      userId: uSub,
      planKey: "hyrox_10i_3m",
    });
    expect(assign.ok).toBe(true);
    expect((await call("subscribeToCourse", tSub, { courseId: c, userId: uSub })).ok).toBe(true);
    expect(((await userDoc(uSub)).activeSubscriptions as Array<{ remainingEntries: number }>)[0]
      .remainingEntries).toBe(9);

    // Utente in waitlist (doc diretto: il corso non è pieno, basta lo stato).
    const uWait = uniq("u-dw");
    await createUser(uWait, { waitlistCourses: [c] });
    await db.collection("courses").doc(c).update({ waitlist: [uWait] });

    const del = await call("deleteCourse", bossToken, { courseId: c });
    expect(del.ok).toBe(true);
    expect(del.result).toMatchObject({ removedSubscribers: 2, removedWaitlist: 1 });

    expect(await courseDoc(c)).toBeUndefined();
    expect((await userDoc(uLegacy)).entrateDisponibili).toBe(2); // 2→1 (subscribe)→2 (rimborso)
    const subUser = await userDoc(uSub);
    expect((subUser.activeSubscriptions as Array<{ remainingEntries: number }>)[0]
      .remainingEntries).toBe(10); // 10→9→10
    expect((await userDoc(uWait)).waitlistCourses).toEqual([]);
  });

  test("recountCourseSubscribed: corregge un contatore gonfio dalla fonte di verità", async () => {
    const boss = uniq("u-boss2");
    const bossToken = await createUser(boss, { role: "Admin" });
    const c = uniq("c-rec");
    await createCourse(c, { subscribed: 7 }); // gonfio, nessun iscritto reale

    const u = uniq("u-rec");
    const t = await createUser(u, {
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 1,
    });
    expect((await call("subscribeToCourse", t, { courseId: c, userId: u })).ok).toBe(true);
    expect((await courseDoc(c))?.subscribed).toBe(8); // ancora sbagliato (7+1)

    const rec = await call("recountCourseSubscribed", bossToken, { courseId: c });
    expect(rec.ok).toBe(true);
    expect(rec.result).toMatchObject({ subscribed: 1 });
    expect((await courseDoc(c))?.subscribed).toBe(1);
  });

  test("authz reale: utente normale non può cancellare corsi né ricontare", async () => {
    const u = uniq("u-noauth");
    const t = await createUser(u, {});
    const c = uniq("c-noauth");
    await createCourse(c);

    const del = await call("deleteCourse", t, { courseId: c });
    expect(del.ok).toBe(false);
    expect(del.errorStatus).toBe("PERMISSION_DENIED");
    const rec = await call("recountCourseSubscribed", t, { courseId: c });
    expect(rec.errorStatus).toBe("PERMISSION_DENIED");
  });

  test("ADMIN rimuove un altro utente entro finestra: rimborso comunque (regola admin-rimborsa-sempre)", async () => {
    const boss = uniq("u-boss3");
    const bossToken = await createUser(boss, { role: "Admin" });
    const u = uniq("u-rm");
    const t = await createUser(u, {
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 3,
    });
    // Corso tra 2 ore: DENTRO la finestra 8h.
    const c = uniq("c-rm");
    await createCourse(c, {
      startDate: Timestamp.fromMillis(Date.now() + 2 * 3600 * 1000),
      endDate: Timestamp.fromMillis(Date.now() + 3 * 3600 * 1000),
    });
    expect((await call("subscribeToCourse", t, { courseId: c, userId: u })).ok).toBe(true);
    expect((await userDoc(u)).entrateDisponibili).toBe(2);

    // L'admin lo rimuove passando perfino confirmedNoRefund: ignorato.
    const rm = await call("unsubscribeFromCourse", bossToken, {
      courseId: c,
      userId: u,
      confirmedNoRefund: true,
    });
    expect(rm.ok).toBe(true);
    const after = await userDoc(u);
    expect(after.entrateDisponibili).toBe(3); // rimborsato
    expect(after.courses).toEqual([]);
    expect(after.cancelledEnrollments ?? []).toEqual([]); // nessun tracking admin
  });
});
