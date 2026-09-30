// Callable di prova (DebugEmailPage): manda un messaggio sintetico al numero
// indicato col trasporto configurato (Make o Meta), senza toccare iscrizioni.
// Serve a far apprendere lo schema a Make e a provare i template sul proprio
// telefono.
//
// Con Meta, se torna un wamid, scrive nel registro un documento `test_…` con
// soli identificativi (l'hash del wamid, non il wamid, che contiene il numero): è l'unico modo di vedere sul webhook di stato
// (statusWebhook.ts) la consegna di un messaggio di prova. Non interferisce
// con claim e soppressioni, che usano solo id `{kind}_{userId}_{courseId}`.
//
// Solo Admin: la callable è raggiungibile via HTTP da qualunque utente
// autenticato, e ogni WhatsApp è reale e a pagamento.

import { logger } from "firebase-functions";
import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { HandlerRequest } from "../handler";
import { WhatsappDeps } from "./demoLesson";
import { isWhatsappRecipientAllowed } from "./environment";
import { DemoWebhookKind, buildTemplateParams, sanitizeTemplateParam, toMakeBody } from "./payload";
import { normalizePhoneE164 } from "./phone";
import { DEMO_LOG_COLLECTION } from "./sendLog";
import { hashMessageId, messageRef } from "./transport";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

interface TestPayload {
  numeroTelefono?: string;
  kind?: string;
  nome?: string;
  corso?: string;
  giorno?: string;
  orario?: string;
}

export async function sendTestDemoLessonWebhookHandler(
  request: HandlerRequest,
  deps: WhatsappDeps
): Promise<Record<string, unknown>> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login richiesto");
  }
  const callerSnap = await deps.db.collection("users").doc(request.auth.uid).get();
  const role = (callerSnap.data()?.role as string | undefined) ?? null;
  if (role !== "Admin") {
    throw new HttpsError("permission-denied", "Solo gli Admin possono inviare WhatsApp di prova");
  }

  const payload = request.data as TestPayload | null;
  if (!payload || typeof payload !== "object" || !payload.numeroTelefono) {
    throw new HttpsError("invalid-argument", "numeroTelefono obbligatorio");
  }
  const phone = normalizePhoneE164(payload.numeroTelefono);
  if (phone.e164 === null) {
    throw new HttpsError("invalid-argument", `Numero non valido (${phone.reason})`);
  }
  if (!isWhatsappRecipientAllowed(phone.e164, deps.env)) {
    throw new HttpsError("permission-denied", "Numero non presente in STAGING_WHATSAPP_ALLOWLIST");
  }

  const kind: DemoWebhookKind = payload.kind === "reminder" ? "reminder" : "booked";
  const transport = deps.transport;
  if (!transport.supports(kind)) {
    throw new HttpsError(
      "failed-precondition",
      `Il trasporto ${transport.name} non ha un template per "${kind}" (con Meta serve META_WA_TEMPLATE_BOOKED)`
    );
  }

  const params = buildTemplateParams({
    nome: sanitizeTemplateParam(payload.nome) || "Test Test",
    corso: sanitizeTemplateParam(payload.corso) || "Lezione di prova",
    // Domani a quest'ora: una data plausibile per il messaggio di prova.
    startAtMillis: deps.nowMillis + ONE_DAY_MS,
    giorno: payload.giorno,
    orario: payload.orario,
  });

  const result = await transport.send(kind, phone.e164, params);
  if (result.ok && result.messageId) {
    await recordTestSend(deps, request.auth.uid, kind, result.status, result.messageId);
  }
  return {
    ok: result.ok,
    status: result.status,
    transport: transport.name,
    ...(result.messageId ? { messageId: result.messageId } : {}),
    ...(result.errorCode !== undefined ? { errorCode: result.errorCode } : {}),
    // Stessi campi del body Make, per mostrare nella pagina di debug cosa è partito.
    payload: { ...toMakeBody(kind, phone.e164, params) },
  };
}

/** Best-effort: il messaggio è già partito, un errore qui non va propagato al client. */
async function recordTestSend(
  deps: WhatsappDeps,
  uid: string,
  kind: DemoWebhookKind,
  status: number,
  messageId: string
): Promise<void> {
  try {
    await deps.db
      .collection(DEMO_LOG_COLLECTION)
      .doc(`test_${uid}_${deps.nowMillis}`)
      .create({
        kind: "test",
        testKind: kind,
        userId: uid,
        transport: deps.transport.name,
        // Solo l'hash: il wamid contiene il numero (transport.ts).
        messageIdHash: hashMessageId(messageId),
        outcome: "sent",
        ok: true,
        status,
        sentAt: Timestamp.fromMillis(deps.nowMillis),
      });
  } catch (err) {
    logger.warn("WhatsApp di prova: documento nel registro non scritto", {
      messageRef: messageRef(messageId),
      error: err instanceof Error ? err.message : String(err),
    });
  }
}
