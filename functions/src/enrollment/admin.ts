// Operazioni ADMIN sul dominio iscrizioni (port di lib/api/courses/deleteCourse.dart
// e updateCourseSubscribedCount.dart). Regola README: le operazioni admin
// rimborsano SEMPRE il credito (nessuna finestra, nessuna perdita).
//
// Differenze deliberate rispetto al client legacy (fix, non regressioni):
// - deleteCourse era N+2 transazioni non atomiche (una per iscritto) che inviava
//   email "posto disponibile" alla waitlist di un corso in cancellazione; qui è
//   UNA transazione, senza email;
// - removeUserFromCourse legacy NON decrementava `subscribed` (origine delle
//   discrepanze che "Correggi conteggio" doveva sanare) e crashava con
//   `entrateDisponibili` null: entrambi risolti dal path callable;
// - il rimborso usa il registro consumi (`enrollmentConsumption`) e ripristina
//   anche `remainingEntries` del nuovo modello, con clamp al massimo del piano.

import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { planByKey } from "./plansCatalog";
import {
  UserSubscriptionRecord,
  recordFromDoc,
  recordToSnapshotEntry,
  computeActiveSnapshot,
} from "./subscription";
import { primaryTypeTagForTags } from "./courseTypes";
import { decideAdminRefund } from "./refund";
import {
  EnrollmentRequest,
  ConsumptionRecord,
  getCourseDoc,
  readConsumption,
  pruneConsumption,
  resolveCreditMode,
  requireAuthUid,
  toMillis,
} from "./enrollment";

type Firestore = admin.firestore.Firestore;
type FsData = admin.firestore.DocumentData;
type Transaction = admin.firestore.Transaction;

/**
 * Limite di sicurezza sugli utenti coinvolti in una cancellazione atomica:
 * nel caso peggiore ~2 scritture per iscritto (doc utente + doc subscriptions)
 * più la delete del corso. Il vincolo pratico di una transazione Firestore è
 * la dimensione della richiesta (10 MiB) e la latency/contention, non un
 * numero fisso di scritture: 200 utenti tiene il worst case largamente dentro
 * entrambi (capienza reale dei corsi: ~10-20).
 */
const MAX_AFFECTED_USERS = 200;

function requireCourseId(data: unknown): string {
  const obj = data && typeof data === "object" ? (data as Record<string, unknown>) : null;
  const courseId = obj?.courseId;
  if (typeof courseId !== "string" || courseId.length === 0) {
    throw new HttpsError("invalid-argument", "courseId è richiesto");
  }
  return courseId;
}

/**
 * Cancellare corsi e riscrivere contatori sono operazioni distruttive che la
 * UI riserva al SOLO Admin (CalendarPage/course_card): il server applica lo
 * stesso vincolo — un Trainer non deve poterle invocare via callable diretta.
 */
async function requireAdmin(
  tx: Transaction,
  db: Firestore,
  uid: string
): Promise<void> {
  const snap = await tx.get(db.collection("users").doc(uid));
  const role = snap.exists ? ((snap.data() as FsData)?.role as string | null) ?? null : null;
  if (role !== "Admin") {
    throw new HttpsError("permission-denied", "Operazione riservata agli Admin");
  }
}

/**
 * Cancella un corso (SOLO Admin) ripulendo iscrizioni e waitlist in UNA
 * transazione atomica. Corsi FUTURI: rimborsa tutti gli iscritti (registro
 * consumi, regola admin-rimborsa-sempre). Corsi GIÀ INIZIATI/conclusi (pulizia
 * del calendario/storico): NESSUN rimborso — i partecipanti hanno frequentato,
 * rimborsarli conierebbe crediti. Nessuna notifica waitlist: il corso sparisce.
 *
 * Payload: { courseId: string }
 */
