// Notifiche server-side per i flussi di iscrizione (best-effort, fuori transazione).
// Porting di lib/services/notification_service.dart:
//  - scheduleTrialReminder: email/push promemoria lezione di prova (giorno prima, 19:00 Europe/Rome)
//  - notifyWaitlistUsers: email "posto disponibile" + rimozione utenti scaduti dalla waitlist
//
// Le date sono calcolate nel fuso Europe/Rome (la palestra è in Italia) come fa il
// client, indipendentemente dal fuso del runtime (UTC).

import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { ONESIGNAL_APP_ID, ONESIGNAL_API_URL } from "../handler";
import {
  trialReminderSubject,
  trialReminderBody,
  waitlistSpotAvailableSubject,
  waitlistSpotAvailableBody,
} from "./emailTemplates";

const DAY_NAMES = [
  "Lunedì",
  "Martedì",
  "Mercoledì",
  "Giovedì",
  "Venerdì",
  "Sabato",
  "Domenica",
];
const MONTH_NAMES = [
  "Gennaio",
  "Febbraio",
  "Marzo",
  "Aprile",
  "Maggio",
  "Giugno",
  "Luglio",
  "Agosto",
  "Settembre",
  "Ottobre",
  "Novembre",
  "Dicembre",
];

const ROME_TZ = "Europe/Rome";

export interface RomeParts {
  year: number;
  month: number; // 1-12
  day: number;
  hour: number;
  minute: number;
  isoWeekday: number; // 1=lun .. 7=dom
}

/** Componenti wall-clock di [millis] nel fuso Europe/Rome. (Esportata per i test.) */
export function romeParts(millis: number): RomeParts {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: ROME_TZ,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
  const map: Record<string, string> = {};
  for (const p of dtf.formatToParts(new Date(millis))) map[p.type] = p.value;
  const year = Number(map.year);
  const month = Number(map.month);
  const day = Number(map.day);
  let hour = Number(map.hour);
  if (hour === 24) hour = 0; // alcune impl. usano 24 per mezzanotte
  const minute = Number(map.minute);
  const dow = new Date(Date.UTC(year, month - 1, day)).getUTCDay(); // 0=dom..6=sab
  const isoWeekday = ((dow + 6) % 7) + 1; // 1=lun..7=dom
  return { year, month, day, hour, minute, isoWeekday };
}

/** Offset (in millis) di Europe/Rome all'istante [date]. */
function romeOffsetMillis(date: Date): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: ROME_TZ,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  const map: Record<string, string> = {};
  for (const p of dtf.formatToParts(date)) map[p.type] = p.value;
  let hour = Number(map.hour);
  if (hour === 24) hour = 0;
  const asUtc = Date.UTC(
    Number(map.year),
    Number(map.month) - 1,
    Number(map.day),
    hour,
    Number(map.minute),
    Number(map.second)
  );
  return asUtc - date.getTime();
}

/** Istante UTC (millis) del wall-clock Europe/Rome indicato. (Esportata per i test.) */
export function romeWallClockToUtcMillis(
  year: number,
  month: number, // 1-12
  day: number,
  hour: number,
  minute: number
): number {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  const offset = romeOffsetMillis(new Date(guess));
  return guess - offset;
}

export function formatCourseDate(startMillis: number): string {
  const p = romeParts(startMillis);
  return `${DAY_NAMES[p.isoWeekday - 1]} ${p.day} ${MONTH_NAMES[p.month - 1]}`;
}

export function formatCourseTime(startMillis: number, endMillis: number): string {
  const s = romeParts(startMillis);
  const e = romeParts(endMillis);
  const pad = (n: number) => n.toString().padStart(2, "0");
  return `${pad(s.hour)}:${pad(s.minute)} - ${pad(e.hour)}:${pad(e.minute)}`;
}

