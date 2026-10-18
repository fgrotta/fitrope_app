import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import {
  sendOneSignalNotificationHandler,
  ensureOneSignalUserHandler,
  removeOneSignalEmailHandler,
  ensureOneSignalEmailSubscription,
  postToOneSignal,
} from "./handler";
import {
  runCertificateEmails,
  sendTestCertificateEmailHandler,
} from "./certificateEmails";
import { assignSubscriptionHandler } from "./enrollment/assignSubscription";
import {
  revokeSubscriptionHandler,
  updateSubscriptionHandler,
} from "./enrollment/manageSubscription";
import {
  createManagedUserHandler,
  checkEmailAvailabilityHandler,
  grantSignupTrialHandler,
  setManagedUserEmailHandler,
} from "./enrollment/provisioning";
import {
  subscribeToCourseHandler,
  unsubscribeFromCourseHandler,
  joinWaitlistHandler,
  leaveWaitlistHandler,
} from "./enrollment/enrollment";
import {
  deleteCourseHandler,
  recountCourseSubscribedHandler,
} from "./enrollment/admin";
import { setAttendanceHandler } from "./enrollment/attendance";
import {
  scheduleTrialReminder,
  sendTrialEnrollmentConfirmation,
  notifyWaitlistUsers,
  getCourseByUid,
} from "./enrollment/notify";
import { buildCourseIcs } from "./enrollment/ics";
import {
  BACKUP_BUCKET,
  checkFirestoreBackup,
  runFirestoreBackup,
} from "./firestoreBackup";
import { v1 } from "@google-cloud/firestore";
import {
  migrateLegacyUserHandler,
  previewLegacyUserMigrationHandler,
} from "./migration/userHandler";
import { isStagingCloneMode, stagingCloneGuarded } from "./stagingCloneGuard";
import {
  readMetaSettings,
  whatsappDemoMode,
  whatsappTransportName,
} from "./whatsapp/environment";
import { makeTransport } from "./whatsapp/makeClient";
import { metaTransport } from "./whatsapp/metaClient";
import { WhatsappTransport } from "./whatsapp/transport";
import { WhatsappDeps, notifyDemoLessonBooked } from "./whatsapp/demoLesson";
import { runDemoLessonReminders } from "./whatsapp/reminders";
import { sendTestDemoLessonWebhookHandler } from "./whatsapp/testWebhook";
import { handleStatusWebhook } from "./whatsapp/statusWebhook";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

// Secret gestito da Google Secret Manager.
// Setup: firebase functions:secrets:set ONESIGNAL_REST_API_KEY
const oneSignalApiKey = defineSecret("ONESIGNAL_REST_API_KEY");

// ──────────────────────────────────────────────
//  WhatsApp lezioni demo (Make o Meta Cloud API)
// ──────────────────────────────────────────────
//
// WHATSAPP_DEMO_MODE, in `.env.<projectId>`, viene letta in DISCOVERY come i
// gate dei certificati:
//   off (default) → nessuna function e nessun secret dichiarato;
//   test          → solo la callable di prova (Admin), per verificare il canale;
//   live          → + WhatsApp di conferma in subscribeToCourse + cron delle 19:00.
// Mergiare significa deployare: è questo gate, e non la scelta di cosa
// deployare, a tenere spento il cron finché canale e template non sono pronti.
//
// WHATSAPP_TRANSPORT (make, default | meta) sceglie il canale e quindi i secret:
//   make → MAKE_WEBHOOK_URL + MAKE_WEBHOOK_KEY;
//   meta → META_WA_ACCESS_TOKEN sugli invii, META_APP_SECRET +
//          META_WA_VERIFY_TOKEN solo sul webhook di stato.
// I secret vengono dichiarati solo se servono: dichiararne uno che nel progetto
// non esiste fa fallire `firebase deploy`. Con `meta` la discovery legge e
// valida anche numero e template (readMetaSettings), e fallisce subito se mancano.
const whatsappMode = whatsappDemoMode(process.env);
const whatsappTransportKind =
  whatsappMode === "off" ? null : whatsappTransportName(process.env);