export async function deleteCourseHandler(
  request: EnrollmentRequest,
  db: Firestore,
  nowMillis: number = Date.now()
): Promise<Record<string, unknown>> {
  const actor = requireAuthUid(request);
  const courseId = requireCourseId(request.data);

  let removedSubscribers = 0;
  let removedWaitlist = 0;

  await db.runTransaction(async (tx) => {
    // ----- letture (tutte prima delle scritture) -----
    await requireAdmin(tx, db, actor);
    const course = await getCourseDoc(tx, db, courseId);

    const subscribersSnap = await tx.get(
      db.collection("users").where("courses", "array-contains", courseId)
    );
    const waitlistedSnap = await tx.get(
      db.collection("users").where("waitlistCourses", "array-contains", courseId)
    );

    if (subscribersSnap.docs.length + waitlistedSnap.docs.length > MAX_AFFECTED_USERS) {
      throw new HttpsError(
        "failed-precondition",
        "Troppi utenti coinvolti per una cancellazione atomica"
      );
    }

    // Assegnati (non incrementati): Firestore può rieseguire la closure in
    // caso di contention e gli accumulatori esterni si gonfierebbero.
    removedSubscribers = subscribersSnap.docs.length;
    removedWaitlist = waitlistedSnap.docs.length;

    const courseStartMillis = toMillis(course.data.startDate);
    // Corso già iniziato/concluso (pulizia calendario/storico): i partecipanti
    // hanno frequentato — nessun rimborso, si rimuovono solo iscrizioni/waitlist.
    const refundable = courseStartMillis > nowMillis;
    const courseTags = Array.isArray(course.data.tags) ? (course.data.tags as string[]) : [];
    const coursePrimaryTag = primaryTypeTagForTags(courseTags);

    // Piano di rimborso per ogni iscritto: registro consumi se presente,
    // altrimenti fallback dal modello attuale (admin rimborsa sempre).
    interface PlannedUpdate {
      ref: admin.firestore.DocumentReference;
      update: FsData;
      restoreSubId: string | null;
      user: FsData;
    }
    const planned = new Map<string, PlannedUpdate>();

    for (const doc of subscribersSnap.docs) {
      const user = doc.data() as FsData;
      const consumption = readConsumption(user);
      const record: ConsumptionRecord | undefined = consumption[courseId];

      let restoreLegacy: boolean;
      let restoreSubId: string | null;
      if (!refundable) {
        restoreLegacy = false;
        restoreSubId = null;
      } else if (record !== undefined) {
        restoreLegacy = record.kind === "LEGACY_ENTRY";
        restoreSubId =
          record.kind === "SUBSCRIPTION_ENTRY" ? (record.subscriptionId ?? null) : null;
      } else {
        const { creditMode, subscriptionId } = resolveCreditMode(
          user,
          coursePrimaryTag,
          courseStartMillis,
          nowMillis
        );
        const refund = decideAdminRefund(creditMode, subscriptionId);
        restoreLegacy = refund.restoreLegacyEntry;
        restoreSubId = refund.restoreSubscriptionEntry ? refund.subscriptionId : null;
      }

      const courses: string[] = Array.isArray(user.courses) ? (user.courses as string[]) : [];
      const update: FsData = {
        courses: courses.filter((id) => id !== courseId),
      };
      if (restoreLegacy) {
        update.entrateDisponibili = ((user.entrateDisponibili as number | null) ?? 0) + 1;
      }
      const remaining = pruneConsumption(consumption, nowMillis);
      delete remaining[courseId];
      update.enrollmentConsumption = remaining;

      planned.set(doc.id, { ref: doc.ref, update, restoreSubId, user });
    }

    // Ripristino ingressi abbonamento: lettura dei doc subscriptions degli
    // utenti che ne hanno bisogno, in PARALLELO (sempre PRIMA delle scritture).
    const subWrites: Array<{ ref: admin.firestore.DocumentReference; remainingEntries: number }> =
      [];
    const needingRestore = [...planned.entries()].filter(([, p]) => p.restoreSubId);
    const subsSnaps = await Promise.all(
      needingRestore.map(([userId]) =>
        tx.get(db.collection("subscriptions").where("userId", "==", userId))
      )
    );
    needingRestore.forEach(([userId, plan], i) => {
      const txRecords: UserSubscriptionRecord[] = [];
      let targetRef: admin.firestore.DocumentReference | undefined;
      let target: UserSubscriptionRecord | undefined;
      for (const d of subsSnaps[i].docs) {
        const r = recordFromDoc(d.id, d.data());
        txRecords.push(r);
        if (d.id === plan.restoreSubId) {
          targetRef = d.ref;
          target = r;
        }
      }
      if (!target || !targetRef) {
        logger.warn("deleteCourse: rimborso abbonamento non applicabile, doc mancante", {
          userId,
          courseId,
          subscriptionId: plan.restoreSubId,
        });
        return;
      }
      const planMax = planByKey(target.planKey)?.entries ?? null;
      const restored = (target.remainingEntries ?? 0) + 1;
      target.remainingEntries = planMax !== null ? Math.min(restored, planMax) : restored;
      subWrites.push({ ref: targetRef, remainingEntries: target.remainingEntries });
      plan.update.activeSubscriptions = computeActiveSnapshot(txRecords, nowMillis).map(
        recordToSnapshotEntry
      );
    });

    // Waitlist: rimozione del corso da waitlistCourses (merge se l'utente è
    // anche iscritto — non dovrebbe accadere, ma il merge è difensivo).
    for (const doc of waitlistedSnap.docs) {
      const user = doc.data() as FsData;
      const waitlistCourses: string[] = Array.isArray(user.waitlistCourses)
        ? (user.waitlistCourses as string[])
        : [];
      const cleaned = waitlistCourses.filter((id) => id !== courseId);
      const existing = planned.get(doc.id);
      if (existing) {
        existing.update.waitlistCourses = cleaned;
      } else {
        planned.set(doc.id, {
          ref: doc.ref,
          update: { waitlistCourses: cleaned },
          restoreSubId: null,
          user,
        });
      }
    }

    // ----- scritture -----
    for (const { ref, remainingEntries } of subWrites) {
      tx.update(ref, { remainingEntries });
    }
    for (const plan of planned.values()) {
      tx.update(plan.ref, plan.update);
    }
    tx.delete(course.ref);
  });

  return { ok: true, removedSubscribers, removedWaitlist };
}

/**
 * Ricalcola `subscribed` di un corso dalla fonte di verità (gli utenti con il
 * corso in `courses[]`), in transazione. Sostituisce il vecchio
 * updateCourseSubscribedCount client che scriveva un valore calcolato
 * client-side (sovrascrivibile da scritture server concorrenti).
 *
 * Payload: { courseId: string }
 */
export async function recountCourseSubscribedHandler(
  request: EnrollmentRequest,
  db: Firestore
): Promise<Record<string, unknown>> {
  const actor = requireAuthUid(request);
  const courseId = requireCourseId(request.data);

  let subscribed = 0;
  await db.runTransaction(async (tx) => {
    await requireAdmin(tx, db, actor);
    const course = await getCourseDoc(tx, db, courseId);
    const subscribersSnap = await tx.get(
      db.collection("users").where("courses", "array-contains", courseId)
    );
    subscribed = subscribersSnap.docs.length;
    tx.update(course.ref, { subscribed });
  });

  return { ok: true, subscribed };
}
