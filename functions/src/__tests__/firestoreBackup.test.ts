import { Timestamp } from "firebase-admin/firestore";
import { checkFirestoreBackup, runFirestoreBackup } from "../firestoreBackup";

function fakeDb(initial?: Record<string, unknown>) {
  let value = initial;
  const snapshot = () => ({
    exists: value !== undefined,
    data: () => value,
  });
  const apply = (patch: Record<string, unknown>) => {
    value = { ...(value ?? {}), ...patch };
  };
  const ref = {
    get: jest.fn(async () => snapshot()),
    set: jest.fn(async (patch: Record<string, unknown>) => apply(patch)),
  };
  const db = {
    collection: () => ({ doc: () => ref }),
    runTransaction: async (
      callback: (tx: {
        get: () => Promise<ReturnType<typeof snapshot>>;
        set: (_ref: unknown, patch: Record<string, unknown>) => void;
      }) => Promise<unknown>,
    ) =>
      callback({
        get: async () => snapshot(),
        set: (_ref, patch) => apply(patch),
      }),
  };
  return { db, ref, value: () => value };
}

async function* noOperations() {
  yield { operations: [] };
}

function adminClient(overrides: Record<string, unknown> = {}) {
  return {
    exportDocuments: jest.fn(async () => [
      { name: "operations/export-1", promise: async () => undefined },
    ]),
    checkExportDocumentsProgress: jest.fn(),
    listOperationsAsync: jest.fn(() => noOperations()),
    ...overrides,
  };
}

const scheduledAt = new Date("2026-08-26T02:00:00.000Z");
const completedAt = new Date("2026-08-26T02:04:00.000Z");

function dependencies(fake: ReturnType<typeof fakeDb>, client = adminClient()) {
  return {
    db: fake.db as never,
    adminClient: client as never,
    writeManifest: jest.fn(async () => undefined),
    now: () => completedAt,
    scheduledAt,
    projectId: "fit-rope-app-1f575",
    invocationId: "invocation-1",
  };
}

