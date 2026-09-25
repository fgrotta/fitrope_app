// Cron dei promemoria WhatsApp: ogni sera alle 19:00 Europe/Rome per le
// lezioni del giorno dopo (export `sendDemoLessonWhatsappReminders` in index.ts).
//
// Le iscrizioni vivono su `users/{uid}.courses`, quindi si parte dai corsi di
// domani e si leggono gli iscritti con `array-contains-any` (massimo 30 valori
// per query → blocchi). Nel modello multi-abbonamento non si può filtrare su
// `planKey` dentro un array di mappe: il predicato "utente di prova" si applica
// in memoria, lo stesso `isTrialUser` dell'iscrizione. Ogni query ha un solo
// campo filtrato: nessun indice composito.
//
// Ripresa: il giorno dei corsi e la soppressione della conferma dipendono da
// `scheduledAtMillis` (event.scheduleTime), stabile nei retry di Cloud Scheduler.
// Se la deadline interna scade, il run smette di avviare invii, attende quelli
// in corso e lancia, così lo Scheduler ritenta; il registro invii (sendLog.ts)
// fa saltare i promemoria già partiti e segnala quelli incerti senza reinviarli.

import { logger } from "firebase-functions";
import { Timestamp } from "firebase-admin/firestore";
import type { DocumentData } from "firebase-admin/firestore";
import { snapshotRecords } from "../enrollment/enrollment";
import { isTrialUser } from "../enrollment/trial";
import {
  DemoCourse,
  DemoUser,
  WhatsappDeps,
  dispatchDemoLesson,
  mapDemoCourseDoc,
  mapDemoUserDoc,
} from "./demoLesson";
import { tomorrowRomeRange } from "./format";

/** Limite di Firestore sui valori di `array-contains-any`. */
export const ARRAY_CONTAINS_ANY_LIMIT = 30;

/** POST verso Make in volo contemporaneamente. */
export const MAX_CONCURRENT_SENDS = 10;

export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

export interface ReminderRunResult {
  coursesTomorrow: number;
  /** Utenti distinti iscritti ad almeno un corso di domani. */
  usersRead: number;
  candidates: number;
  sent: number;
  skipped: number;
  /** Invii rifiutati, incerti o da verificare, e utenti con snapshot illeggibile. */
  failed: number;
}

export interface ReminderRunOptions {
  /** Istante schedulato del job: sceglie "domani" e il giorno della soppressione. */
  scheduledAtMillis: number;
  /** Oltre questo istante non si avviano nuovi invii. */
  deadlineMillis: number;
  now?: () => number;
}

interface Candidate {
  user: DemoUser;
  course: DemoCourse;
}

export async function runDemoLessonReminders(
  deps: WhatsappDeps,
  options: ReminderRunOptions
): Promise<ReminderRunResult> {
  const now = options.now ?? Date.now;
  const range = tomorrowRomeRange(options.scheduledAtMillis);

  const courseSnap = await deps.db
    .collection("courses")
    .where("startDate", ">=", Timestamp.fromMillis(range.startMs))
    .where("startDate", "<=", Timestamp.fromMillis(range.endMs))
    .get();
  const courses = courseSnap.docs.map((doc) =>
    mapDemoCourseDoc({ id: doc.id, data: () => doc.data() })
  );

  const result: ReminderRunResult = {
    coursesTomorrow: courses.length,
    usersRead: 0,
    candidates: 0,
    sent: 0,
    skipped: 0,
    failed: 0,
  };

  // `users.courses` contiene l'uid del corso; sui documenti storici può essere l'id del documento.
  const membershipValues = [...new Set(courses.flatMap((c) => [c.uid, c.docId]))];
  const userDocs = new Map<string, DocumentData>();
  for (const values of chunk(membershipValues, ARRAY_CONTAINS_ANY_LIMIT)) {
    const snap = await deps.db
      .collection("users")
      .where("courses", "array-contains-any", values)
      .get();
    // Un utente iscritto a corsi di blocchi diversi torna in più query: lo leggo una volta.
    for (const doc of snap.docs) userDocs.set(doc.id, doc.data());
  }
  result.usersRead = userDocs.size;

  const candidates: Candidate[] = [];
  for (const [userId, data] of userDocs) {
    let trial: boolean;
    try {
      const live = snapshotRecords(data).filter((r) => r.endDateMillis >= deps.nowMillis);
      trial = isTrialUser(data, live);
    } catch (err) {
      // Uno snapshot malformato riguarda solo questo utente: lo conto e proseguo.
      result.failed++;
      logger.error("Promemoria WhatsApp: abbonamenti dell'utente illeggibili", {
        userId,
        error: err instanceof Error ? err.message : String(err),
      });
      continue;
    }
    if (!trial) continue;

    const user = mapDemoUserDoc({ id: userId, data: () => data });
    for (const course of courses) {
      if (user.courses.includes(course.uid) || user.courses.includes(course.docId)) {
        candidates.push({ user, course });
      }
    }
  }
  result.candidates = candidates.length;

  let next = 0;
  let deadlineReached = false;
  const worker = async () => {
    while (next < candidates.length) {
      if (now() >= options.deadlineMillis) {
        deadlineReached = true;
        return;
      }
      const { user, course } = candidates[next++];
      const ids = { userId: user.uid, courseId: course.uid };
      try {
        const outcome = await dispatchDemoLesson(
          deps,
          "reminder",
          user,
          course,
          options.scheduledAtMillis
        );
        if (outcome.sent) {
          result.sent++;
        } else if (outcome.failed) {
          // Rifiutato o incerto: da verificare in Make, senza far ripetere il batch.
          result.failed++;
          logger.error("Promemoria WhatsApp non consegnato", { ...ids, reason: outcome.reason });
        } else {
          result.skipped++;
          logger.info("Promemoria WhatsApp saltato", { ...ids, reason: outcome.reason });
        }
      } catch (err) {
        // Tipicamente Firestore sul claim: nessuna POST partita, il retry del job lo riprende.
        result.failed++;
        logger.error("Promemoria WhatsApp fallito", {
          ...ids,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(MAX_CONCURRENT_SENDS, candidates.length) }, worker)
  );

  const remaining = candidates.length - next;
  logger.info("Run promemoria WhatsApp completata", { ...result, remaining, deadlineReached });
  if (deadlineReached) {
    throw new Error(
      `Deadline del run raggiunta: ${remaining} promemoria da elaborare al prossimo tentativo`
    );
  }
  return result;
}
