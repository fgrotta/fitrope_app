# Piano: Storico Email per-utente in Admin (schedulata / inviata / aperta)

## Context

L'admin vuole poter verificare, per ogni utente, le email che gli sono state
inviate negli ultimi 30 giorni e il loro stato: **schedulata**, **inviata**,
**aperta**. Oggi FitRope invia email tramite OneSignal (via Cloud Functions) ma
**non conserva alcuna traccia** di cosa è stato inviato a chi.

Vincoli emersi dalla verifica delle API OneSignal:
- `GET /notifications` (lista) e `GET /notifications/{id}` restituiscono le
  statistiche **aggregate** di un messaggio (`send_after`, `completed_at`,
  `successful`, `converted`=click, opens email) ma **NON il destinatario**: non
  esiste `external_id` nella risposta.
- I messaggi inviati via API sono conservati **solo ~30 giorni**.
- Non esiste modo affidabile di attribuire un vecchio messaggio a un utente
  (l'endpoint "Message history" per-destinatario richiede piano a pagamento,
  finestra di 7 giorni e non riporta gli "opens").
- **Ma** FitRope invia ogni email a un **singolo utente**
  (`include_aliases: {external_id: [uid]}`), quindi le statistiche aggregate di
  un messaggio **coincidono** con lo stato per quell'utente — a patto di
  registrare noi la mappa `notification_id → uid` al momento dell'invio.

**Decisioni prese con l'utente:**
- Stato "aperta" ricavato **on-demand** interrogando OneSignal quando l'admin
  apre la vista (niente webhook / niente piano a pagamento).
- Solo **sezione per-utente** in `UserDetailPage` (nessuna vista globale).
- Tutti e 4 i tipi di email: promemoria prova, waitlist, certificato 10gg,
  certificato scadenza.
- Storico **forward-only**: parte dal deploy del logging, ogni record è
  attribuito con certezza. Nessun backfill inaffidabile.

## Approccio

Due pezzi nuovi lato server (logging degli invii + callable di enrichment) e una
nuova sezione nella pagina di dettaglio utente lato Flutter. Si riusano i pattern
esistenti: `postToOneSignal` come choke-point invii, `_buildSection` per la UI,
`FirebaseFunctions...httpsCallable` per le callable.

## Modello dati — Firestore

Nuova collection top-level **`emailLogs`** (un doc auto-id per email inviata):

| Campo | Tipo | Note |
|---|---|---|
| `userId` | string | uid destinatario (= external_id OneSignal) |
| `email` | string | snapshot email al momento dell'invio |
| `type` | string | `trial_reminder` \| `waitlist` \| `certificate_reminder10` \| `certificate_expiry` |
| `subject` | string | oggetto email |
| `oneSignalId` | string | `id` restituito dalla POST /notifications |
| `createdAt` | Timestamp | server time del logging |
| `scheduledFor` | Timestamp? | `send_after` se schedulata (promemoria prova); null se immediata |
| `sentAt` | Timestamp? | cache enrichment (completed_at) |
| `openedAt` / `opened` | bool/Timestamp? | cache enrichment |
| `clicked` | bool? | cache enrichment (converted) |
| `lastSyncedAt` | Timestamp? | ultimo enrichment OneSignal |

Indice composito richiesto: `emailLogs` → `userId ASC, createdAt DESC`
(aggiungere a `firestore.indexes.json` se presente, altrimenti Firestore
proporrà il link in fase di query). Collection top-level (non subcollection) per
robustezza rispetto all'ambiguità doc-id vs campo `uid`.

## Backend — Cloud Functions (`functions/src/`)

I 4 invii passano da due flussi:
- **Client-triggered** (promemoria prova, waitlist): il payload è costruito in
  Flutter e inviato via callable `sendOneSignalNotification` → `postToOneSignal`.
- **Server-side** (certificato 10gg/scadenza): costruito e inviato in
  `certificateEmails.ts` via `postToOneSignal`.

Per centralizzare il logging (senza fidarsi del client):

1. **`handler.ts`**
   - Nuovo helper `logEmailSend({userId, email, type, subject, oneSignalId, scheduledFor})`
     che scrive un doc in `emailLogs` (admin SDK Firestore, già disponibile).
   - `sendOneSignalNotification`: accettare un campo opzionale `logMeta`
     (`{userId, type, subject}`) **da rimuovere dal payload prima della POST**;
     dopo POST riuscita con `target_channel === "email"` e `logMeta` presente,
     chiamare `logEmailSend` con l'`id` restituito e lo `send_after` del payload.
   - Nuovo helper `getNotification(id, apiKey)` → `GET /notifications/{id}?app_id=...`
     con header `Authorization: Key ...` (stesso pattern di `postToOneSignal`).

