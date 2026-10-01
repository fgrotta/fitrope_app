// Presenze effettive ai corsi (server autoritativo).
//
// Registro durevole di chi era davvero in sala, per alimentare in futuro uno
// score di rischio abbandono: oggi NON ha effetti sul socio (niente penalità,
// niente ingressi scalati alla presenza), quindi basta la finestra temporale
// server-side, senza verifica di prossimità.
//
// Chi marca:
//  - lo STAFF (Admin sempre, Trainer solo sui propri corsi o su quelli senza
//    trainer) da 30' prima dell'inizio in poi, senza limite superiore, presente
//    o assente; il tocco dello staff sovrascrive sempre un self check-in;
//  - il SOCIO iscritto, solo `present: true`, da 15' prima a 30' dopo l'inizio,
//    e solo finché lo staff non ha registrato nulla per lui.
//
// Storage: `attendance/{courseId}_{userId}` (id deterministico) + marcatore
// `courses/{id}.attendance = { lastMarkedAt, lastMarkedBy, presentCount }`,
// scritto come oggetto intero (niente dotted path né increment) in transazione.

import { HttpsError, FunctionsErrorCode } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  EnrollmentRequest,
  asObject,
  getCourseDoc,
  requireAuthUid,
  requireString,
  toMillis,
} from "./enrollment";

type Firestore = admin.firestore.Firestore;
type FsData = admin.firestore.DocumentData;

const MINUTE_MS = 60 * 1000;
/** Il self check-in apre 15' prima dell'inizio... */
export const SELF_WINDOW_BEFORE_MS = 15 * MINUTE_MS;
/** ...e chiude 30' dopo: poi il socio deve chiedere al trainer. */
export const SELF_WINDOW_AFTER_MS = 30 * MINUTE_MS;
/** Lo staff può fare l'appello da 30' prima dell'inizio, senza scadenza. */
export const STAFF_WINDOW_BEFORE_MS = 30 * MINUTE_MS;
/** Come la UI (calendar_page.dart), un corso senza trainer è di tutti i Trainer. */
export const TRAINER_MAY_MARK_UNASSIGNED_COURSE = true;

export type AttendanceSource = "self" | "trainer" | "admin";

export type AttendanceReason =
  | "ATTENDANCE_STAFF_CANNOT_SELF_MARK"
  | "ATTENDANCE_NOT_STAFF"
  | "ATTENDANCE_NOT_COURSE_TRAINER"
  | "ATTENDANCE_SELF_CANNOT_MARK_ABSENT"
  | "ATTENDANCE_NOT_ENROLLED"
  | "ATTENDANCE_WINDOW_NOT_OPEN"
  | "ATTENDANCE_WINDOW_CLOSED"
  | "ATTENDANCE_ALREADY_RECORDED_BY_STAFF";

export interface AttendanceInput {
  actorUid: string;
  actorRole: string | null;
  targetUid: string;
  requestedPresent: boolean;
  /** `trainerId` del corso; null o "" = corso senza trainer assegnato. */
  courseTrainerId: string | null;
  courseStartMillis: number;
  nowMillis: number;
  /** Il corso è in `users/{target}.courses` (false anche se il target non esiste). */
  targetEnrolled: boolean;
  existing: { present: boolean; source: AttendanceSource } | null;
}

export type AttendanceDecision =
  | { allowed: false; reason: AttendanceReason }
  | {
      allowed: true;
      source: AttendanceSource;
      /** Niente da scrivere: la richiesta ripete lo stato già registrato. */
      noop: boolean;
      /** Variazione di `presentCount` sul marcatore del corso. */
      presentDelta: number;
    };

const deny = (reason: AttendanceReason): AttendanceDecision => ({ allowed: false, reason });

function isStaffRole(role: string | null): boolean {
  return role === "Admin" || role === "Trainer";
}

