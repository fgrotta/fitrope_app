# Report dei test Fit House

**Data:** 17 settembre 2026  
**Branch:** `fgrotta/test-scenari-emulatore-staging`  
**Pull request:** [#22](https://github.com/fgrotta/fitrope_app/pull/22)

## Sintesi

La nuova strategia di test è stata verificata con test Flutter, test delle
Cloud Functions e una suite end-to-end eseguita contro Firebase Emulator Suite.
Tutti i test eseguiti hanno avuto esito positivo.

| Livello | Risultato | Cosa verifica |
| --- | ---: | --- |
| Flutter unit/widget | **541 superati** | Modelli, regole di abbonamento, UI, calendario, waitlist, simulazione e serializzazione |
| Cloud Functions Jest | **400 superati** in 20 suite | Eligibility, transazioni, rimborsi, abbonamenti, notifiche, autorizzazioni e migrazioni |
| E2E Flutter + Emulator Suite | **3 scenari superati** | Flussi UI reali con Auth, Firestore e callable Functions |
| Assert backend E2E | **superato** | Stato finale di corso, iscrizioni, waitlist, rimborso e ricevuta notifica |

## Scenari E2E eseguiti

### 1. Iscrizione, lista d'attesa e subentro

Il test usa un corso con capienza pari a un posto e due utenti con piano Open
`open_2x_1m`.

1. Il socio accede all'app reale e si iscrive al corso.
2. Il secondo socio visualizza il corso pieno e apre la lista d'attesa.
3. Il dialog di conferma viene accettato e l'utente entra in waitlist.
4. Il primo socio si disiscrive e libera il posto.
5. Il socio in waitlist visualizza la disponibilità e completa l'iscrizione.
6. L'assert Admin SDK verifica contatore, waitlist e corsi degli utenti.

Stato finale verificato:

```json
{"subscribed":1,"waitlist":[],"memberCourses":[],"waiterCourses":["e2e_e2e_1789648066755_course"]}
```

### 2. Registrazione self-service

Il test compila la schermata di registrazione con email, password, nome,
cognome e consenso privacy. Verifica quindi:

- messaggio UI di conferma dell'invio email;
- creazione dell'account Firebase Auth;
- documento `users` creato con ruolo `User`;
- `tipologiaIscrizione = ABBONAMENTO_PROVA`;
- eliminazione dell'account sintetico al termine del test.

La consegna reale dell'email non fa parte del perimetro: viene verificato che
l'invio sia stato attivato.

### 3. Pacchetto legacy: consumo e rimborso

Un utente legacy parte con due ingressi disponibili. Il test verifica che:

- l'iscrizione al corso decrementi gli ingressi a uno;
- venga registrato il consumo dell'iscrizione;
- la disiscrizione fuori dalla finestra di penalità rimborsi l'ingresso;
- il corso torni senza iscritti e gli ingressi tornino a due.

## Fixture create durante il run

Le fixture sono state create dal control plane Admin SDK nel progetto emulato
`demo-fitrope`, con prefisso `e2e_`, e poi rimosse.

| Ruolo | UID | Email |
| --- | --- | --- |
| Admin | `e2e_e2e_1789648066755_admin` | `e2e_e2e_1789648066755_admin@example.test` |
| Trainer | `e2e_e2e_1789648066755_trainer` | `e2e_e2e_1789648066755_trainer@example.test` |
| Socio | `e2e_e2e_1789648066755_member` | `e2e_e2e_1789648066755_member@example.test` |
| Socio waitlist | `e2e_e2e_1789648066755_waiter` | `e2e_e2e_1789648066755_waiter@example.test` |
| Socio legacy | `e2e_e2e_1789648066755_legacy` | `e2e_e2e_1789648066755_legacy@example.test` |
| Registrazione | creato e rimosso durante il test | `e2e_e2e_1789648066755_registration@example.test` |

Abbonamenti v2 creati per il test:

| Utente | Piano | Famiglia | Limite |
| --- | --- | --- | --- |
| Socio | `open_2x_1m` | OPEN | 2 ingressi/settimana, 1 mese |
| Socio waitlist | `open_2x_1m` | OPEN | 2 ingressi/settimana, 1 mese |

## Test Flutter e Functions inclusi

I test automatici coprono in particolare:

- calcolo eligibility per modello legacy e multi-abbonamento;
- limiti settimanali, ingressi residui e scadenze;
- recupero nella stessa giornata e penalità di disiscrizione;
- waitlist e disponibilità del posto;
- widget calendario, card corso, filtri, sale e layout responsive;
- creazione/modifica utenti e corsi;
- autenticazione, simulazione utente e guardie sulle scritture;
- template email, link calendario e documento `.ics`;
- transazioni Functions, concorrenza, rimborsi e autorizzazioni;
- migrazioni utenti/corsi e convenzioni del codice.

## Ambiente e riproducibilità

Prerequisiti: Flutter 3.41.6, Node.js, `firebase-tools@15`, Java 21 e
ChromeDriver della stessa major di Chrome.

Comando consigliato per ripetere l'E2E locale:

```bash
export PATH="/usr/local/opt/openjdk@21/bin:$PATH"
export PATH="/percorso/alla/cartella/chromedriver:$PATH"
scripts/e2e.sh emulator
```

La procedura completa è descritta in
[`integration_test/README.md`](../integration_test/README.md).

## Note e limiti

- OneSignal viene chiamato dal client web durante il test, ma le notifiche
  reali non sono un criterio di successo dell'emulatore; l'esito del trigger è
  verificato tramite ricevuta backend.
- L'esecuzione contro Firebase staging è configurata nella CI, ma richiede
  credenziali ADC/OIDC e variabili Firebase non presenti localmente.
- Le fixture e i dati del run sono sintetici e non toccano il progetto di
  produzione.

## Commits principali

La PR contiene commit separati per implementazione, stabilizzazione E2E,
cleanup e documentazione. L'ultimo commit è `d38f2317`.
