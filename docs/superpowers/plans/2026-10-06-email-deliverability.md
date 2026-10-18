# Email: revisione e prima fase

Aggiornamento del 18 ottobre 2026. Questa versione recepisce la revisione del
piano originale e la scelta di mantenere reset password e verifica email su
Firebase Auth nella prima fase.

## Obiettivo

Unificare layout e preheader delle notifiche prova, waitlist e certificati,
riutilizzare i template server negli invii di debug e verificare DNS e mittente
OneSignal con evidenze reali. La correzione dell'autenticazione email non garantisce
da sola l'arrivo in Inbox.

## Avanzamento applicativo

- [x] Layout TypeScript condiviso con logo, footer, CTA ed escaping.
- [x] Migrazione dei cinque template delle notifiche e relativi preheader.
- [x] Callable `sendTestEnrollmentEmail`, solo Admin e solo emulatore/staging,
  con controllo ambiente anche a runtime e guard del clone staging.
- [x] Destinatario letto da Firestore; email normalizzata e allowlist applicata
  prima dell'ensure. Nessun invio dopo una soppressione dell'ensure.
- [x] Risposte OneSignal senza ID o con zero destinatari trattate come errore;
  soppressione propagata al client senza snackbar di successo.
- [x] Wrapper Flutter migrati, con guardie simulazione prima degli effetti.
- [x] Eliminati template Dart e mirror calendario; copertura trasferita ai test TS.
- [x] Documentazione e smoke test staging aggiornati.
- [ ] PR verso `develop` e verifica CI.

## DNS e mittente

Rilievo DNS, passaggi esatti, stato delle evidenze e criteri di accettazione:
[registro operativo](../../operations/EMAIL_DELIVERABILITY.md).

- [x] Rilevati TXT, MX e CNAME tramite Google DNS-over-HTTPS.
- [ ] Rilevare stato e record richiesti dalla dashboard OneSignal.
- [ ] Rilevare Return-Path, dominio DKIM e Authentication-Results da email ricevute.
- [ ] Applicare i record verificati in dashboard e configurare mittente/reply-to.
- [ ] Attivare i report DMARC dopo aver verificato la casella destinataria.
- [ ] Valutare la rimozione di OneSignal dallo SPF radice sulla base degli header.
- [ ] Verificare autenticazione e consegna su Gmail, Outlook e iCloud.

Gli accessi alle dashboard e gli header non erano disponibili durante lo sviluppo:
i passaggi esterni restano da completare. Non aggiungere include SPF alla radice
senza ricalcolarne il budget. Attendere i TTL precedenti, anche di quattro ore.
Mantenere DMARC `p=none` durante l'osservazione iniziale.

## Verifica applicativa

Eseguire build e unit test Functions, integrazione Auth/Firestore/Functions su
emulatori dedicati, test Flutter, analyze e formattazione. I test devono coprire:

- struttura HTML unica, brand, escaping di testo/attributi e preheader nei payload;
- contenuti, sala, singolare/plurale e link Google Calendar/ICS preservati;
- login, ruolo Admin, profilo assente, email non valida e payload non validi;
- email e UID staging consentiti/esclusi, soppressione ensure/post, errori provider;
- HTTP 200 senza invio e guardie client prima dell'accesso a Firebase;
- callable effettiva sull'emulatore con attori Auth reali e trasporto finto per
  il percorso positivo del relativo handler.

La QA ordinaria usa trasporto finto o chiavi fittizie. Gli invii a caselle reali
sono prove mirate separate. Staging distribuisce prima Functions e poi web;
la callable di debug non viene esportata in produzione.

## Vincoli per una futura fase Auth

La precedente implementazione proposta non va utilizzata senza risolvere:

1. **Destinatario esatto:** un link di reset/verifica deve raggiungere soltanto
   l'email corrente Auth, evitando l'invio a tutti gli indirizzi associati all'UID
   OneSignal. L'helper attuale aggiunge subscription senza rimuovere quelle vecchie.
2. **Esito del provider:** HTTP 200 non basta; verificare ID, errori e destinatari,
   distinguendo accettazione del messaggio da consegna nella casella.
3. **Preferenze:** l'invio Auth non deve riabilitare le subscription delle notifiche
   ordinarie. Valutare `include_unsubscribed` per i soli messaggi essenziali e
   disabilitare il click tracking dei link di sicurezza.
4. **Fallback:** definire errori ammessi, autorizzazione, throttling e gestione di
   timeout con esito incerto. Una risposta per-email `fallbackToFirebase` può
   rivelare l'esistenza dell'account quando il provider fallisce; il solo
   `{ok:true}` sul percorso felice non basta a garantire risposte uniformi.
5. **Registrazione:** la scorciatoia password dimenticata deve coprire sia
   `duplicateProfileMessage` sia `duplicateAccountMessage`.
6. **Contratto operativo:** con fallback Firebase, mittente/template uniformi
   hanno un'eccezione. Non promettere consegna in Inbox o assenza assoluta di
   enumerazione; verificare anche protezioni antiabuso e ciclo di vita dei
   documenti di throttle prima di introdurre una nuova callable pubblica.

La fase Auth richiede un nuovo piano prima dell'implementazione. Nessuna nuova
callable Auth o variabile `AUTH_CONTINUE_URL` è introdotta nella prima fase.