/** Logica pura: l'ordine dei controlli definisce quale reason vince. */
export function decideAttendance(input: AttendanceInput): AttendanceDecision {
  const isSelf = input.actorUid === input.targetUid;
  const isStaff = isStaffRole(input.actorRole);

  // 1. ruolo
  if (isSelf && isStaff) return deny("ATTENDANCE_STAFF_CANNOT_SELF_MARK");
  if (!isSelf && !isStaff) return deny("ATTENDANCE_NOT_STAFF");
  if (!isSelf && input.actorRole === "Trainer") {
    const trainerId = input.courseTrainerId ?? "";
    const unassigned = trainerId.length === 0;
    const owner = trainerId === input.actorUid;
    if (!owner && !(unassigned && TRAINER_MAY_MARK_UNASSIGNED_COURSE)) {
      return deny("ATTENDANCE_NOT_COURSE_TRAINER");
    }
  }

  // 2. il socio può solo dichiararsi presente
  if (isSelf && !input.requestedPresent) return deny("ATTENDANCE_SELF_CANNOT_MARK_ABSENT");

  // 3. anche lo staff: prima si iscrive il socio (con force), poi l'appello
  if (!input.targetEnrolled) return deny("ATTENDANCE_NOT_ENROLLED");

  // 4. finestra (bordi inclusivi)
  const offset = input.nowMillis - input.courseStartMillis;
  if (isSelf) {
    if (offset < -SELF_WINDOW_BEFORE_MS) return deny("ATTENDANCE_WINDOW_NOT_OPEN");
    if (offset > SELF_WINDOW_AFTER_MS) return deny("ATTENDANCE_WINDOW_CLOSED");
  } else if (offset < -STAFF_WINDOW_BEFORE_MS) {
    return deny("ATTENDANCE_WINDOW_NOT_OPEN");
  }

  // 5. record esistente
  const source: AttendanceSource = isSelf
    ? "self"
    : input.actorRole === "Admin"
      ? "admin"
      : "trainer";
  const existing = input.existing;
  if (isSelf && existing && existing.source !== "self") {
    return deny("ATTENDANCE_ALREADY_RECORDED_BY_STAFF");
  }
  // Doppio tap in sala (o dello staff): idempotente, non un errore.
  if (existing && existing.present === input.requestedPresent && existing.source === source) {
    return { allowed: true, source, noop: true, presentDelta: 0 };
  }

  // 6. delta sul conteggio
  const presentDelta = (input.requestedPresent ? 1 : 0) - (existing?.present ? 1 : 0);
  return { allowed: true, source, noop: false, presentDelta };
}

const REASON_TO_HTTP: Record<AttendanceReason, { code: FunctionsErrorCode; msg: string }> = {
  ATTENDANCE_STAFF_CANNOT_SELF_MARK: {
    code: "permission-denied",
    msg: "Admin e Trainer non registrano la propria presenza",
  },
  ATTENDANCE_NOT_STAFF: {
    code: "permission-denied",
    msg: "Solo lo staff può registrare la presenza di un altro utente",
  },
  ATTENDANCE_NOT_COURSE_TRAINER: {
    code: "permission-denied",
    msg: "Puoi registrare le presenze solo dei tuoi corsi",
  },
  ATTENDANCE_SELF_CANNOT_MARK_ABSENT: {
    code: "permission-denied",
    msg: "Puoi solo segnalare la tua presenza",
  },
  ATTENDANCE_NOT_ENROLLED: {
    code: "failed-precondition",
    msg: "L'utente non è iscritto a questo corso",
  },
  ATTENDANCE_WINDOW_NOT_OPEN: {
    code: "failed-precondition",
    msg: "La registrazione delle presenze non è ancora aperta",
  },
  ATTENDANCE_WINDOW_CLOSED: {
    code: "failed-precondition",
    msg: "Il check-in è chiuso: chiedi al trainer di registrare la tua presenza",
  },
  ATTENDANCE_ALREADY_RECORDED_BY_STAFF: {
    code: "failed-precondition",
    msg: "La tua presenza è già stata registrata dallo staff",
  },
};

