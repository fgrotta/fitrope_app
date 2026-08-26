// Gate ambiente delle funzioni certificati: devono esistere SOLO su emulatore
// (FUNCTIONS_EMULATOR=true) e staging (APP_ENV=staging). In produzione l'export
// deve essere undefined, così la CLI Firebase non le deploya in discovery.
// Il require avviene dentro jest.isolateModules per rieseguire index.ts con
// l'env manipolata (admin.initializeApp è guardato da apps.length).

type IndexModule = {
  sendTestCertificateEmail: unknown;
  certificateEmailsDaily: unknown;
  sendOneSignalNotification: unknown;
  subscribeToCourse: unknown;
  firestoreBackupDaily: unknown;
  firestoreBackupDailyCheck: unknown;
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
    expect(mod.subscribeToCourse).toBeDefined();
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
