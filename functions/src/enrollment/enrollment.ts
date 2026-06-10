// Handler server-authoritative per il dominio iscrizioni (port di
// lib/api/courses/{subscribeToCourse,unsubscribeToCourse,joinWaitlist,leaveWaitlist}.dart).
//
// Tutto in transazione Firestore (letture prima delle scritture). La logica di
// idoneità/rimborso è nei moduli puri eligibility.ts / refund.ts (mirror di
// getCourseState.dart / CourseUnsubscribeHelper). Le notifiche (best-effort) sono
// iniettabili tramite `deps`, così i test non toccano la rete.

import { HttpsError, FunctionsErrorCode } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
// Import modulare: nel runtime dell'emulatore functions il namespace
// `admin.firestore` è patchato e PERDE le proprietà statiche (Timestamp,
// FieldValue) → vanno importate da "firebase-admin/firestore" (bug trovato
// dallo smoke test sull'emulatore, vedi docs/AMBIENTI_DI_TEST.md).
import { Timestamp } from "firebase-admin/firestore";
import { planByKey } from "./plansCatalog";
import {
  UserSubscriptionRecord,
  recordFromDoc,
  recordToSnapshotEntry,
  computeActiveSnapshot,
} from "./subscription";
import { primaryTypeTagForTags } from "./courseTypes";
import {
  evaluateSubscribe,
  coveringSubsByType,
  validAtDate,
  countWeeklyEntries,
  weekBoundsMillis,
  EnrolledCourse,
  CancelledRecord,
  SubscribeReason,
} from "./eligibility";
import { decideRefund, CreditMode } from "./refund";

type Firestore = admin.firestore.Firestore;
type FsData = admin.firestore.DocumentData;
type DocRef = admin.firestore.DocumentReference;
type Transaction = admin.firestore.Transaction;

export interface EnrollmentRequest {
  auth?: { uid: string } | null;
  data: unknown;
}

/** Notifiche best-effort, iniettabili (no-op nei test). */
export interface EnrollmentDeps {
  notifyTrialReminder?: (userId: string, courseId: string) => Promise<void>;
  notifyWaitlist?: (courseId: string) => Promise<void>;
}

const ADMIN_ROLES = new Set(["Admin", "Trainer"]);

function requireAuthUid(request: EnrollmentRequest): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login richiesto");
  return request.auth.uid;
}

function asObject(data: unknown): Record<string, unknown> {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Body mancante o invalido");
  }
  return data as Record<string, unknown>;
}

function requireString(v: unknown, field: string): string {
  if (typeof v !== "string" || v.length === 0) {
    throw new HttpsError("invalid-argument", `${field} è richiesto`);
  }
  return v;
}

/** Trova il documento corso per campo `uid` (come il client). */
async function getCourseDoc(
  tx: Transaction,
  db: Firestore,
  courseId: string
): Promise<{ ref: DocRef; data: FsData }> {
  const snap = await tx.get(
    db.collection("courses").where("uid", "==", courseId).limit(1)
  );
  if (snap.empty) {
    throw new HttpsError("not-found", `Corso ${courseId} inesistente`);
  }
  const doc = snap.docs[0];
  return { ref: doc.ref, data: doc.data() };
}

async function getRole(tx: Transaction, db: Firestore, uid: string): Promise<string | null> {
  const snap = await tx.get(db.collection("users").doc(uid));
  return snap.exists ? (snap.data()?.role as string | null) ?? null : null;
}

function snapshotRecords(userData: FsData): UserSubscriptionRecord[] {
  const raw = userData.activeSubscriptions;
  if (!Array.isArray(raw)) return [];
  return raw.map((e: FsData) => recordFromDoc((e.id as string) ?? "", e));
}

function toMillis(ts: unknown): number {
  if (ts && typeof (ts as { toMillis?: () => number }).toMillis === "function") {
    return (ts as { toMillis: () => number }).toMillis();
  }
  return 0;
}

const REASON_TO_HTTP: Record<
  Exclude<SubscribeReason, "OK">,
  { code: FunctionsErrorCode; msg: string }