const metaSettings =
  whatsappTransportKind === "meta" ? readMetaSettings(process.env) : null;
const makeSecret =
  whatsappTransportKind === "make"
    ? {
        url: defineSecret("MAKE_WEBHOOK_URL"),
        key: defineSecret("MAKE_WEBHOOK_KEY"),
      }
    : null;
const metaAccessToken =
  whatsappTransportKind === "meta" ? defineSecret("META_WA_ACCESS_TOKEN") : null;
const metaWebhookSecret =
  whatsappTransportKind === "meta"
    ? {
        appSecret: defineSecret("META_APP_SECRET"),
        verifyToken: defineSecret("META_WA_VERIFY_TOKEN"),
      }
    : null;
const whatsappSendSecrets = makeSecret
  ? [makeSecret.url, makeSecret.key]
  : metaAccessToken
    ? [metaAccessToken]
    : [];
// La conferma all'iscrizione: Make la manda sempre (il Router sceglie il
// template da `tipo`), Meta solo se è configurato un template apposito.
const whatsappBookedEnabled =
  whatsappMode === "live" &&
  (makeSecret !== null || metaSettings?.templates.booked !== undefined);

function makeWhatsappTransport(): WhatsappTransport {
  if (makeSecret) {
    return makeTransport(makeSecret.url.value(), makeSecret.key.value());
  }
  if (metaSettings && metaAccessToken) {
    return metaTransport({ ...metaSettings, accessToken: metaAccessToken.value() });
  }
  throw new HttpsError(
    "failed-precondition",
    "WhatsApp demo disattivato (WHATSAPP_DEMO_MODE=off)",
  );
}

function makeWhatsappDeps(): WhatsappDeps {
  return {
    db: admin.firestore(),
    transport: makeWhatsappTransport(),
    nowMillis: Date.now(),
    env: process.env,
  };
}

/**
 * Proxy verso OneSignal REST API.
 * Il client invia il body OneSignal già formattato (include_aliases, headings,
 * contents, target_channel, send_after, email_subject, email_body, ...).
 */
export const sendOneSignalNotification = onCall(
  {
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
  },
  stagingCloneGuarded((request) =>
    sendOneSignalNotificationHandler(
      { auth: request.auth ?? null, data: request.data },
      oneSignalApiKey.value(),
      { db: admin.firestore(), ensure: ensureOneSignalEmailSubscription },
    )),
);

/**
 * Crea o aggiorna l'utente OneSignal con la sua email subscription.
 * Va chiamata al login per garantire che l'utente esista sul backend OneSignal
 * prima di poter ricevere notifiche email via `include_aliases.external_id`.
 *
 * Payload atteso: { externalId: string, email?: string }
 */
export const ensureOneSignalUser = onCall(
  {
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
  },
  stagingCloneGuarded((request) =>
    ensureOneSignalUserHandler(
      { auth: request.auth ?? null, data: request.data },
      oneSignalApiKey.value(),
    )),
);

/**
 * Disabilita la subscription email OneSignal dell'utente autenticato.
 *
 * Payload atteso: { email: string }
 */
export const removeOneSignalEmail = onCall(
  {
    secrets: [oneSignalApiKey],
    region: "europe-west8",
    cors: true,
  },
  stagingCloneGuarded((request) =>
    removeOneSignalEmailHandler(
      { auth: request.auth ?? null, data: request.data },
      oneSignalApiKey.value(),
    )),
);

/**
 * Assegna un abbonamento a un utente (solo Admin). Crea il documento in
 * `subscriptions` e ricalcola lo snapshot `activeSubscriptions` sul doc utente.
 *
 * Payload atteso: { userId: string, planKey: string, startDateMillis?: number,
 * endDateMillis?: number }. Una Prova sovrapposta viene revocata e sostituita.
 */