/**
 * Istante di invio del promemoria prova: il giorno prima del corso alle 19:00
 * Europe/Rome. Il rollover di inizio mese (giorno 1 → "giorno 0" del mese) è
 * gestito dalla semantica di Date.UTC (→ ultimo giorno del mese precedente).
 * (Esportata per i test.)
 */
export function trialReminderSendAtMillis(courseStartMillis: number): number {
  const start = romeParts(courseStartMillis);
  return romeWallClockToUtcMillis(start.year, start.month, start.day - 1, 19, 0);
}

/** POST verso OneSignal REST API (inietta app_id server-side). Best-effort. */
async function postOneSignal(
  apiKey: string,
  label: string,
  payload: Record<string, unknown>
): Promise<void> {
  try {
    const body = { ...payload, app_id: ONESIGNAL_APP_ID };
    const response = await fetch(ONESIGNAL_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        Authorization: `Key ${apiKey.trim()}`,
      },
      body: JSON.stringify(body),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      logger.warn(`OneSignal ${label} non ok`, { status: response.status, data });
    }
  } catch (err) {
    logger.warn(`OneSignal ${label} errore`, err);
  }
}

type Firestore = admin.firestore.Firestore;
type FsData = admin.firestore.DocumentData;

function toMillis(ts: unknown): number | null {
  if (ts && typeof (ts as { toMillis?: () => number }).toMillis === "function") {
    return (ts as { toMillis: () => number }).toMillis();
  }
  return null;
}

/** Trova il corso per campo `uid` (come fa il client). Null se assente. */
async function getCourseByUid(
  db: Firestore,
  courseId: string
): Promise<{ ref: admin.firestore.DocumentReference; data: FsData } | null> {
  const snap = await db
    .collection("courses")
    .where("uid", "==", courseId)
    .limit(1)
    .get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  return { ref: doc.ref, data: doc.data() };
}

/**
 * Schedula il promemoria della lezione di prova (giorno prima, 19:00 Europe/Rome).
 * Rispetta il flag `reminderEnabled` del corso e le preferenze notifiche utente.
 */
export async function scheduleTrialReminder(
  db: Firestore,
  apiKey: string,
  userId: string,
  courseId: string,
  nowMillis: number
): Promise<void> {
  const course = await getCourseByUid(db, courseId);
  if (!course) return;
  const courseDoc = course.data;

  const reminderEnabled = courseDoc.reminderEnabled !== false;
  if (!reminderEnabled) return;

  const startMillis = toMillis(courseDoc.startDate);
  const endMillis = toMillis(courseDoc.endDate);
  if (startMillis === null || endMillis === null) return;

  const sendAtMillis = trialReminderSendAtMillis(startMillis);
  if (sendAtMillis <= nowMillis) return; // data invio già passata

  const sendAfter = new Date(sendAtMillis).toISOString();
  const courseDate = formatCourseDate(startMillis);
  const courseTime = formatCourseTime(startMillis, endMillis);
  const name = (courseDoc.name as string) ?? "";

  const userSnap = await db.collection("users").doc(userId).get();
  const userData = userSnap.data() ?? {};
  const pushEnabled = userData.pushNotificationsEnabled !== false;
  const emailEnabled = userData.emailNotificationsEnabled !== false;

  const tasks: Promise<void>[] = [];
  if (pushEnabled) {
    tasks.push(
      postOneSignal(apiKey, "Trial Push Reminder", {
        include_aliases: { external_id: [userId] },
        target_channel: "push",
        send_after: sendAfter,
        headings: {
          it: "Promemoria lezione di prova",
          en: "Trial lesson reminder",
        },
        contents: {
          it: `La tua lezione di prova "${name}" è domani (${courseDate}, ${courseTime}). Ti aspettiamo!`,
          en: `Your trial lesson "${name}" is tomorrow (${courseDate}, ${courseTime}). See you there!`,
        },
      })
    );
  }
  if (emailEnabled) {
    tasks.push(
      postOneSignal(apiKey, "Trial Email Reminder", {
        include_aliases: { external_id: [userId] },
        target_channel: "email",
        send_after: sendAfter,
        email_subject: trialReminderSubject(name),
        email_body: trialReminderBody({ courseName: name, courseDate, courseTime }),
      })
    );
  }
  await Promise.all(tasks);
}