> = {
  ALREADY_SUBSCRIBED: { code: "already-exists", msg: "Sei già iscritto a questo corso" },
  NO_ACCESS: { code: "permission-denied", msg: "Non hai accesso a questo corso" },
  FULL: { code: "failed-precondition", msg: "Il corso è al completo" },
  EXPIRED: { code: "failed-precondition", msg: "Abbonamento scaduto per questo corso" },
  NO_ENTRIES: { code: "failed-precondition", msg: "Ingressi esauriti" },
  WEEKLY_LIMIT: { code: "failed-precondition", msg: "Limite settimanale raggiunto" },
  NOT_ELIGIBLE: { code: "failed-precondition", msg: "Nessun abbonamento valido per questo corso" },
};

/** Voce del catalogo dei corsi della settimana (dati immutabili-ish del corso). */
interface WeekCatalogEntry {
  uid: string;
  startMillis: number;
  primaryTag: string;
}

/**
 * Catalogo dei corsi della settimana del corso target (range query su startDate).
 * Letto FUORI transazione: è catalogo (esistenza/orario/tag dei corsi), non stato
 * dell'utente. Il conteggio settimanale viene poi calcolato DENTRO la transazione
 * con il doc utente fresco ([weeklyUsedFromCatalog]), così richieste concorrenti
 * dello stesso utente si serializzano sul suo doc e non bypassano il limite.
 */
interface WeekCatalog {
  byUid: Map<string, WeekCatalogEntry>;
  /** Bordi della settimana coperta dal catalogo (per la verifica in transazione). */
  weekStart: number;
  weekEnd: number;
}

async function fetchWeekCatalog(
  db: Firestore,
  courseStartMillis: number
): Promise<WeekCatalog> {
  const { start: weekStart, end: weekEnd } = weekBoundsMillis(courseStartMillis);

  const snap = await db
    .collection("courses")
    .where("startDate", ">=", Timestamp.fromMillis(weekStart))
    .where("startDate", "<=", Timestamp.fromMillis(weekEnd))
    .get();

  const byUid = new Map<string, WeekCatalogEntry>();
  for (const doc of snap.docs) {
    const c = doc.data();
    const uid = (c.uid as string) ?? doc.id;
    const tags = Array.isArray(c.tags) ? (c.tags as string[]) : [];
    byUid.set(uid, {
      uid,
      startMillis: toMillis(c.startDate),
      primaryTag: primaryTypeTagForTags(tags),
    });
  }
  return { byUid, weekStart, weekEnd };
}

/**
 * Ingressi settimanali usati: corsi iscritti ([userCourses], dal doc utente
 * LETTO IN TRANSAZIONE) + disiscrizioni perse, nello scope [typeTags]
 * (null = globale, legacy temporale).
 */
function weeklyUsedFromCatalog(
  catalog: WeekCatalog,
  courseStartMillis: number,
  userCourses: string[],
  cancelledRaw: FsData[],
  typeTags: Set<string> | null
): number {
  const enrolled: EnrolledCourse[] = [];
  for (const id of userCourses) {
    const entry = catalog.byUid.get(id);
    if (entry) {
      enrolled.push({
        uid: entry.uid,
        startMillis: entry.startMillis,
        primaryTag: entry.primaryTag,
      });
    }
  }

  const cancelled: CancelledRecord[] = cancelledRaw.map((c) => ({
    entryLost: c.entryLost === true,
    courseStartMillis: toMillis(c.courseStartDate),
    primaryTag: catalog.byUid.get((c.courseId as string) ?? "")?.primaryTag ?? null,
  }));

  return countWeeklyEntries(courseStartMillis, enrolled, cancelled, typeTags);
}

