# Migrazione Prova e Pacchetti ingressi

Questa estensione del runner converte i due modelli legacy a ingressi senza
alterare saldo, scadenza o fonte dei rimborsi. Il dettaglio operativo generale
resta nel [RUNBOOK](RUNBOOK.md).

## Mapping automatici

| Sorgente legacy | Vincoli | Piano V2 |
|---|---|---|
| `ABBONAMENTO_PROVA` | ruolo User, solo tag Open, saldo 0..1, scadenza valida | `open_trial_1i_30d` |
| `PACCHETTO_ENTRATE` | ruolo User, solo tag Open, saldo 0..10, scadenza valida | `open_10i_3m` |
| `PACCHETTO_ENTRATE` | ruolo User, solo tag Personal Trainer, saldo 0..10, scadenza valida | `pt_10i_3m` |

La Prova dura 30 giorni esatti. Il Pacchetto usa la durata nominale legacy di
tre mesi nel calendario Europe/Rome. `endDate` conserva esattamente
`fineIscrizione`; `remainingEntries` conserva esattamente
`entrateDisponibili`. Nessun saldo viene corretto o limitato implicitamente.

Gli ID sono deterministici:

- famiglia Open: `legacy_open_<userId>`;
- famiglia PT: `legacy_pt_<userId>`.

## Esclusioni che richiedono revisione

Il runner non converte automaticamente:

- saldi negativi, non interi o superiori al massimale;
- tag assenti, speciali o misti Open+PT;
- scadenze assenti o non interpretabili;
- finestre la cui data iniziale nominale è futura;
- ruoli diversi da User;
- conflitti con subscription V2 della stessa famiglia;
- utenti con una prenotazione futura fuori dalla finestra o dalla famiglia del
  piano target.

Le esclusioni sono riportate nei CSV con codici stabili. Non modificare a mano
il manifest per forzarle: bonificare la sorgente oppure usare la procedura
amministrativa guidata dopo una decisione di business.

## Cutover del modello

L'apply imposta `subscriptionModelVersion: 2`. Da quel momento l'assenza di un
abbonamento V2 vivo significa “nessun abbonamento attivo” e non riattiva il
fallback sui campi legacy. I campi legacy restano sul documento solo come
traccia durante il rollout.

La transazione crea il documento `subscriptions`, ricalcola
`activeSubscriptions`, scrive il marker versione 2 e converte ogni voce
`enrollmentConsumption.*.kind == LEGACY_ENTRY` in `SUBSCRIPTION_ENTRY`,
puntandola al nuovo documento. Il saldo non viene incrementato: il credito era
già stato scalato quando fu creata la prenotazione.

Il dry-run risolve anche le prenotazioni future presenti in `users.courses`.
Una prenotazione è coperta solo se la tipologia del corso appartiene ai tag del
piano e la data del corso cade nella finestra target. Il manifest congela queste
dipendenze; l'apply ricontrolla i corsi referenziati e produce `SOURCE_DRIFT` se
cambiano.

## Piano Prova

`open_trial_1i_30d` è un piano V2 di famiglia OPEN, modalità ENTRIES, massimo un
ingresso e durata di 30 giorni. Il client e le Functions lo riconoscono come
Prova tramite `planKey`, incluse conferma e promemoria di iscrizione. Non va
approssimato con `open_10i_1m`.

## Gate prima dell'apply

- zero `SOURCE_DRIFT` e `TARGET_CONFLICT`;
- nessun saldo o `endDate` diverso dalla sorgente;
- massimo una subscription attiva per famiglia;
- nessuna prenotazione futura non coperta;
- verifica di iscrizione, disiscrizione e rimborso prima/dopo la conversione;
- revisione esplicita di tutti gli utenti attivi esclusi.