export const assignSubscription = onCall(
  {
    region: "europe-west8",
    cors: true,
  },
  stagingCloneGuarded((request) =>
    assignSubscriptionHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

/**
 * Modifica un abbonamento (solo Admin): piano, date e ingressi residui.
 *
 * Payload: { subscriptionId, planKey, startDateMillis, endDateMillis, remainingEntries? }
 */
export const updateSubscription = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    updateSubscriptionHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

/** Revoca un abbonamento (solo Admin) conservandone lo storico. Payload: { subscriptionId } */
export const revokeSubscription = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    revokeSubscriptionHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

export const createManagedUser = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) => createManagedUserHandler(
    { auth: request.auth ?? null, data: request.data }, admin.firestore(),
  )),
);

export const checkEmailAvailability = onCall(
  { region: "europe-west8", cors: true },
  (request) => checkEmailAvailabilityHandler(
    { auth: request.auth ?? null, data: request.data }, admin.firestore(), admin.auth(),
  ),
);

export const setManagedUserEmail = onCall(
  { region: "europe-west8", cors: true },
  (request) => setManagedUserEmailHandler(
    { auth: request.auth ?? null, data: request.data }, admin.firestore(), admin.auth(),
  ),
);

export const grantSignupTrial = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) => grantSignupTrialHandler(
    { auth: request.auth ?? null, data: request.data }, admin.firestore(),
  )),
);

/** Anteprima non mutante della conversione legacy di un singolo utente (Admin). */
export const previewLegacyUserMigration = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    previewLegacyUserMigrationHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

/** Normalizzazione e conversione legacy Admin, protette da fingerprint e transazione. */
export const migrateLegacyUser = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    migrateLegacyUserHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

/**
 * Iscrizione a un corso (server-authoritative): valida idoneità/capienza, scala
 * gli ingressi dell'abbonamento giusto e aggiorna lo snapshot, in transazione.
 *
 * Payload: { courseId: string, userId: string, force?: boolean }
 */
export const subscribeToCourse = onCall(
  {
    region: "europe-west8",
    cors: true,
    secrets: whatsappBookedEnabled
      ? [oneSignalApiKey, ...whatsappSendSecrets]
      : [oneSignalApiKey],
  },
  stagingCloneGuarded((request) =>
    subscribeToCourseHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
      {
        notifyTrialReminder: (userId, courseId) =>
          scheduleTrialReminder(
            admin.firestore(),
            oneSignalApiKey.value(),
            userId,
            courseId,
            Date.now(),
          ),
        notifyTrialConfirmation: (userId, courseId) =>
          sendTrialEnrollmentConfirmation(
            admin.firestore(),
            oneSignalApiKey.value(),
            userId,
            courseId,
            Date.now(),
          ),
        // async: anche un errore sincrono (es. secret non leggibile) diventa un
        // rifiuto, che subscribeToCourseHandler ignora come le altre notifiche.
        // Senza async farebbe fallire un'iscrizione già committata.
        ...(whatsappBookedEnabled
          ? {
              notifyTrialWhatsapp: async (userId: string, courseId: string) => {
                await notifyDemoLessonBooked(makeWhatsappDeps(), userId, courseId);
              },
            }
          : {}),
      },
    )),
);

/**
 * Serve il file iCalendar della lezione, linkato dal bottone "Apple / Outlook /
 * altro" nelle email della prova. Endpoint HTTP e non callable perché il click
 * arriva da un client email: nessun SDK, solo una GET.
 *
 * Pubblico e non autenticato per necessità (le email non portano credenziali),
 * ma espone solo nome corso, orario e sala — dati che qualsiasi socio già vede —
 * e il `courseId` è un auto-ID Firestore a 20 caratteri, non enumerabile.
 */
