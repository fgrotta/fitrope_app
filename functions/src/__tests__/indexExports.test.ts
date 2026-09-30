// Gate ambiente delle funzioni certificati: devono esistere SOLO su emulatore
// (FUNCTIONS_EMULATOR=true) e staging (APP_ENV=staging). In produzione l'export
// deve essere undefined, così la CLI Firebase non le deploya in discovery.
// Il require avviene dentro jest.isolateModules per rieseguire index.ts con
// l'env manipolata (admin.initializeApp è guardato da apps.length).

type IndexModule = {
  sendTestCertificateEmail: unknown;
  certificateEmailsDaily: unknown;
  sendOneSignalNotification: unknown;
  checkEmailAvailability: unknown;
  setManagedUserEmail: unknown;
  subscribeToCourse: unknown;
  setAttendance: unknown;
  updateSubscription: unknown;
  revokeSubscription: unknown;
  courseIcs: unknown;
  firestoreBackupDaily: unknown;
  firestoreBackupDailyCheck: unknown;
  sendTestDemoLessonWebhook: unknown;
  sendDemoLessonWhatsappReminders: unknown;
  whatsappStatusWebhook: unknown;
};

function loadIndex(): IndexModule {
  let mod: IndexModule | undefined;
  jest.isolateModules(() => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    mod = require("../index") as IndexModule;
  });
  return mod as IndexModule;
}

