import type { FirestoreAdminClient } from "@google-cloud/firestore/types/v1/firestore_admin_client";
import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { randomUUID } from "crypto";

export const BACKUP_PROJECT = "fit-rope-app-1f575";
export const BACKUP_BUCKET = "fit-rope-app-1f575-firestore-backups";
const RUNS = "_systemBackupRuns";

type RunStatus = "STARTING" | "RUNNING" | "SUCCEEDED" | "FAILED";

class BackupStillRunningError extends Error {
  constructor(operationName: string) {
    super(`FIRESTORE_BACKUP_STILL_RUNNING:${operationName}`);
    this.name = "BackupStillRunningError";
  }
}

interface BackupRun {
  status: RunStatus;
  attempt: number;
  outputUri?: string;
  operationName?: string;
  startedAt?: Timestamp;
  finishedAt?: Timestamp;
  error?: string;
  leaseOwner?: string;
  leaseExpiresAt?: Timestamp;
}

export interface BackupDependencies {
  db: admin.firestore.Firestore;
  adminClient: FirestoreAdminClient;
  writeManifest: (path: string, body: Record<string, unknown>) => Promise<void>;
  now: () => Date;
  scheduledAt?: Date;
  projectId: string | undefined;
  invocationId?: string;
  maxWaitMillis?: number;
}

function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function utcPrefix(date: Date, attempt: number): string {
  const yyyy = date.getUTCFullYear();
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(date.getUTCDate()).padStart(2, "0");
  const stamp = date.toISOString().replace(/[:.]/g, "-");
  return `gs://${BACKUP_BUCKET}/automatic/${yyyy}/${mm}/${dd}/firestore-${stamp}-attempt-${attempt}`;
}