2. **`index.ts`**
   - Nuova callable **`getEmailDeliveryStatus`** (onCall, region `europe-west8`,
     secret `ONESIGNAL_REST_API_KEY`, CORS): input `{ oneSignalIds: string[] }`
     (cap ~30). Per ogni id chiama `getNotification`, mappa la risposta a
     `{ id, sentAt, opened, openedAt?, clicked }` e **riscrive la cache** sul doc
     `emailLogs` corrispondente (così lo stato sopravvive oltre i 30gg OneSignal).
     Ritorna la mappa `id → stato`.

3. **`certificateEmails.ts`**
   - Dopo ogni `postToOneSignal` riuscito, chiamare `logEmailSend` con
     `type = certificate_reminder10` / `certificate_expiry`, subject e uid noti.

> **Da verificare in implementazione:** il nome esatto del campo "opens" email
> dentro `platform_delivery_stats.email` della risposta `GET /notifications/{id}`
> (candidati: `opened` / `unique_open`). Loggare una risposta reale una volta e
> adattare il mapping. `converted` = click.

## Frontend — Flutter

1. **Modello** `lib/types/emailLog.dart` — classe `EmailLogEntry` con `fromJson`
   / `toJson` (rispettare convenzione serializzazione manuale + case del file).
   Enum/label italiane per `type`.

2. **API** `lib/api/emailLogs/getUserEmailLogs.dart` — query
   `emailLogs where userId == uid && createdAt >= now-30d orderBy createdAt desc`.

3. **`lib/services/notification_service.dart`**
   - Wrapper `getEmailDeliveryStatus(List<String> ids)` sulla nuova callable
     (region `europe-west8`, come le altre).
   - In `scheduleTrialReminder` e `notifyWaitlistUsers`: aggiungere `logMeta`
     (`userId`, `type`, `subject`) **solo** alla chiamata email di
     `sendOneSignalNotification` (non alla push).

4. **`lib/pages/protected/UserDetailPage.dart`** — nuova sezione
   **"Storico Email"** dopo "Notification Preferences" (~riga 889), via
   `_buildSection`. Desktop-first:
   - Al caricamento: fetch `emailLogs` (30gg) → poi `getEmailDeliveryStatus` per
     riempire inviata/aperta.
   - Righe/tabella con colonne: **Tipo · Schedulata · Inviata · Aperta**
     (icone/chip di stato + date via `formatDate`).
   - Mobile: lista di card (funzionale, non ottimizzata).
   - **Evitare layout-shift** (lezione CLAUDE.md): stato di caricamento con
     spinner e altezza stabile, poi righe finali; niente stringhe transitorie in
     description condivise.

5. **`firestore.rules`** — lettura `emailLogs` consentita solo agli admin;
   scrittura solo lato server (admin SDK bypassa le rules).

## File toccati (sintesi)

- `functions/src/handler.ts` — `logEmailSend`, `getNotification`, strip `logMeta`
- `functions/src/index.ts` — callable `getEmailDeliveryStatus`
- `functions/src/certificateEmails.ts` — log dopo invio
- `lib/types/emailLog.dart` — nuovo modello
- `lib/api/emailLogs/getUserEmailLogs.dart` — nuova query
- `lib/services/notification_service.dart` — wrapper + `logMeta`
- `lib/pages/protected/UserDetailPage.dart` — sezione "Storico Email"
- `firestore.rules` (+ eventuale `firestore.indexes.json`)

## Verifica

1. `cd functions && npm run build && npm test` — build TS + jest (aggiungere test
   per il mapping di `getEmailDeliveryStatus` e per `logEmailSend`, mock `fetch`).
2. `flutter analyze` + `flutter test` (test `fromJson`/`toJson` di `EmailLogEntry`).
3. **End-to-end live** (`flutter run -d chrome`, hard reload dopo relaunch):
   - Da `DebugEmailPage` inviare una email di test all'utente corrente →
     verificare che compaia un doc in `emailLogs` e la riga nella sezione
     "Storico Email" del proprio dettaglio.
   - Attendere l'invio reale / usare la prova, poi riaprire la sezione e
     verificare che "Inviata" e "Aperta" si popolino dopo l'enrichment OneSignal.
   - Controllare la resa **desktop** (larghezza reale via `window.innerWidth`,
     breakpoint desktop) e l'assenza di salti di altezza durante il caricamento.
4. Deploy: `firebase deploy --only functions` (predeploy compila via tsc); la
   nuova callable e il logging vanno in produzione insieme.

## Note

- Aggiornare il sistema di test in-app (`DebugEmailPage`) se serve un tipo email
  di test dedicato (lezione: ogni nuovo tipo email → aggiungerlo ai test in-app).
- Lo storico è forward-only: la sezione sarà vuota finché non partono invii
  post-deploy. Comunicarlo nella UI (es. empty-state esplicativo).