/**
 * Registro consumi per prenotazione (campo `enrollmentConsumption` sul doc
 * utente, mappa courseId → {kind, subscriptionId?}). Scritto allo subscribe con
 * ciò che è stato REALMENTE scalato, letto e ripulito all'unsubscribe: così il
 * rimborso ripristina la fonte effettivamente consumata anche se nel frattempo
 * il modello dell'utente è cambiato (es. admin ha assegnato un abbonamento dopo
 * una prenotazione legacy), e un force-subscribe che non ha scalato nulla non
 * genera mai un rimborso (kind NONE).
 */
interface ConsumptionRecord {
  kind: "NONE" | "LEGACY_ENTRY" | "SUBSCRIPTION_ENTRY";
  subscriptionId?: string | null;
}

function readConsumption(user: FsData): Record<string, ConsumptionRecord> {
  const raw = user.enrollmentConsumption;
  return raw && typeof raw === "object" ? { ...(raw as Record<string, ConsumptionRecord>) } : {};
}

// ──────────────────────────────────────────────
//  subscribeToCourse
// ──────────────────────────────────────────────

export async function subscribeToCourseHandler(
  request: EnrollmentRequest,
  db: Firestore,
  deps: EnrollmentDeps = {},
  nowMillis: number = Date.now()
): Promise<Record<string, unknown>> {
  const actor = requireAuthUid(request);
  const data = asObject(request.data);
  const courseId = requireString(data.courseId, "courseId");
  const targetUserId = requireString(data.userId, "userId");
  const wantsForce = data.force === true;

  // Pre-fase (fuori transazione): SOLO catalogo — la data del corso per i bordi
  // settimana e i corsi della settimana (esistenza/orario/tag, dati che non
  // cambiano concorrentemente in modo rilevante). Tutto lo STATO (corso, utente,
  // abbonamenti) viene letto e valutato dentro la transazione.
  const coursePreSnap = await db
    .collection("courses")
    .where("uid", "==", courseId)
    .limit(1)
    .get();
  if (coursePreSnap.empty) {
    throw new HttpsError("not-found", `Corso ${courseId} inesistente`);
  }
  const weekCatalog = await fetchWeekCatalog(
    db,
    toMillis(coursePreSnap.docs[0].data().startDate)
  );

  let isTrialUser = false;

  await db.runTransaction(async (tx) => {
    // ----- letture (tutte prima delle scritture) -----
    const course = await getCourseDoc(tx, db, courseId);
    const actorRef = db.collection("users").doc(actor);
    const userRef = db.collection("users").doc(targetUserId);

    const actorTxSnap = await tx.get(actorRef);
    const actorRole = actorTxSnap.exists
      ? ((actorTxSnap.data() as FsData)?.role as string | null) ?? null
      : null;
    const isPrivileged = actorRole !== null && ADMIN_ROLES.has(actorRole);

    if (targetUserId === actor) {
      if (isPrivileged) {
        throw new HttpsError("permission-denied", "Admin e Trainer non possono iscriversi ai corsi");
      }
    } else if (!isPrivileged) {
      throw new HttpsError("permission-denied", "Non puoi iscrivere un altro utente");
    }
    const force = wantsForce && isPrivileged;

    const userTxSnap =
      targetUserId === actor ? actorTxSnap : await tx.get(userRef);
    if (!userTxSnap.exists) throw new HttpsError("not-found", "Utente inesistente");
    const user = userTxSnap.data() as FsData;

    const courseStartMillis = toMillis(course.data.startDate);
    const courseTags = Array.isArray(course.data.tags) ? (course.data.tags as string[]) : [];
    const coursePrimaryTag = primaryTypeTagForTags(courseTags);

    // Corso già iniziato/passato → CLOSED (mirror del primo gate di
    // getCourseState). Force admin può comunque registrare presenze a posteriori.
    if (courseStartMillis <= nowMillis && !force) {
      throw new HttpsError("failed-precondition", "Il corso è già iniziato");
    }

    const records = snapshotRecords(user);
    const liveRecords = records.filter((r) => r.endDateMillis >= nowMillis);
    const userCourses: string[] = Array.isArray(user.courses) ? (user.courses as string[]) : [];
    const cancelledRaw: FsData[] = Array.isArray(user.cancelledEnrollments)
      ? (user.cancelledEnrollments as FsData[])
      : [];

    // Abbonamenti dalla collezione (fonte di verità): letti se lo snapshot è
    // vivo, sia per validare/decrementare gli ingressi sia per riscrivere lo
    // snapshot. (Lettura PRIMA delle scritture, requisito Firestore.)
    let txRecords: UserSubscriptionRecord[] = [];
    const subRefById = new Map<string, DocRef>();
    if (liveRecords.length > 0) {
      const subsSnap = await tx.get(
        db.collection("subscriptions").where("userId", "==", targetUserId)
      );
      txRecords = subsSnap.docs.map((d) => {
        subRefById.set(d.id, d.ref);
        return recordFromDoc(d.id, d.data());
      });
    }

    // Il catalogo settimana è stato letto fuori transazione sulla startDate
    // pre-letta: se nel frattempo il corso è stato spostato in un'ALTRA
    // settimana, il catalogo non corrisponde → abort (il client può ritentare).
    if (
      courseStartMillis < weekCatalog.weekStart ||
      courseStartMillis > weekCatalog.weekEnd
    ) {
      throw new HttpsError(
        "aborted",
        "Il corso è stato riprogrammato: riprova l'iscrizione"
      );
    }

    // Conteggio settimanale DENTRO la transazione, con il doc utente fresco:
    // richieste concorrenti dello stesso utente si serializzano sul suo doc,
    // quindi il limite non è bypassabile con doppi tap / device paralleli.
    let weeklyUsed = 0;
    if (liveRecords.length > 0) {
      const valid = validAtDate(
        coveringSubsByType(liveRecords, coursePrimaryTag),
        courseStartMillis
      );
      const freqSub = valid.find(
        (s) => s.billingMode === "FREQUENCY" && s.weeklyFrequency !== null
      );
      if (freqSub) {
        const tags = new Set<string>();
        valid
          .filter((s) => s.billingMode === "FREQUENCY")
          .forEach((s) => s.courseTypeTags.forEach((t) => tags.add(t)));
        weeklyUsed = weeklyUsedFromCatalog(
          weekCatalog,
          courseStartMillis,
          userCourses,
          cancelledRaw,
          tags
        );
      }
    } else {
      const tip = (user.tipologiaIscrizione as string | null) ?? null;
      const temporal =
        tip !== null && tip.startsWith("ABBONAMENTO_") && tip !== "ABBONAMENTO_PROVA";
      if (temporal && user.entrateSettimanali != null) {
        weeklyUsed = weeklyUsedFromCatalog(
          weekCatalog,
          courseStartMillis,
          userCourses,
          cancelledRaw,
          null
        );
      }
    }

    const decision = evaluateSubscribe({
      force,
      alreadySubscribed: userCourses.includes(courseId),
      courseFull:
        ((course.data.subscribed as number) ?? 0) >= ((course.data.capacity as number) ?? 0),
      userTags: Array.isArray(user.tipologiaCorsoTags)
        ? (user.tipologiaCorsoTags as string[])
        : [],
      courseTags,
      coursePrimaryTag,
      courseStartMillis,
      nowMillis,
      activeSubscriptions: records,
      tipologia: (user.tipologiaIscrizione as string | null) ?? null,
      entrateDisponibili: (user.entrateDisponibili as number | null) ?? null,
      entrateSettimanali: (user.entrateSettimanali as number | null) ?? null,
      fineIscrizioneMillis: user.fineIscrizione ? toMillis(user.fineIscrizione) : null,
      weeklyUsed,
    });

    if (!decision.allowed) {
      const e = REASON_TO_HTTP[decision.reason as Exclude<SubscribeReason, "OK">];
      throw new HttpsError(e.code, e.msg);
    }

    // Promemoria prova: solo per utenti ancora sul modello legacy (uno snapshot
    // vivo significa che l'utente è stato convertito al multi-abbonamento, anche
    // se tipologiaIscrizione legacy è rimasta PROVA).
    isTrialUser =
      liveRecords.length === 0 && user.tipologiaIscrizione === "ABBONAMENTO_PROVA";

    // ----- scritture (array ricostruiti dai doc letti in transazione) -----
    const subscribed = (course.data.subscribed as number) ?? 0;
    const courseUpdate: FsData = { subscribed: subscribed + 1 };
    const waitlist: string[] = Array.isArray(course.data.waitlist)
      ? (course.data.waitlist as string[])
      : [];
    if (waitlist.includes(targetUserId)) {
      courseUpdate.waitlist = waitlist.filter((id) => id !== targetUserId);
    }
    tx.update(course.ref, courseUpdate);

    const userUpdate: FsData = { courses: [...userCourses, courseId] };
    const waitlistCourses: string[] = Array.isArray(user.waitlistCourses)
      ? (user.waitlistCourses as string[])
      : [];
    if (waitlistCourses.includes(courseId)) {
      userUpdate.waitlistCourses = waitlistCourses.filter((id) => id !== courseId);
    }

    // Consumo del credito + registro per-prenotazione (vedi ConsumptionRecord):
    // si registra ciò che è stato REALMENTE scalato, così il rimborso futuro
    // ripristina la fonte giusta anche se il modello dell'utente cambia.
    const consumed: ConsumptionRecord = { kind: "NONE" };
    if (decision.consume.kind === "LEGACY_ENTRY") {
      const current = (user.entrateDisponibili as number | null) ?? 0;
      // Force admin: consuma il credito disponibile senza andare negativo.
      if (!force && current <= 0) {
        throw new HttpsError("failed-precondition", "Ingressi esauriti");
      }
      if (current > 0) {
        userUpdate.entrateDisponibili = current - 1;
        consumed.kind = "LEGACY_ENTRY";
      }
    } else if (decision.consume.kind === "SUBSCRIPTION_ENTRY") {
      const subId = decision.consume.subscriptionId;
      const target = subId ? txRecords.find((r) => r.id === subId) : undefined;
      const ref = subId ? subRefById.get(subId) : undefined;
      // La collezione è la fonte di verità: lo snapshot può essere stale.
      if (!force && (!target || (target.remainingEntries ?? 0) <= 0)) {
        throw new HttpsError("failed-precondition", "Ingressi esauriti");
      }
      if (target && ref && (target.remainingEntries ?? 0) > 0) {
        target.remainingEntries = (target.remainingEntries ?? 0) - 1;
        tx.update(ref, { remainingEntries: target.remainingEntries });
        userUpdate.activeSubscriptions = computeActiveSnapshot(txRecords, nowMillis).map(
          recordToSnapshotEntry
        );
        consumed.kind = "SUBSCRIPTION_ENTRY";
        consumed.subscriptionId = subId ?? null;
      }
    }

    const consumption = readConsumption(user);
    consumption[courseId] = consumed;
    userUpdate.enrollmentConsumption = consumption;

    tx.update(userRef, userUpdate);
  });

  if (isTrialUser && deps.notifyTrialReminder) {
    await deps.notifyTrialReminder(targetUserId, courseId).catch(() => undefined);
  }

  return { ok: true };
}