describe("firestoreBackupDaily", () => {
  test("avvia un export, attende LRO e scrive il manifest UTC", async () => {
    const fake = fakeDb();
    const deps = dependencies(fake);
    const result = await runFirestoreBackup(deps);
    expect(
      (deps.adminClient as never as { exportDocuments: jest.Mock })
        .exportDocuments,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        name: "projects/fit-rope-app-1f575/databases/(default)",
        collectionIds: [],
        outputUriPrefix: expect.stringContaining(
          "/automatic/2026/08/26/firestore-2026-08-26T02-00-00-000Z-attempt-1",
        ),
      }),
    );
    expect(result.status).toBe("SUCCEEDED");
    expect(deps.writeManifest).toHaveBeenCalledWith(
      "_manifests/2026/08/26.json",
      expect.objectContaining({ status: "SUCCEEDED" }),
    );
  });

  test("usa scheduleTime anche se il completamento cade nel giorno dopo", async () => {
    const fake = fakeDb();
    const deps = dependencies(fake);
    deps.now = () => new Date("2026-08-27T00:01:00.000Z");
    await runFirestoreBackup(deps);
    expect(deps.writeManifest).toHaveBeenCalledWith(
      "_manifests/2026/08/26.json",
      expect.any(Object),
    );
  });

  test("un run completato non avvia un secondo export", async () => {
    const fake = fakeDb({
      status: "SUCCEEDED",
      attempt: 1,
      outputUri: "gs://done",
      operationName: "op",
    });
    const deps = dependencies(fake);
    const result = await runFirestoreBackup(deps);
    expect(result.status).toBe("SUCCEEDED");
    expect(
      (deps.adminClient as never as { exportDocuments: jest.Mock })
        .exportDocuments,
    ).not.toHaveBeenCalled();
  });

  test("una lease concorrente impedisce un export duplicato", async () => {
    const fake = fakeDb({
      status: "STARTING",
      attempt: 1,
      outputUri: "gs://pending",
      leaseOwner: "other-invocation",
      leaseExpiresAt: Timestamp.fromMillis(Date.now() + 60_000),
    });
    const deps = dependencies(fake);
    const result = await runFirestoreBackup(deps);
    expect(result.status).toBe("STARTING");
    expect(
      (deps.adminClient as never as { exportDocuments: jest.Mock })
        .exportDocuments,
    ).not.toHaveBeenCalled();
  });

  test("riconcilia uno STARTING orfano cercando lo stesso output URI", async () => {
    const outputUri = "gs://pending";
    const fake = fakeDb({
      status: "STARTING",
      attempt: 1,
      outputUri,
      leaseOwner: "old",
      leaseExpiresAt: Timestamp.fromMillis(0),
    });
    async function* operations() {
      yield { operations: [{ name: "operations/recovered" }] };
    }
    const client = adminClient({
      listOperationsAsync: jest.fn(() => operations()),
      checkExportDocumentsProgress: jest.fn(async () => ({
        name: "operations/recovered",
        done: true,
        metadata: { outputUriPrefix: outputUri },
        promise: async () => undefined,
      })),
    });
    const deps = dependencies(fake, client);
    const result = await runFirestoreBackup(deps);
    expect(result).toEqual(
      expect.objectContaining({
        status: "SUCCEEDED",
        operationName: "operations/recovered",
      }),
    );
    expect(client.exportDocuments).not.toHaveBeenCalled();
  });

  test("un RUNNING incompleto chiede un retry senza avviare altri export", async () => {
    const fake = fakeDb({
      status: "RUNNING",
      attempt: 1,
      outputUri: "gs://pending",
      operationName: "operations/running",
      leaseExpiresAt: Timestamp.fromMillis(0),
    });
    const client = adminClient({
      checkExportDocumentsProgress: jest.fn(async () => ({
        done: false,
        promise: jest.fn(),
      })),
    });
    await expect(
      runFirestoreBackup(dependencies(fake, client)),
    ).rejects.toThrow("FIRESTORE_BACKUP_STILL_RUNNING");
    expect(client.exportDocuments).not.toHaveBeenCalled();
  });

  test("un export oltre la finestra libera la lease e chiede un retry", async () => {
    const fake = fakeDb();
    const client = adminClient({
      exportDocuments: jest.fn(async () => [
        {
          name: "operations/slow",
          promise: () => new Promise(() => undefined),
        },
      ]),
    });
    const deps = { ...dependencies(fake, client), maxWaitMillis: 1 };
    await expect(runFirestoreBackup(deps)).rejects.toThrow(
      "FIRESTORE_BACKUP_STILL_RUNNING",
    );
    expect(fake.value()).toEqual(
      expect.objectContaining({ status: "RUNNING" }),
    );
  });

  test("un FAILED crea un nuovo tentativo", async () => {
    const fake = fakeDb({ status: "FAILED", attempt: 1 });
    const deps = dependencies(fake);
    await runFirestoreBackup(deps);
    expect(
      (deps.adminClient as never as { exportDocuments: jest.Mock })
        .exportDocuments,
    ).toHaveBeenCalledWith(
      expect.objectContaining({
        outputUriPrefix: expect.stringContaining("attempt-2"),
      }),
    );
  });

  test("rifiuta un progetto diverso da PRD", async () => {
    const fake = fakeDb();
    const deps = dependencies(fake);
    deps.projectId = "fit-rope-staging";
    await expect(runFirestoreBackup(deps)).rejects.toThrow(
      "consentita solo su fit-rope-app-1f575",
    );
  });

  test("un errore API marca il run FAILED", async () => {
    const fake = fakeDb();
    const client = adminClient({
      exportDocuments: jest.fn(async () => {
        throw new Error("API unavailable");
      }),
    });
    await expect(
      runFirestoreBackup(dependencies(fake, client)),
    ).rejects.toThrow("API unavailable");
    expect(fake.value()).toEqual(
      expect.objectContaining({ status: "FAILED", error: "API unavailable" }),
    );
  });

  test("un manifest non scritto impedisce di marcare SUCCEEDED", async () => {
    const fake = fakeDb();
    const deps = dependencies(fake);
    deps.writeManifest = jest.fn(async () => {
      throw new Error("manifest failed");
    });
    await expect(runFirestoreBackup(deps)).rejects.toThrow("manifest failed");
    expect(fake.value()).toEqual(expect.objectContaining({ status: "FAILED" }));
  });

  test("il check fallisce per backup mancante o non concluso", async () => {
    await expect(
      checkFirestoreBackup(fakeDb().db as never, scheduledAt),
    ).rejects.toThrow("FIRESTORE_BACKUP_NOT_SUCCEEDED");
    await expect(
      checkFirestoreBackup(
        fakeDb({ status: "RUNNING" }).db as never,
        scheduledAt,
      ),
    ).rejects.toThrow("RUNNING");
  });
});