function readSource(v: unknown): AttendanceSource {
  return v === "trainer" || v === "admin" ? v : "self";
}

export function attendanceDocId(courseId: string, userId: string): string {
  return `${courseId}_${userId}`;
}

/**
 * Registra la presenza (o l'assenza) di un iscritto a un corso.
 *
 * Payload: { courseId: string, userId?: string, present: boolean }
 * (`userId` assente = check-in del chiamante).
 * Errori: HttpsError con `details.reason` = AttendanceReason, così il client
 * distingue i casi senza interpretare il messaggio.
 */
export async function setAttendanceHandler(
  request: EnrollmentRequest,
  db: Firestore,
  nowMillis: number = Date.now()
): Promise<Record<string, unknown>> {
  const actor = requireAuthUid(request);
  const data = asObject(request.data);
  const courseId = requireString(data.courseId, "courseId");
  const targetUid =
    data.userId === undefined || data.userId === null
      ? actor
      : requireString(data.userId, "userId");
  if (typeof data.present !== "boolean") {
    throw new HttpsError("invalid-argument", "present è richiesto");
  }
  const present = data.present;

  let result: Record<string, unknown> = {};
  await db.runTransaction(async (tx) => {
    // ----- letture (tutte prima delle scritture) -----
    const course = await getCourseDoc(tx, db, courseId);
    const actorSnap = await tx.get(db.collection("users").doc(actor));
    const targetSnap =
      targetUid === actor ? actorSnap : await tx.get(db.collection("users").doc(targetUid));
    const attRef = db.collection("attendance").doc(attendanceDocId(courseId, targetUid));
    const attSnap = await tx.get(attRef);

    const actorRole = actorSnap.exists
      ? (((actorSnap.data() as FsData).role as string | null) ?? null)
      : null;
    const targetCourses = targetSnap.exists
      ? ((targetSnap.data() as FsData).courses as unknown)
      : null;
    const existingData = attSnap.exists ? (attSnap.data() as FsData) : null;
    const courseStartMillis = toMillis(course.data.startDate);
    const trainerId = course.data.trainerId;

    const decision = decideAttendance({
      actorUid: actor,
      actorRole,
      targetUid,
      requestedPresent: present,
      courseTrainerId: typeof trainerId === "string" ? trainerId : null,
      courseStartMillis,
      nowMillis,
      targetEnrolled: Array.isArray(targetCourses) && targetCourses.includes(courseId),
      existing: existingData
        ? { present: existingData.present === true, source: readSource(existingData.source) }
        : null,
    });
    if (!decision.allowed) {
      const { code, msg } = REASON_TO_HTTP[decision.reason];
      throw new HttpsError(code, msg, { reason: decision.reason });
    }

    const marker = (course.data.attendance ?? null) as FsData | null;
    const prevCount = typeof marker?.presentCount === "number" ? marker.presentCount : 0;
    if (decision.noop) {
      result = {
        ok: true,
        present,
        source: decision.source,
        changed: false,
        presentCount: prevCount,
      };
      return;
    }

    // ----- scritture -----
    const at = Timestamp.fromMillis(nowMillis);
    const record: FsData = {
      courseId,
      userId: targetUid,
      courseStartMillis,
      present,
      source: decision.source,
      markedBy: actor,
      updatedAt: at,
    };
    if (!existingData) record.markedAt = at;
    tx.set(attRef, record, { merge: true });

    const presentCount = Math.max(0, prevCount + decision.presentDelta);
    tx.update(course.ref, {
      attendance: { lastMarkedAt: at, lastMarkedBy: actor, presentCount },
    });
    result = { ok: true, present, source: decision.source, changed: true, presentCount };
  });

  return result;
}