// ──────────────────────────────────────────────
//  unsubscribeFromCourse
// ──────────────────────────────────────────────

export async function unsubscribeFromCourseHandler(
  request: EnrollmentRequest,
  db: Firestore,
  deps: EnrollmentDeps = {},
  nowMillis: number = Date.now()
): Promise<Record<string, unknown>> {
  const actor = requireAuthUid(request);
  const data = asObject(request.data);
  const courseId = requireString(data.courseId, "courseId");
  const targetUserId = requireString(data.userId, "userId");
  const confirmedNoRefund = data.confirmedNoRefund === true;

  let courseAlreadyStarted = false;

  await db.runTransaction(async (tx) => {
    const course = await getCourseDoc(tx, db, courseId);
    const userRef = db.collection("users").doc(targetUserId);
    const userTxSnap = await tx.get(userRef);
    if (!userTxSnap.exists) throw new HttpsError("not-found", "Utente inesistente");
    const user = userTxSnap.data() as FsData;

    // Autorizzazione: self, oppure Admin/Trainer su altri.
    if (targetUserId !== actor) {
      const actorRole = await getRole(tx, db, actor);
      if (actorRole === null || !ADMIN_ROLES.has(actorRole)) {
        throw new HttpsError("permission-denied", "Non puoi disiscrivere un altro utente");
      }
    }

    const subscribed = (course.data.subscribed as number) ?? 0;
    const courses: string[] = Array.isArray(user.courses) ? (user.courses as string[]) : [];
    if (!courses.includes(courseId)) {
      throw new HttpsError("failed-precondition", "Non sei iscritto a questo corso");
    }
    if (subscribed <= 0) {
      throw new HttpsError("failed-precondition", "Nessun iscritto al corso");
    }

    const courseStartMillis = toMillis(course.data.startDate);
    courseAlreadyStarted = courseStartMillis <= nowMillis;

    // Corso già iniziato/concluso: la disiscrizione self è bloccata (mirror del
    // gate CLOSED di subscribe — manometterebbe lo storico presenze); le
    // correzioni a posteriori restano possibili agli Admin/Trainer su altri
    // utenti (il ramo target !== actor è già riservato ai privilegiati).
    if (courseAlreadyStarted && targetUserId === actor) {
      throw new HttpsError("failed-precondition", "Il corso è già iniziato");
    }
    const courseTags = Array.isArray(course.data.tags) ? (course.data.tags as string[]) : [];
    const coursePrimaryTag = primaryTypeTagForTags(courseTags);
    const records = snapshotRecords(user);
    // Selezione del modello: solo voci non scadute (coerente con evaluateSubscribe).
    const liveRecords = records.filter((r) => r.endDateMillis >= nowMillis);
    const useSubs = liveRecords.length > 0;

    // Risolvi il creditMode dal modello ATTUALE: determina finestra (8h/4h) e
    // tracciamento cancelledEnrollments. La fonte da RIPRISTINARE invece viene
    // dal registro consumi (vedi sotto), se presente.
    let creditMode: CreditMode = "NONE";
    let subscriptionId: string | null = null;
    if (useSubs) {
      const valid = validAtDate(
        coveringSubsByType(liveRecords, coursePrimaryTag),
        courseStartMillis
      );
      const entrySub = valid.find((s) => s.billingMode === "ENTRIES");
      const freqSub = valid.find((s) => s.billingMode === "FREQUENCY");
      if (entrySub) {
        creditMode = "ENTRIES_SUB";
        subscriptionId = entrySub.id ?? null;
      } else if (freqSub) {
        creditMode = "FREQUENCY_SUB";
      }
    } else {
      const tip = (user.tipologiaIscrizione as string | null) ?? null;
      if (tip === "PACCHETTO_ENTRATE" || tip === "ABBONAMENTO_PROVA") {
        creditMode = "ENTRIES_LEGACY";
      } else if (tip !== null && tip.startsWith("ABBONAMENTO_")) {
        creditMode = "FREQUENCY_LEGACY";
      }
    }

    const minutesToStart = (courseStartMillis - nowMillis) / 60000;
    const refund = decideRefund({ creditMode, subscriptionId, minutesToStart, confirmedNoRefund });
    if (refund.requiresConfirmation) {
      throw new HttpsError(
        "failed-precondition",
        "Disiscrizione entro la finestra: conferma richiesta per procedere"
      );
    }

    // Fonte da ripristinare: il registro consumi dice cosa fu REALMENTE scalato
    // a questa prenotazione (sopravvive ai cambi di modello: prenotazione legacy
    // + abbonamento assegnato dopo → si ripristina l'entrata legacy, non un
    // ingresso mai consumato; force-subscribe senza consumo → nessun ripristino).
    // `lost` (= refund.entryLost) vale per qualunque fonte: entro finestra con
    // conferma il credito si perde. Prenotazioni pre-registro (campo assente):
    // fallback alla risoluzione dal modello attuale (refund.restore*).
    const consumption = readConsumption(user);
    const consumedRecord: ConsumptionRecord | undefined = consumption[courseId];
    const lost = refund.entryLost;
    const restoreLegacy =
      consumedRecord !== undefined
        ? consumedRecord.kind === "LEGACY_ENTRY" && !lost
        : refund.restoreLegacyEntry;
    const restoreSubId =
      consumedRecord !== undefined
        ? consumedRecord.kind === "SUBSCRIPTION_ENTRY" && !lost
          ? (consumedRecord.subscriptionId ?? null)
          : null
        : refund.restoreSubscriptionEntry
          ? refund.subscriptionId
          : null;

    // Lettura aggiuntiva per il ripristino ingressi abbonamento (prima delle scritture).
    let txRecords: UserSubscriptionRecord[] = [];
    const subRefById = new Map<string, DocRef>();
    if (restoreSubId) {
      const subsSnap = await tx.get(
        db.collection("subscriptions").where("userId", "==", targetUserId)
      );
      txRecords = subsSnap.docs.map((d) => {
        subRefById.set(d.id, d.ref);
        return recordFromDoc(d.id, d.data());
      });
    }

    // ----- scritture (array ricostruiti a partire dai doc letti in transazione) -----
    tx.update(course.ref, { subscribed: subscribed - 1 });

    const userUpdate: FsData = {
      courses: courses.filter((id) => id !== courseId),
    };

    if (restoreLegacy) {
      const current = (user.entrateDisponibili as number | null) ?? 0;
      userUpdate.entrateDisponibili = current + 1;
    }

    if (restoreSubId) {
      const ref = subRefById.get(restoreSubId);
      const target = txRecords.find((r) => r.id === restoreSubId);
      if (ref && target) {
        // Clamp difensivo al massimo del piano: un ripristino legittimo non può
        // mai superare gli ingressi del piano.
        const planMax = planByKey(target.planKey)?.entries ?? null;
        const restored = (target.remainingEntries ?? 0) + 1;
        target.remainingEntries = planMax !== null ? Math.min(restored, planMax) : restored;
        tx.update(ref, { remainingEntries: target.remainingEntries });
        userUpdate.activeSubscriptions = computeActiveSnapshot(txRecords, nowMillis).map(
          recordToSnapshotEntry
        );
      }
    }

    if (refund.trackCancelled) {
      const existing: FsData[] = Array.isArray(user.cancelledEnrollments)
        ? (user.cancelledEnrollments as FsData[])
        : [];
      userUpdate.cancelledEnrollments = [
        ...existing,
        {
          courseId,
          cancelledAt: Timestamp.fromMillis(nowMillis),
          entryLost: refund.entryLost,
          courseStartDate: course.data.startDate,
        },
      ];
    }

    // Registro consumi: la prenotazione è chiusa, rimuovi la voce.
    if (consumedRecord !== undefined) {
      const remaining = { ...consumption };
      delete remaining[courseId];
      userUpdate.enrollmentConsumption = remaining;
    }

    tx.update(userRef, userUpdate);
  });

  // Niente notifica "posto disponibile" per corsi già iniziati (rimozioni
  // admin a posteriori): sarebbe un invito fuorviante a iscriversi.
  if (deps.notifyWaitlist && !courseAlreadyStarted) {
    await deps.notifyWaitlist(courseId).catch(() => undefined);
  }

  return { ok: true };
}