export const courseIcs = onRequest(
  { region: "europe-west8", cors: true },
  async (req, res) => {
    if (isStagingCloneMode()) {
      res.status(403).send("Endpoint non disponibile sul clone staging");
      return;
    }
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.status(405).set("Allow", "GET, HEAD").send("Metodo non consentito");
      return;
    }

    const raw = req.query.courseId;
    const courseId = typeof raw === "string" ? raw.trim() : "";
    if (!courseId) {
      res.status(400).send("Parametro courseId mancante");
      return;
    }

    let course: Awaited<ReturnType<typeof getCourseByUid>>;
    try {
      course = await getCourseByUid(admin.firestore(), courseId);
    } catch (err) {
      logger.error("courseIcs: lettura corso fallita", err);
      res.status(500).send("Errore interno");
      return;
    }
    if (!course) {
      res.status(404).send("Corso non trovato");
      return;
    }

    const data = course.data;
    const startMillis = data.startDate?.toMillis?.();
    const endMillis = data.endDate?.toMillis?.();
    if (typeof startMillis !== "number" || typeof endMillis !== "number") {
      logger.warn("courseIcs: corso senza date valide", { courseId });
      res.status(404).send("Corso senza date valide");
      return;
    }

    const ics = buildCourseIcs({
      courseId,
      courseName: (data.name as string) ?? "Lezione",
      startMillis,
      endMillis,
      sala: (data.sala as string | undefined) ?? null,
      nowMillis: Date.now(),
    });

    // no-store: il corso può essere spostato o cancellato dopo l'invio
    // dell'email, l'.ics deve riflettere Firestore e non una copia congelata.
    res
      .status(200)
      .set("Content-Type", "text/calendar; charset=utf-8")
      .set("Content-Disposition", 'attachment; filename="lezione.ics"')
      .set("Cache-Control", "no-store")
      .send(ics);
  }
);

/**
 * Disiscrizione da un corso: applica le finestre di rimborso (8h ingressi / 4h
 * frequenza), ripristina il credito dovuto, traccia le disiscrizioni perse e
 * notifica la waitlist, in transazione.
 *
 * Payload: { courseId: string, userId: string, confirmedNoRefund?: boolean }
 */
export const unsubscribeFromCourse = onCall(
  { region: "europe-west8", cors: true, secrets: [oneSignalApiKey] },
  stagingCloneGuarded((request) =>
    unsubscribeFromCourseHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
      {
        notifyWaitlist: (courseId) =>
          notifyWaitlistUsers(
            admin.firestore(),
            oneSignalApiKey.value(),
            courseId,
          ),
      },
    )),
);

/**
 * Iscrizione alla lista d'attesa di un corso pieno.
 *
 * Payload: { courseId: string, userId: string }
 */
export const joinWaitlist = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    joinWaitlistHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

/**
 * Rimozione dalla lista d'attesa (self oppure Admin/Trainer su altri).
 *
 * Payload: { courseId: string, userId: string }
 */
export const leaveWaitlist = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    leaveWaitlistHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

/**
 * Cancella un corso rimborsando tutti gli iscritti e ripulendo le waitlist
 * (Admin/Trainer), in una transazione atomica.
 *
 * Payload: { courseId: string }
 */
export const deleteCourse = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    deleteCourseHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

/**
 * Ricalcola il contatore `subscribed` di un corso dalla fonte di verità
 * (Admin/Trainer). Sostituisce la correzione manuale client-side.
 *
 * Payload: { courseId: string }
 */
export const recountCourseSubscribed = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    recountCourseSubscribedHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

/**
 * Registra la presenza effettiva a un corso: check-in del socio (solo
 * presente, da 15' prima a 30' dopo l'inizio) oppure appello dello staff
 * (Admin, o Trainer del corso, da 30' prima in poi, presente o assente).
 * Guardata sul clone staging: un socio clonato non deve scrivere presenze.
 *
 * Payload: { courseId: string, userId?: string, present: boolean }
 */
export const setAttendance = onCall(
  { region: "europe-west8", cors: true },
  stagingCloneGuarded((request) =>
    setAttendanceHandler(
      { auth: request.auth ?? null, data: request.data },
      admin.firestore(),
    )),
);

