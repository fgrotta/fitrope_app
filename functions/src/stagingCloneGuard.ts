import { CallableRequest, HttpsError } from "firebase-functions/v2/https";

/** Limits staging callables while a production Firestore export is mounted. */
export function isStagingCloneMode(): boolean {
  return process.env.STAGING_CLONE_MODE === "true";
}

export function isStagingCloneUidAllowed(uid: string): boolean {
  if (!isStagingCloneMode()) return true;
  const configured = process.env.STAGING_CLONE_ALLOWED_UIDS ?? "";
  return configured.split(",").some((id) => id.trim() === uid);
}

export function assertStagingCloneAccess(uid: string | undefined): void {
  if (!isStagingCloneMode()) return;
  if (!uid || !isStagingCloneUidAllowed(uid)) {
    throw new HttpsError("permission-denied", "Account non abilitato al clone staging");
  }
}

export function stagingCloneGuarded<T, R>(
  handler: (request: CallableRequest<T>) => R,
): (request: CallableRequest<T>) => R {
  return (request) => {
    assertStagingCloneAccess(request.auth?.uid);
    return handler(request);
  };
}