// ──────────────────────────────────────────────
//  joinWaitlist
// ──────────────────────────────────────────────

export async function joinWaitlistHandler(
  request: EnrollmentRequest,
  db: Firestore,
  nowMillis: number = Date.now()
): Promise<Record<string, unknown>> {
  const actor = requireAuthUid(request);
  const data = asObject(request.data);
  const courseId = requireString(data.courseId, "courseId");
  const targetUserId = requireString(data.userId, "userId");

  await db.runTransaction(async (tx) => {
    const course = await getCourseDoc(tx, db, courseId);
    const userRef = db.collection("users").doc(targetUserId);
    const userTxSnap = await tx.get(userRef);
    if (!userTxSnap.exists) throw new HttpsError("not-found", "Utente inesistente");
    const user = userTxSnap.data() as FsData;

    if (targetUserId !== actor) {
      const actorRole = await getRole(tx, db, actor);
      if (actorRole === null || !ADMIN_ROLES.has(actorRole)) {
        throw new HttpsError("permission-denied", "Non puoi gestire la waitlist di un altro utente");
      }
    }

    // Mirror di getCourseState: con waitlist disabilitata lo stato è FULL,
    // mai CAN_WAITLIST → il server non accetta iscrizioni in lista.
    if (course.data.waitlistEnabled === false) {
      throw new HttpsError(
        "failed-precondition",
        "Lista d'attesa non disponibile per questo corso"
      );
    }
    // Corso già iniziato → CLOSED (simmetrico a subscribeToCourse).
    if (toMillis(course.data.startDate) <= nowMillis) {
      throw new HttpsError("failed-precondition", "Il corso è già iniziato");
    }

    const subscribed = (course.data.subscribed as number) ?? 0;
    const capacity = (course.data.capacity as number) ?? 0;
    if (subscribed < capacity) {
      throw new HttpsError("failed-precondition", "Il corso non è pieno: iscriviti direttamente");
    }

    const waitlist: string[] = Array.isArray(course.data.waitlist)
      ? (course.data.waitlist as string[])
      : [];
    if (waitlist.includes(targetUserId)) {
      throw new HttpsError("already-exists", "Sei già in lista d'attesa");
    }
    const courses: string[] = Array.isArray(user.courses) ? (user.courses as string[]) : [];
    if (courses.includes(courseId)) {
      throw new HttpsError("already-exists", "Sei già iscritto a questo corso");
    }

    const waitlistCourses: string[] = Array.isArray(user.waitlistCourses)
      ? (user.waitlistCourses as string[])
      : [];
    tx.update(course.ref, { waitlist: [...waitlist, targetUserId] });
    tx.update(userRef, { waitlistCourses: [...waitlistCourses, courseId] });
  });

  return { ok: true };
}