function manifestPath(date: Date): string {
  const yyyy = date.getUTCFullYear();
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(date.getUTCDate()).padStart(2, "0");
  return `_manifests/${yyyy}/${mm}/${dd}.json`;
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function isOperationDone(
  client: FirestoreAdminClient,
  operationName: string,
): Promise<boolean> {
  const operation = await client.checkExportDocumentsProgress(operationName);
  if (!operation.done) return false;
  await operation.promise();
  return true;
}

async function findOperationForOutput(
  client: FirestoreAdminClient,
  outputUri: string,
): Promise<string | undefined> {
  const database = `projects/${BACKUP_PROJECT}/databases/(default)`;
  for await (const page of client.listOperationsAsync({
    name: database,
    filter: "",
    pageSize: 1000,
    pageToken: "",
  } as never)) {
    for (const operation of page.operations ?? []) {
      if (!operation.name) continue;
      try {
        const checked = await client.checkExportDocumentsProgress(
          operation.name,
        );
        const metadata = checked.metadata as unknown as {
          outputUriPrefix?: string;
        } | null;
        if (metadata?.outputUriPrefix === outputUri) return operation.name;
      } catch {
        // Operazioni di altro tipo o già eliminate non impediscono la scansione.
      }
    }
  }
  return undefined;
}

async function waitAtMost<T>(
  promise: Promise<T>,
  millis: number,
): Promise<boolean> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise.then(() => true),
      new Promise<boolean>((resolve) => {
        timer = setTimeout(() => resolve(false), millis);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function releaseLease(
  runRef: admin.firestore.DocumentReference,
): Promise<void> {
  await runRef.set(
    {
      leaseOwner: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
    },
    { merge: true },
  );
}

/**
 * Export idempotente: Cloud Scheduler può invocare/riprovare lo stesso job più
 * volte. Il documento del giorno è la sorgente di verità per l'operazione LRO.
 */
export async function runFirestoreBackup(
  deps: BackupDependencies,
): Promise<{ status: RunStatus; outputUri?: string; operationName?: string }> {
  if (deps.projectId !== BACKUP_PROJECT) {
    throw new Error(
      `firestoreBackupDaily consentita solo su ${BACKUP_PROJECT}`,
    );
  }
  const scheduledAt = deps.scheduledAt ?? deps.now();
  const key = dayKey(scheduledAt);
  const runRef = deps.db.collection(RUNS).doc(key);
  const owner = deps.invocationId ?? randomUUID();
  const leaseMillis = 10 * 60 * 1000;
  const existing = await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(runRef);
    const run = snap.exists ? (snap.data() as BackupRun) : undefined;
    const leaseActive =
      run?.leaseExpiresAt && run.leaseExpiresAt.toMillis() > Date.now();
    if (
      run?.status === "SUCCEEDED" ||
      (leaseActive && run.leaseOwner !== owner)
    ) {
      return run;
    }
    tx.set(
      runRef,
      {
        leaseOwner: owner,
        leaseExpiresAt: Timestamp.fromMillis(Date.now() + leaseMillis),
      },
      { merge: true },
    );
    return run;
  });

  if (existing?.status === "SUCCEEDED") {
    return {
      status: existing.status,
      outputUri: existing.outputUri,
      operationName: existing.operationName,
    };
  }
  if (
    existing?.leaseExpiresAt &&
    existing.leaseExpiresAt.toMillis() > Date.now() &&
    existing.leaseOwner !== owner
  ) {
    return {
      status: existing.status ?? "STARTING",
      outputUri: existing.outputUri,
      operationName: existing.operationName,
    };
  }
  if (
    (existing?.status === "STARTING" || existing?.status === "RUNNING") &&
    existing.operationName
  ) {
    try {
      if (!(await isOperationDone(deps.adminClient, existing.operationName))) {
        await releaseLease(runRef);
        throw new BackupStillRunningError(existing.operationName);
      }
      await finishSuccess(deps, runRef, scheduledAt, existing);
      return {
        status: "SUCCEEDED",
        outputUri: existing.outputUri,
        operationName: existing.operationName,
      };
    } catch (error) {
      if (error instanceof BackupStillRunningError) throw error;
      await runRef.set(
        {
          status: "FAILED",
          error: errorText(error),
          finishedAt: Timestamp.now(),
          leaseOwner: FieldValue.delete(),
          leaseExpiresAt: FieldValue.delete(),
        },
        { merge: true },
      );
      throw error;
    }
  }

  const attempt =
    existing?.status === "STARTING"
      ? (existing.attempt ?? 1)
      : (existing?.attempt ?? 0) + 1;
  const outputUri =
    existing?.status === "STARTING" && existing.outputUri
      ? existing.outputUri
      : utcPrefix(scheduledAt, attempt);
  // Prima persiste STARTING: un crash qui non genera un export non tracciato.
  await runRef.set(
    {
      status: "STARTING",
      attempt,
      outputUri,
      startedAt: Timestamp.now(),
      error: FieldValue.delete(),
    },
    { merge: true },
  );
  try {
    const reconciledName = await findOperationForOutput(
      deps.adminClient,
      outputUri,
    );
    if (reconciledName) {
      await runRef.set(
        { status: "RUNNING", operationName: reconciledName },
        { merge: true },
      );
      const done = await isOperationDone(deps.adminClient, reconciledName);
      if (!done) {
        await releaseLease(runRef);
        throw new BackupStillRunningError(reconciledName);
      }
      await finishSuccess(deps, runRef, scheduledAt, {
        status: "RUNNING",
        attempt,
        outputUri,
        operationName: reconciledName,
      });
      return { status: "SUCCEEDED", outputUri, operationName: reconciledName };
    }
    const [operation] = await deps.adminClient.exportDocuments({
      name: `projects/${BACKUP_PROJECT}/databases/(default)`,
      outputUriPrefix: outputUri,
      collectionIds: [],
    });
    const operationName = operation.name;
    if (!operationName)
      throw new Error("L'export Firestore non ha restituito operationName");
    await runRef.set({ status: "RUNNING", operationName }, { merge: true });

    // Un export grande può superare la durata della funzione. Il prossimo retry
    // monitora la stessa operation, senza avviarne una duplicata.
    const done = await waitAtMost(
      operation.promise(),
      deps.maxWaitMillis ?? 8 * 60 * 1000,
    );
    if (!done) {
      await releaseLease(runRef);
      throw new BackupStillRunningError(operationName);
    }
    await finishSuccess(deps, runRef, scheduledAt, {
      status: "RUNNING",
      attempt,
      outputUri,
      operationName,
    });
    return { status: "SUCCEEDED", outputUri, operationName };
  } catch (error) {
    if (error instanceof BackupStillRunningError) throw error;
    await runRef.set(
      {
        status: "FAILED",
        attempt,
        outputUri,
        error: errorText(error),
        finishedAt: Timestamp.now(),
        leaseOwner: FieldValue.delete(),
        leaseExpiresAt: FieldValue.delete(),
      },
      { merge: true },
    );
    throw error;
  }
}

async function finishSuccess(
  deps: BackupDependencies,
  runRef: admin.firestore.DocumentReference,
  scheduledAt: Date,
  run: BackupRun,
): Promise<void> {
  const completedAt = deps.now();
  await deps.writeManifest(manifestPath(scheduledAt), {
    status: "SUCCEEDED",
    database: `projects/${BACKUP_PROJECT}/databases/(default)`,
    outputUri: run.outputUri,
    operationName: run.operationName,
    completedAt: completedAt.toISOString(),
  });
  await runRef.set(
    {
      status: "SUCCEEDED",
      finishedAt: Timestamp.fromDate(completedAt),
      leaseOwner: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
    },
    { merge: true },
  );
  logger.info("Export Firestore completato", {
    outputUri: run.outputUri,
    operationName: run.operationName,
  });
}

/** Fail-fast monitorato alle 03:00 UTC: rende visibile un backup mancante. */
export async function checkFirestoreBackup(
  db: admin.firestore.Firestore,
  now: Date,
): Promise<void> {
  const key = dayKey(now);
  const run = await db.collection(RUNS).doc(key).get();
  if (!run.exists || run.data()?.status !== "SUCCEEDED") {
    throw new Error(
      JSON.stringify({
        code: "FIRESTORE_BACKUP_NOT_SUCCEEDED",
        day: key,
        status: run.data()?.status ?? "MISSING",
      }),
    );
  }
}