// ──────────────────────────────────────────────
//  Email certificati — SOLO emulatore e staging
// ──────────────────────────────────────────────
//
// Le funzioni certificati non devono esistere in produzione finché la feature
// non viene promossa. Il gate agisce in fase di DISCOVERY: la CLI Firebase
// carica `.env.<projectId>` prima di enumerare gli export, quindi su staging
// (`.env.fit-rope-staging` con APP_ENV=staging, scritto da staging.yml) le
// funzioni vengono deployate, mentre in prod — dove quel file non esiste —
// l'export è undefined e la CLI le ignora. Sull'emulatore il runtime imposta
// FUNCTIONS_EMULATOR=true. La stessa condizione è rivalutata a runtime come
// guardia difensiva contro un deploy con env sbagliata.
function certificateFunctionsEnabled(): boolean {
  return (
    process.env.APP_ENV === "staging" ||
    process.env.FUNCTIONS_EMULATOR === "true"
  );
}

// I backup PRD devono essere discoverable solo nell'ambiente di produzione:
// staging ed Emulator non devono mai esportare dati né creare Scheduler job.
function firestoreBackupEnabled(): boolean {
  return (
    process.env.APP_ENV !== "staging" &&
    process.env.FUNCTIONS_EMULATOR !== "true"
  );
}

const firestoreBackupDaily = firestoreBackupEnabled()
  ? onSchedule(
      {
        schedule: "0 2 * * *",
        timeZone: "UTC",
        region: "europe-west8",
        serviceAccount:
          "fitrope-firestore-backup@fit-rope-app-1f575.iam.gserviceaccount.com",
        timeoutSeconds: 540,
        maxInstances: 1,
        retryCount: 3,
        minBackoffSeconds: 30,
      },
      async (event) => {
        if (!firestoreBackupEnabled()) return;
        const bucket = admin.storage().bucket(BACKUP_BUCKET);
        await runFirestoreBackup({
          db: admin.firestore(),
          adminClient: new v1.FirestoreAdminClient(),
          projectId: process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT,
          now: () => new Date(),
          scheduledAt: new Date(event.scheduleTime),
          writeManifest: async (path, body) => {
            await bucket.file(path).save(`${JSON.stringify(body, null, 2)}\n`, {
              contentType: "application/json",
              resumable: false,
            });
          },
        });
      },
    )
  : undefined;

const firestoreBackupDailyCheck = firestoreBackupEnabled()
  ? onSchedule(
      {
        schedule: "0 3 * * *",
        timeZone: "UTC",
        region: "europe-west8",
        serviceAccount:
          "fitrope-firestore-backup@fit-rope-app-1f575.iam.gserviceaccount.com",
        timeoutSeconds: 60,
        maxInstances: 1,
      },
      async (event) => {
        if (!firestoreBackupEnabled()) return;
        await checkFirestoreBackup(
          admin.firestore(),
          new Date(event.scheduleTime),
        );
      },
    )
  : undefined;

export { firestoreBackupDaily, firestoreBackupDailyCheck };

/**
 * Invio di test delle email certificato (DebugEmailPage, kDebugMode).
 * Payload: { externalId: string, firstName?: string, kind?: "reminder10"|"expiryToday", email?: string }
 */
export const sendTestCertificateEmail = certificateFunctionsEnabled()
  ? onCall(
      { secrets: [oneSignalApiKey], region: "europe-west8", cors: true },
      stagingCloneGuarded((request) => {
        if (!certificateFunctionsEnabled()) {
          throw new HttpsError(
            "failed-precondition",
            "Funzione disponibile solo su emulatore e staging",
          );
        }
        return sendTestCertificateEmailHandler(
          { auth: request.auth ?? null, data: request.data },
          oneSignalApiKey.value(),
        );
      }),
    )
  : undefined;

/**
 * Run giornaliero delle email certificato: promemoria a chi scade tra 10 giorni
 * e avviso a chi scade oggi (08:00 Europe/Rome). In staging gli invii restano
 * comunque filtrati dalla allowlist dentro postToOneSignal/ensure (UID stg_ +
 * STAGING_NOTIFICATION_EMAIL_ALLOWLIST).
 */