// ──────────────────────────────────────────────
//  leaveWaitlist
// ──────────────────────────────────────────────

export async function leaveWaitlistHandler(
  request: EnrollmentRequest,
  db: Firestore
): Promise<Record<string, unknown>> {
  const actor = requireAuthUid(request);
  const data = asObject(request.data);
  const courseId = requireString(data.courseId, "courseId");
  const targetUserId = requireString(data.userId, "userId");

  await db.runTransaction(async (tx) => {
    const course = await getCourseDoc(tx, db, courseId);
    const userRef = db.collection("users").doc(targetUserId);
    const userTxSnap = await tx.get(userRef);
    if (!userTxSnap.exists) throw new HttpsError("not-found", "Utente inesistente");
    const user = userTxSnap.data() as FsData;

    if (targetUserId !== actor) {
      const actorRole = await getRole(tx, db, actor);
      if (actorRole === null || !ADMIN_ROLES.has(actorRole)) {
        throw new HttpsError("permission-denied", "Non puoi gestire la waitlist di un altro utente");
      }
    }

    const waitlist: string[] = Array.isArray(course.data.waitlist)
      ? (course.data.waitlist as string[])
      : [];
    const waitlistCourses: string[] = Array.isArray(user.waitlistCourses)
      ? (user.waitlistCourses as string[])
      : [];

    const inCourse = waitlist.includes(targetUserId);
    const inUser = waitlistCourses.includes(courseId);
    if (!inCourse && !inUser) {
      throw new HttpsError("failed-precondition", "Non sei in lista d'attesa");
    }

    if (inCourse) {
      tx.update(course.ref, {
        waitlist: waitlist.filter((id) => id !== targetUserId),
      });
    }
    if (inUser) {
      tx.update(userRef, {
        waitlistCourses: waitlistCourses.filter((id) => id !== courseId),
      });
    }
  });

  return { ok: true };
}
