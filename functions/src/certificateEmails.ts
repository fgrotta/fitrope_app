import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import {
  ONESIGNAL_APP_ID,
  postToOneSignal,
  ensureOneSignalEmailSubscription,
  HandlerRequest,
} from "./handler";
import {
  certificateReminderSubject,
  certificateExpiryTodaySubject,
  certificateReminderBody,
  certificateExpiryTodayBody,
} from "./certificateEmailTemplates";
import { romeDayWindow, RomeDayWindow } from "./romeTime";

// Ri-esportati per compatibilità: erano definiti qui prima dell'estrazione in ./romeTime.
export { romeDayWindow };
export type { RomeDayWindow };

// ──────────────────────────────────────────────
//  Tipi
// ──────────────────────────────────────────────

export type EmailKind = "reminder10" | "expiryToday";

export interface CandidateUser {
  uid: string;
  name: string;
  email: string | null;
  isActive: boolean;
  emailNotificationsEnabled: boolean;
  certificatoScadenza: Timestamp | null;
}

interface UserDocLike {
  id: string;
  data: () => Record<string, unknown> | undefined;
}

// ──────────────────────────────────────────────
//  Query + filtro
// ──────────────────────────────────────────────

/** Mappa un documento Firestore in CandidateUser, applicando i default. */
export function mapUserDoc(doc: UserDocLike): CandidateUser {
  const data = doc.data() ?? {};
  return {
    uid: (data.uid as string) ?? doc.id,
    name: (data.name as string) ?? "",
    email: (data.email as string | undefined) ?? null,
    isActive: (data.isActive as boolean | undefined) ?? true,
    emailNotificationsEnabled:
      (data.emailNotificationsEnabled as boolean | undefined) ?? true,
    certificatoScadenza: (data.certificatoScadenza as Timestamp | undefined) ?? null,
  };
}

/**
 * Query Firestore degli utenti con `certificatoScadenza` nella finestra.
 * Solo filtri di range su un campo → nessun indice composito necessario.
 */
export async function queryUsersInWindow(
  firestore: Firestore,
  window: RomeDayWindow
): Promise<CandidateUser[]> {
  const snap = await firestore
    .collection("users")
    .where("certificatoScadenza", ">=", Timestamp.fromMillis(window.startMs))
    .where("certificatoScadenza", "<=", Timestamp.fromMillis(window.endMs))
    .get();

  return snap.docs.map((doc) => mapUserDoc(doc));
}

/** Tiene solo utenti attivi, con email abilitate e certificato presente. */
export function selectRecipients(users: CandidateUser[]): CandidateUser[] {
  return users.filter(
    (u) =>
      u.isActive === true &&
      u.emailNotificationsEnabled !== false &&
      !!u.certificatoScadenza
  );
}

// ──────────────────────────────────────────────
//  Payload + orchestrazione
// ──────────────────────────────────────────────

/**
 * Costruisce il payload OneSignal per un utente. `app_id` è iniettato qui perché
 * il percorso schedulato chiama `postToOneSignal` direttamente (che non lo inietta).
 * Nessun `send_after` → invio immediato.
 */
export function buildCertificateEmailPayload(
  user: CandidateUser,
  kind: EmailKind,
  subjectPrefix = ""
): Record<string, unknown> {
  const firstName = (user.name ?? "").trim();
  const subject =
    kind === "reminder10"
      ? certificateReminderSubject()
      : certificateExpiryTodaySubject();
  const body =
    kind === "reminder10"
      ? certificateReminderBody(firstName)
      : certificateExpiryTodayBody(firstName);
  return {
    app_id: ONESIGNAL_APP_ID,
    include_aliases: { external_id: [user.uid] },
    target_channel: "email",
    email_subject: `${subjectPrefix}${subject}`,
    email_body: body,
  };
}

export interface RunDeps {
  db: Firestore;
  apiKey: string;
  post: (payload: Record<string, unknown>, apiKey: string) => Promise<unknown>;
  /**
   * Garantisce che l'utente OneSignal esista con la subscription email, partendo
   * dall'email di Firestore. Necessario perché OneSignal consegna via external_id
   * solo se la subscription esiste: senza questo, i membri che non si sono mai
   * loggati (subscription creata al login) non riceverebbero l'email.
   */
  ensure: (
    externalId: string,
    email: string | undefined,
    apiKey: string
  ) => Promise<unknown>;
  now: Date;
}

/**
 * Logica del run giornaliero: invia il promemoria a chi scade tra 10 giorni e
 * l'avviso a chi scade oggi. Per ogni destinatario assicura prima la subscription
 * email OneSignal (vedi RunDeps.ensure), poi invia. Try/catch per utente così un
 * errore su un destinatario non interrompe il run né innesca retry dello scheduler.
 */
export async function runCertificateEmails(
  deps: RunDeps
): Promise<{ reminderSent: number; expirySent: number }> {
  const [reminderUsers, expiryUsers] = await Promise.all([
    queryUsersInWindow(deps.db, romeDayWindow(deps.now, 10)),
    queryUsersInWindow(deps.db, romeDayWindow(deps.now, 0)),
  ]);

  const sendBatch = async (
    users: CandidateUser[],
    kind: EmailKind
  ): Promise<number> => {
    let sent = 0;
    for (const u of selectRecipients(users)) {
      try {
        if (u.email) {
          await deps.ensure(u.uid, u.email, deps.apiKey);
        }
        await deps.post(buildCertificateEmailPayload(u, kind), deps.apiKey);
        sent++;
      } catch (err) {
        logger.error("Invio email certificato fallito", { uid: u.uid, kind, err });
      }
    }
    return sent;
  };

  const reminderSent = await sendBatch(reminderUsers, "reminder10");
  const expirySent = await sendBatch(expiryUsers, "expiryToday");

  logger.info("Certificate emails run completata", { reminderSent, expirySent });
  return { reminderSent, expirySent };
}

// ──────────────────────────────────────────────
//  Handler della callable di test (DebugEmailPage)
// ──────────────────────────────────────────────

/**
 * Invia una delle due email di certificato a un singolo utente per test manuale.
 * Renderizza il template TS (single-source) e aggiunge il prefisso "TEST - ".
 * Payload atteso: { externalId: string, firstName?: string, kind?: EmailKind }
 */
export async function sendTestCertificateEmailHandler(
  request: HandlerRequest,
  apiKey: string
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }
  const payload = request.data as
    | { externalId?: string; firstName?: string; kind?: string; email?: string }
    | null;
  if (!payload || typeof payload !== "object" || !payload.externalId) {
    throw new HttpsError("invalid-argument", "externalId obbligatorio");
  }

  const kind: EmailKind =
    payload.kind === "expiryToday" ? "expiryToday" : "reminder10";
  const user: CandidateUser = {
    uid: payload.externalId,
    name: payload.firstName ?? "",
    email: payload.email?.trim() ?? null,
    isActive: true,
    emailNotificationsEnabled: true,
    certificatoScadenza: null,
  };

  // Come il cron, assicura la subscription email così il test funziona anche
  // verso utenti che non si sono mai loggati.
  if (user.email) {
    await ensureOneSignalEmailSubscription(user.uid, user.email, apiKey);
  }
  return postToOneSignal(buildCertificateEmailPayload(user, kind, "TEST - "), apiKey);
}
