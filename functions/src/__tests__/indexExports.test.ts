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
  courseIcs: unknown;
  firestoreBackupDaily: unknown;
  firestoreBackupDailyCheck: unknown;
  sendTestDemoLessonWebhook: unknown;
  sendDemoLessonWhatsappReminders: unknown;
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

describe("gate WHATSAPP_DEMO_MODE (export condizionale in index.ts)", () => {
  const saved = {
    mode: process.env.WHATSAPP_DEMO_MODE,
    appEnv: process.env.APP_ENV,
    emulator: process.env.FUNCTIONS_EMULATOR,
  };

  beforeEach(() => {
    delete process.env.APP_ENV;
    delete process.env.FUNCTIONS_EMULATOR;
  });

  afterEach(() => {
    const restore = (key: string, value: string | undefined) => {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    };
    restore("WHATSAPP_DEMO_MODE", saved.mode);
    restore("APP_ENV", saved.appEnv);
    restore("FUNCTIONS_EMULATOR", saved.emulator);
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
});