/**
 * Notifica via email gli utenti in lista d'attesa che si è liberato un posto, e
 * rimuove dalla waitlist quelli con abbonamento (legacy) scaduto. Rispetta il flag
 * `waitlistEnabled` del corso e le preferenze email utente.
 *
 * NB: push disabilitata (come nel client). Il controllo scadenza usa il campo
 * legacy `fineIscrizione`; gli utenti col nuovo modello (snapshot
 * `activeSubscriptions` non vuoto) sono ESCLUSI dalla rimozione anche se
 * conservano un `fineIscrizione` stantio nel passato.
 */
export async function notifyWaitlistUsers(
  db: Firestore,
  apiKey: string,
  courseId: string
): Promise<void> {
  const course = await getCourseByUid(db, courseId);
  if (!course) return;
  const courseDoc = course.data;
  const courseRef = course.ref;

  const waitlistEnabled = courseDoc.waitlistEnabled !== false;
  if (!waitlistEnabled) return;

  const waitlist: string[] = Array.isArray(courseDoc.waitlist)
    ? courseDoc.waitlist.map((x: unknown) => String(x))
    : [];
  const subscribed = (courseDoc.subscribed as number) ?? 0;
  const capacity = (courseDoc.capacity as number) ?? 0;
  if (waitlist.length === 0) return;
  if (subscribed >= capacity) return;

  const spotsAvailable = capacity - subscribed;
  const startMillis = toMillis(courseDoc.startDate);
  const endMillis = toMillis(courseDoc.endDate);
  if (startMillis === null || endMillis === null) return;

  // Firestore `in` ammette max 30 valori: chunk per sicurezza.
  const chunks: string[][] = [];
  for (let i = 0; i < waitlist.length; i += 30) {
    chunks.push(waitlist.slice(i, i + 30));
  }
  const userDocs: FsData[] = [];
  for (const chunk of chunks) {
    const snap = await db
      .collection("users")
      .where("uid", "in", chunk)
      .get();
    snap.docs.forEach((d) => userDocs.push(d.data()));
  }

  const emailUserIds: string[] = [];
  const expiredUserIds: string[] = [];
  for (const data of userDocs) {
    const uid = data.uid as string;
    const fine = toMillis(data.fineIscrizione);
    const hasSubscriptions =
      Array.isArray(data.activeSubscriptions) && data.activeSubscriptions.length > 0;
    if (!hasSubscriptions && fine !== null && startMillis > fine) {
      expiredUserIds.push(uid);
      continue;
    }
    if (data.emailNotificationsEnabled !== false) emailUserIds.push(uid);
  }

  // Rimuovi gli utenti scaduti dalla waitlist (corso + waitlistCourses).
  if (expiredUserIds.length > 0) {
    const batch = db.batch();
    batch.update(courseRef, {
      waitlist: FieldValue.arrayRemove(...expiredUserIds),
    });
    for (const uid of expiredUserIds) {
      batch.update(db.collection("users").doc(uid), {
        waitlistCourses: FieldValue.arrayRemove(courseId),
      });
    }
    await batch.commit().catch((err) =>
      logger.warn("notifyWaitlistUsers: rimozione scaduti fallita", err)
    );
  }

  if (emailUserIds.length === 0) return;

  const courseDate = formatCourseDate(startMillis);
  const courseTime = formatCourseTime(startMillis, endMillis);
  const name = (courseDoc.name as string) ?? "";

  await postOneSignal(apiKey, "Waitlist Email", {
    include_aliases: { external_id: emailUserIds },
    target_channel: "email",
    email_subject: waitlistSpotAvailableSubject(name),
    email_body: waitlistSpotAvailableBody({
      courseName: name,
      courseDate,
      courseTime,
      spotsAvailable,
    }),
  });
}