export const certificateEmailsDaily = certificateFunctionsEnabled()
  ? onSchedule(
      {
        schedule: "0 8 * * *",
        timeZone: "Europe/Rome",
        region: "europe-west8",
        secrets: [oneSignalApiKey],
      },
      async () => {
        if (!certificateFunctionsEnabled() || isStagingCloneMode()) {
          logger.warn(
            "certificateEmailsDaily invocata fuori da emulatore/staging: no-op",
          );
          return;
        }
        await runCertificateEmails({
          db: admin.firestore(),
          apiKey: oneSignalApiKey.value(),
          post: postToOneSignal,
          ensure: ensureOneSignalEmailSubscription,
          now: new Date(),
        });
      },
    )
  : undefined;

/**
 * WhatsApp di prova verso il numero indicato (DebugEmailPage, kDebugMode).
 * Solo Admin. Esiste con WHATSAPP_DEMO_MODE=test|live.
 * Payload: { numeroTelefono: string, kind?: "booked"|"reminder", nome?, corso?, giorno?, orario? }
 */
export const sendTestDemoLessonWebhook =
  whatsappMode === "off"
    ? undefined
    : onCall(
        { secrets: whatsappSendSecrets, region: "europe-west8", cors: true },
        stagingCloneGuarded((request) =>
          sendTestDemoLessonWebhookHandler(
            { auth: request.auth ?? null, data: request.data },
            makeWhatsappDeps(),
          )),
      );

/**
 * Promemoria WhatsApp delle lezioni di prova di domani, ogni sera alle 19:00
 * Europe/Rome. Esiste solo con WHATSAPP_DEMO_MODE=live. La condizione viene
 * rivalutata a runtime come guardia difensiva, come per i certificati.
 */
export const sendDemoLessonWhatsappReminders =
  whatsappMode === "live"
    ? onSchedule(
        {
          schedule: "0 19 * * *",
          timeZone: "Europe/Rome",
          region: "europe-west8",
          secrets: whatsappSendSecrets,
          timeoutSeconds: 540,
          maxInstances: 1,
          retryCount: 3,
          minBackoffSeconds: 30,
        },
        async (event) => {
          if (whatsappDemoMode(process.env) !== "live" || isStagingCloneMode()) {
            logger.warn(
              "sendDemoLessonWhatsappReminders fuori da WHATSAPP_DEMO_MODE=live o su clone staging: no-op",
            );
            return;
          }
          await runDemoLessonReminders(makeWhatsappDeps(), {
            scheduledAtMillis: new Date(event.scheduleTime).getTime(),
            deadlineMillis: Date.now() + 480_000,
          });
        },
      )
    : undefined;

/**
 * Webhook di stato della Cloud API Meta: verifica GET dell'URL e stati di
 * consegna (sent/delivered/read/failed) riconciliati sul registro invii.
 * Esiste solo con WHATSAPP_TRANSPORT=meta e WHATSAPP_DEMO_MODE=test|live.
 * Pubblico per necessità (lo chiama Meta): la protezione è la firma HMAC.
 * L'URL va configurato in Meta DOPO il deploy: Meta fa il GET di verifica al
 * salvataggio.
 */
export const whatsappStatusWebhook = metaWebhookSecret
  ? onRequest(
      {
        region: "europe-west8",
        secrets: [metaWebhookSecret.appSecret, metaWebhookSecret.verifyToken],
      },
      async (req, res) => {
        const result = await handleStatusWebhook(
          {
            method: req.method,
            query: req.query as Record<string, unknown>,
            headers: req.headers,
            rawBody: req.rawBody,
          },
          {
            db: admin.firestore(),
            appSecret: metaWebhookSecret.appSecret.value(),
            verifyToken: metaWebhookSecret.verifyToken.value(),
          },
        );
        res.status(result.status).type("text/plain").send(result.body);
      },
    )
  : undefined;