describe("gate ambiente funzioni certificati (export condizionale in index.ts)", () => {
  const savedAppEnv = process.env.APP_ENV;
  const savedEmulator = process.env.FUNCTIONS_EMULATOR;

  afterEach(() => {
    if (savedAppEnv === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = savedAppEnv;
    if (savedEmulator === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = savedEmulator;
  });

  test("produzione (nessuna env): certificati NON esportati, il resto sì", () => {
    delete process.env.APP_ENV;
    delete process.env.FUNCTIONS_EMULATOR;
    const mod = loadIndex();
    expect(mod.sendTestCertificateEmail).toBeUndefined();
    expect(mod.certificateEmailsDaily).toBeUndefined();
    // Le callable ordinarie non devono essere toccate dal gate.
    expect(mod.sendOneSignalNotification).toBeDefined();
    expect(mod.checkEmailAvailability).toBeDefined();
    expect(mod.setManagedUserEmail).toBeDefined();
    expect(mod.subscribeToCourse).toBeDefined();
    expect(mod.setAttendance).toBeDefined();
    expect(mod.updateSubscription).toBeDefined();
    expect(mod.revokeSubscription).toBeDefined();
    // courseIcs serve i link "aggiungi al calendario" delle email: va in prod.
    expect(mod.courseIcs).toBeDefined();
    expect(mod.firestoreBackupDaily).toBeDefined();
    expect(mod.firestoreBackupDailyCheck).toBeDefined();
  });

  test("staging (APP_ENV=staging): certificati esportati", () => {
    process.env.APP_ENV = "staging";
    delete process.env.FUNCTIONS_EMULATOR;
    const mod = loadIndex();
    expect(mod.sendTestCertificateEmail).toBeDefined();
    expect(mod.certificateEmailsDaily).toBeDefined();
    expect(mod.firestoreBackupDaily).toBeUndefined();
    expect(mod.firestoreBackupDailyCheck).toBeUndefined();
  });

  test("emulatore (FUNCTIONS_EMULATOR=true): certificati esportati", () => {
    delete process.env.APP_ENV;
    process.env.FUNCTIONS_EMULATOR = "true";
    const mod = loadIndex();
    expect(mod.sendTestCertificateEmail).toBeDefined();
    expect(mod.certificateEmailsDaily).toBeDefined();
    expect(mod.firestoreBackupDaily).toBeUndefined();
    expect(mod.firestoreBackupDailyCheck).toBeUndefined();
  });
});

/** Nomi dei secret legati a una function (letti dal manifest che usa la CLI). */
function secretKeys(fn: unknown): string[] {
  const endpoint = (
    fn as { __endpoint?: { secretEnvironmentVariables?: Array<{ key: string }> } }
  ).__endpoint;
  return (endpoint?.secretEnvironmentVariables ?? []).map((s) => s.key).sort();
}

const WHATSAPP_ENV_KEYS = [
  "WHATSAPP_DEMO_MODE",
  "WHATSAPP_TRANSPORT",
  "META_GRAPH_VERSION",
  "META_WA_PHONE_NUMBER_ID",
  "META_WA_TEMPLATE_REMINDER",
  "META_WA_TEMPLATE_BOOKED",
  "META_WA_TEMPLATE_LANG",
  "APP_ENV",
  "FUNCTIONS_EMULATOR",
];

describe("gate WHATSAPP_DEMO_MODE (export condizionale in index.ts)", () => {
  const saved = Object.fromEntries(WHATSAPP_ENV_KEYS.map((key) => [key, process.env[key]]));

  beforeEach(() => {
    for (const key of WHATSAPP_ENV_KEYS) delete process.env[key];
  });

  afterEach(() => {
    for (const key of WHATSAPP_ENV_KEYS) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  });

  test("off (default): nessuna function WhatsApp, subscribeToCourse senza secret Make", () => {
    delete process.env.WHATSAPP_DEMO_MODE;
    const mod = loadIndex();
    expect(mod.sendTestDemoLessonWebhook).toBeUndefined();
    expect(mod.sendDemoLessonWhatsappReminders).toBeUndefined();
    // La prima asserzione valida anche il selettore: se __endpoint cambiasse
    // forma, fallirebbe qui invece di passare in silenzio.
    expect(secretKeys(mod.subscribeToCourse)).toEqual(["ONESIGNAL_REST_API_KEY"]);
  });

  test("valore sconosciuto: come off", () => {
    process.env.WHATSAPP_DEMO_MODE = "si";
    const mod = loadIndex();
    expect(mod.sendTestDemoLessonWebhook).toBeUndefined();
    expect(mod.sendDemoLessonWhatsappReminders).toBeUndefined();
  });

  test("test: solo la callable di prova, con i secret Make", () => {
    process.env.WHATSAPP_DEMO_MODE = "test";
    const mod = loadIndex();
    expect(secretKeys(mod.sendTestDemoLessonWebhook)).toEqual([
      "MAKE_WEBHOOK_KEY",
      "MAKE_WEBHOOK_URL",
    ]);
    expect(mod.sendDemoLessonWhatsappReminders).toBeUndefined();
    expect(secretKeys(mod.subscribeToCourse)).toEqual(["ONESIGNAL_REST_API_KEY"]);
  });

  test("live: callable di prova, cron e secret Make anche su subscribeToCourse", () => {
    process.env.WHATSAPP_DEMO_MODE = "live";
    const mod = loadIndex();
    expect(mod.sendTestDemoLessonWebhook).toBeDefined();
    expect(secretKeys(mod.sendDemoLessonWhatsappReminders)).toEqual([
      "MAKE_WEBHOOK_KEY",
      "MAKE_WEBHOOK_URL",
    ]);
    expect(secretKeys(mod.subscribeToCourse)).toEqual([
      "MAKE_WEBHOOK_KEY",
      "MAKE_WEBHOOK_URL",
      "ONESIGNAL_REST_API_KEY",
    ]);
  });

  test("live: il cron gira alle 19:00 di Roma con timeout, istanza singola e retry", () => {
    process.env.WHATSAPP_DEMO_MODE = "live";
    const mod = loadIndex();
    const endpoint = (mod.sendDemoLessonWhatsappReminders as { __endpoint?: Record<string, unknown> })
      .__endpoint;
    expect(endpoint).toMatchObject({
      region: ["europe-west8"],
      timeoutSeconds: 540,
      maxInstances: 1,
      scheduleTrigger: {
        schedule: "0 19 * * *",
        timeZone: "Europe/Rome",
        retryConfig: { retryCount: 3, minBackoffSeconds: 30 },
      },
    });
  });

  const useMeta = (over: Record<string, string> = {}) => {
    Object.assign(process.env, {
      WHATSAPP_TRANSPORT: "meta",
      META_GRAPH_VERSION: "v26.0",
      META_WA_PHONE_NUMBER_ID: "106540352242922",
      META_WA_TEMPLATE_REMINDER: "promemoria_lezione_prova",
      ...over,
    });
  };

  test("off con trasporto meta: niente function e niente validazione della config Meta", () => {
    process.env.WHATSAPP_TRANSPORT = "meta";
    const mod = loadIndex();
    expect(mod.sendTestDemoLessonWebhook).toBeUndefined();
    expect(mod.whatsappStatusWebhook).toBeUndefined();
  });

  test("test + make: nessun webhook di stato", () => {
    process.env.WHATSAPP_DEMO_MODE = "test";
    const mod = loadIndex();
    expect(mod.whatsappStatusWebhook).toBeUndefined();
  });

  test("test + meta: la callable di prova usa solo il token Meta", () => {
    process.env.WHATSAPP_DEMO_MODE = "test";
    useMeta();
    const mod = loadIndex();
    expect(secretKeys(mod.sendTestDemoLessonWebhook)).toEqual(["META_WA_ACCESS_TOKEN"]);
    expect(mod.sendDemoLessonWhatsappReminders).toBeUndefined();
    expect(secretKeys(mod.subscribeToCourse)).toEqual(["ONESIGNAL_REST_API_KEY"]);
  });

  test("live + meta senza template di conferma: cron col token, subscribeToCourse senza", () => {
    process.env.WHATSAPP_DEMO_MODE = "live";
    useMeta();
    const mod = loadIndex();
    expect(secretKeys(mod.sendDemoLessonWhatsappReminders)).toEqual(["META_WA_ACCESS_TOKEN"]);
    expect(secretKeys(mod.subscribeToCourse)).toEqual(["ONESIGNAL_REST_API_KEY"]);
  });

  test("live + meta con template di conferma: il token anche su subscribeToCourse", () => {
    process.env.WHATSAPP_DEMO_MODE = "live";
    useMeta({ META_WA_TEMPLATE_BOOKED: "conferma_lezione_prova" });
    const mod = loadIndex();
    expect(secretKeys(mod.subscribeToCourse)).toEqual([
      "META_WA_ACCESS_TOKEN",
      "ONESIGNAL_REST_API_KEY",
    ]);
  });

  test("meta con configurazione incompleta: la discovery fallisce", () => {
    process.env.WHATSAPP_DEMO_MODE = "test";
    useMeta({ META_WA_PHONE_NUMBER_ID: "" });
    expect(() => loadIndex()).toThrow(/META_WA_PHONE_NUMBER_ID/);
  });
});
