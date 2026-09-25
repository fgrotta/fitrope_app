// Callable di prova (DebugEmailPage): manda un payload sintetico al numero
// indicato, senza toccare iscrizioni né registro invii. Serve a far apprendere
// lo schema a Make e a provare i template sul proprio telefono.
//
// Solo Admin: la callable è raggiungibile via HTTP da qualunque utente
// autenticato, e ogni WhatsApp è reale e a pagamento.

import { HttpsError } from "firebase-functions/v2/https";
import { HandlerRequest } from "../handler";
import { WhatsappDeps } from "./demoLesson";
import { isWhatsappRecipientAllowed } from "./environment";
import { DemoWebhookKind, buildDemoLessonPayload, sanitizeTemplateParam } from "./payload";
import { normalizePhoneE164 } from "./phone";

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
  const body = buildDemoLessonPayload({
    kind,
    nome: sanitizeTemplateParam(payload.nome) || "Test Test",
    corso: sanitizeTemplateParam(payload.corso) || "Lezione di prova",
    phoneE164: phone.e164,
    // Domani a quest'ora: una data plausibile per il messaggio di prova.
    startAtMillis: deps.nowMillis + ONE_DAY_MS,
    giorno: payload.giorno,
    orario: payload.orario,
  });

  const result = await deps.post(deps.webhookUrl, deps.apiKey, body);
  return { ok: result.ok, status: result.status, payload: { ...body } };
}
