import { HttpsError } from "firebase-functions/v2/https";
import type { Firestore } from "firebase-admin/firestore";
import { HandlerRequest, ONESIGNAL_APP_ID, isStagingIdentityAllowed } from "../handler";
import { calendarUrlsForCourse } from "./calendarLinks";
import {
  trialConfirmationSubject, trialConfirmationBody, trialConfirmationPreheader,
  trialReminderSubject, trialReminderBody, trialReminderPreheader,
  waitlistSpotAvailableSubject, waitlistSpotAvailableBody, waitlistSpotAvailablePreheader,
} from "./emailTemplates";

type TestEnrollmentKind = "waitlist" | "trialReminder" | "trialConfirmation";

export interface TestEnrollmentArgs {
  externalId: string;
  kind: TestEnrollmentKind;
  courseName: string;
  courseDate: string;
  courseTime: string;
  spotsAvailable?: number;
  courseId?: string;
  startMillis?: number;
  endMillis?: number;
  sala?: string;
}

function parseArgs(data: unknown): TestEnrollmentArgs {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "Dati email mancanti");
  }
  const a = data as Record<string, unknown>;
  if (typeof a.externalId !== "string" || !a.externalId.trim() || a.externalId.includes("/") ||
      typeof a.kind !== "string" || !["waitlist", "trialReminder", "trialConfirmation"].includes(a.kind) ||
      ["courseName", "courseDate", "courseTime"].some((key) => typeof a[key] !== "string")) {
    throw new HttpsError("invalid-argument", "Destinatario, tipo e dettagli del corso obbligatori");
  }
  if ((a.sala !== undefined && typeof a.sala !== "string") ||
      (a.courseId !== undefined && typeof a.courseId !== "string") ||
      (a.spotsAvailable !== undefined &&
        (!Number.isInteger(a.spotsAvailable) || Number(a.spotsAvailable) < 1))) {
    throw new HttpsError("invalid-argument", "Sala, corso o numero di posti non validi");
  }
  if (a.kind !== "waitlist" &&
      (typeof a.startMillis !== "number" || !Number.isFinite(a.startMillis) ||
       !Number.isFinite(new Date(a.startMillis).getTime()) ||
       typeof a.endMillis !== "number" || !Number.isFinite(a.endMillis) ||
       !Number.isFinite(new Date(a.endMillis).getTime()) || a.endMillis <= a.startMillis)) {
    throw new HttpsError("invalid-argument", "Orari del corso non validi");
  }
  return { ...a, externalId: a.externalId.trim() } as unknown as TestEnrollmentArgs;
}

export function buildTestEnrollmentPayload(args: TestEnrollmentArgs): Record<string, unknown> {
  const a = parseArgs(args);
  const common = {
    app_id: ONESIGNAL_APP_ID,
    include_aliases: { external_id: [a.externalId] },
    target_channel: "email",
  };
  if (a.kind === "waitlist") {
    return {
      ...common,
      email_subject: `TEST - ${waitlistSpotAvailableSubject(a.courseName)}`,
      email_preheader: waitlistSpotAvailablePreheader(a.courseName),
      email_body: waitlistSpotAvailableBody({ ...a, spotsAvailable: a.spotsAvailable ?? 1 }),
    };
  }
  const trialArgs = {
    ...a,
    ...calendarUrlsForCourse(a.courseId?.trim() || "debug", {
      courseName: a.courseName, startMillis: a.startMillis!, endMillis: a.endMillis!,
      sala: a.sala?.trim() || null,
    }),
  };
  return a.kind === "trialReminder"
    ? { ...common, email_subject: `TEST - ${trialReminderSubject(a.courseName)}`,
        email_preheader: trialReminderPreheader(a.courseName), email_body: trialReminderBody(trialArgs) }
    : { ...common, email_subject: `TEST - ${trialConfirmationSubject(a.courseName)}`,
        email_preheader: trialConfirmationPreheader(a.courseName), email_body: trialConfirmationBody(trialArgs) };
}

export interface TestEmailDeps {
  db: Firestore;
  post: (payload: Record<string, unknown>, apiKey: string) => Promise<Record<string, unknown>>;
  ensure: (externalId: string, email: string, apiKey: string) => Promise<unknown>;
}

export async function sendTestEnrollmentEmailHandler(
  request: HandlerRequest, apiKey: string, deps: TestEmailDeps,
): Promise<Record<string, unknown>> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login richiesto");
  const actor = await deps.db.collection("users").doc(request.auth.uid).get();
  if (actor.data()?.role !== "Admin") {
    throw new HttpsError("permission-denied", "Solo un Admin può inviare email di test");
  }
  const a = parseArgs(request.data);
  const recipient = await deps.db.collection("users").doc(a.externalId).get();
  if (!recipient.exists) throw new HttpsError("not-found", "Profilo destinatario non trovato");
  const rawEmail: unknown = recipient.data()?.email;
  const email = typeof rawEmail === "string" ? rawEmail.trim().toLowerCase() : "";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("failed-precondition", "Il destinatario non ha un'email valida");
  }
  // Prima dell'ensure: un invio di debug non può aggirare l'allowlist staging.
  if (!isStagingIdentityAllowed(a.externalId, email)) return { suppressed: true };
  const ensured = await deps.ensure(a.externalId, email, apiKey) as { suppressed?: boolean } | undefined;
  if (ensured?.suppressed) return { suppressed: true };
  const result = await deps.post(buildTestEnrollmentPayload(a), apiKey);
  if (result.suppressed === true) return result;
  if (typeof result.id !== "string" || !result.id || result.recipients === 0) {
    throw new HttpsError("unavailable", "OneSignal non ha accettato l'invio dell'email");
  }
  return result;
}
