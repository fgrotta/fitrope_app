# Migrazione Tipo/Tag e abbonamenti legacy — piano aggiornato

## Baseline produzione

Analisi read-only del 26 agosto 2026 su `fit-rope-app-1f575`:

- 1.975 corsi, nessun documento V2 e nessun Hyrox.
- 1.964 corsi convertibili automaticamente; 11 esclusi.
- 505 utenti, nessuna collezione `subscriptions`, zero `activeSubscriptions` e zero HYROX.
- 58 utenti convertibili automaticamente.
- 447 utenti ignorati perché privi di una corrispondenza esatta.
- Prima della rimozione del legacy, 71 utenti attivi con scadenza futura richiedono bonifica manuale.
- 8 utenti e 9 corsi storici contengono Hey Mamma: restano esclusi e non modificabili.

## Matrici di conversione

### Corsi

Il vecchio `courseType` viene ignorato e sovrascritto.

| Input `tags` | `courseType` | `tag` | Mirror `tags` | Quantità |
|---|---|---|---|---:|
| assente | `open` | `null` | `['Open']` | 532 |
| `[]` | `open` | `null` | `['Open']` | 365 |
| `['Open']` | `open` | `null` | `['Open']` | 568 |
| `['Personal Trainer']` | `personal_trainer` | `'Personal Trainer'` | `['Personal Trainer']` | 499 |
| contiene `Hey Mamma` | ignorato | — | invariato | 9 |
| `['Open','Personal Trainer']` | ignorato | — | invariato | 2 |
| qualsiasi altra shape | ignorato | — | invariato | 0 |

Tutti i 109 corsi futuri sono convertibili.

### Utenti

Un utente viene convertito solo quando:

- `role == 'User'`;
- non contiene Hey Mamma;
- `tipologiaCorsoTags == ['Open']`;
- la tipologia è mensile, trimestrale, semestrale o annuale;
- `entrateSettimanali` è 2, 3 o `null`;
- `fineIscrizione` è presente;
- `startDate = fineIscrizione - durata` in Europe/Rome non è futura rispetto al timestamp del dry-run.

| Legacy | Frequenza | Piano target |
|---|---:|---|
| Mensile | 2/3/illimitato | `open_2x_1m` / `open_3x_1m` / `open_unlim_1m` |
| Trimestrale | 2/3/illimitato | `open_2x_3m` / `open_3x_3m` / `open_unlim_3m` |
| Semestrale | 2/3/illimitato | `open_2x_6m` / `open_3x_6m` / `open_unlim_6m` |
| Annuale | 2/3/illimitato | `open_2x_12m` / `open_3x_12m` / `open_unlim_12m` |

Distribuzione delle 58 conversioni automatiche:

| Piano | Utenti |
|---|---:|
| `open_2x_1m` | 15 |
| `open_3x_1m` | 3 |
| `open_2x_3m` | 25 |
| `open_3x_3m` | 3 |
| `open_2x_6m` | 9 |
| `open_3x_6m` | 2 |
| `open_3x_12m` | 1 |

Vengono ignorati e riportati:

- 334 pacchetti ingressi o prove;
- 53 documenti con ruolo diverso da User o assente;
- 32 shape invalide o ambigue;
- 8 utenti Hey Mamma;
- 20 utenti con data iniziale nominale futura.

Non esiste alcun fallback. Il legacy viene eliminato solo dopo la bonifica manuale dei 71 utenti correnti esclusi.

## Report CSV utenti

Il dry-run genera obbligatoriamente:

```text
.context/migrations/<run-id>/users-migration-report.csv
```

Formato:

- UTF-8 con BOM, per apertura corretta in Excel;
- separatore `;`;
- intestazione obbligatoria;
- date ISO 8601 con timezone;
- liste serializzate come JSON nella singola cella;
- escaping CSV conforme RFC 4180;
- permessi file `0600`;
- nessun dato personale stampato integralmente nella console.

Colonne:

```text
run_id
evaluated_at
project_id
document_id
uid
email
name
last_name
numero_telefono
role
is_active
created_at
tipologia_iscrizione
tipologia_corso_tags
entrate_disponibili
entrate_settimanali
fine_iscrizione
conversion_status
reason_code
reason_detail
target_subscription_id
target_plan_key
target_family
target_billing_mode
target_course_type_tags
target_weekly_frequency
target_remaining_entries
target_start_date
target_end_date
apply_status
```

Valori di `conversion_status`:

- `CONVERTIBLE`
- `IGNORED`
- `ALREADY_APPLIED`
- `SOURCE_DRIFT`
- `TARGET_CONFLICT`

Codici principali di esclusione:

- `HEY_MAMMA`
- `ROLE_NOT_USER`
- `NO_EXACT_ENTRIES_PLAN`
- `TRIAL_NOT_SUPPORTED`
- `INVALID_LEGACY_TYPE`
- `INVALID_TAG_SHAPE`
- `INVALID_WEEKLY_FREQUENCY`
- `MISSING_END_DATE`
- `FUTURE_START`
- `EXISTING_SUBSCRIPTION_CONFLICT`

Il CSV contiene sempre tutti i 505 utenti, inclusi quelli convertibili e quelli ignorati. Un CSV analogo, senza dati utente, registra le decisioni sui corsi:

```text
.context/migrations/<run-id>/courses-migration-report.csv
```

Il manifest machine-readable usato da `--apply` resta separato dal report CSV e contiene fingerprint e target completi. Non è destinato alla modifica manuale.

## Runner di migrazione

Implementare trasformatori puri sotto `functions/src/migration/` e un runner:

```text
node scripts/backfillCourseModel.js \
  --project=fit-rope-app-1f575 \
  --scope=courses|users|all \
  --dry-run \
  --report-dir=.context/migrations/<run-id>

node scripts/backfillCourseModel.js \
  --project=fit-rope-app-1f575 \
  --scope=all \
  --apply \
  --manifest=.context/migrations/<run-id>/manifest.jsonl \
  --confirm-project=fit-rope-app-1f575

node scripts/backfillCourseModel.js \
  --project=fit-rope-app-1f575 \
  --verify
```

Comportamento:

- `--dry-run` è il default e non scrive su Firestore.
- Congela `evaluatedAt`, classificazione, source fingerprint e target.
- `--apply` richiede il manifest del dry-run revisionato.
- Una sorgente cambiata dopo il dry-run viene ignorata come `SOURCE_DRIFT`.
- I corsi vengono aggiornati con `BulkWriter`.
- Subscription e snapshot utente vengono scritti in transazione.
- Gli ID subscription sono deterministici.
- Una seconda esecuzione produce zero scritture sugli stessi dati.
- Un target identico è `ALREADY_APPLIED`; un target diverso è `TARGET_CONFLICT` e non viene sovrascritto.
- `endDate` conserva esattamente `fineIscrizione`.
- `startDate` usa la sottrazione nominale Europe/Rome; se futura, l’utente viene ignorato.
- Le subscription scadute vengono conservate ma non inserite in `activeSubscriptions`.
- Il CSV viene rigenerato anche dopo `--apply` e `--verify`, valorizzando `apply_status`.

## Modello, parser e rules

- Aggiungere `Course.tag`, `courseModelV2` e il resolver centralizzato V1/V2.
- Rimuovere HYROX da enum, cataloghi, registry, label e seed nella stessa PR.
- Aggiungere i quattro piani Open a ingressi.
- Parser client/server stretti: valori sconosciuti producono errore e log, mai coercizione o fallback.
- Eligibility, waitlist, unsubscribe, rimborsi e conteggio settimanale usano esclusivamente il tipo del corso.
- Hey Mamma sparisce da UI, filtri e selettori; i documenti storici restano V1 read-only.

Le Firestore Rules accettano soltanto shape V2 esatte:

| Shape | Esito |
|---|---|
| Open, `tag: null`, `tags: ['Open']` | accettata |
| Open, tag descrittivo, `tags: ['Open', tag]` | accettata |
| PT, tag PT, `tags: ['Personal Trainer']` | accettata |
| Open con tag PT | negata |
| PT con tag diverso da PT | negata |
| mirror invertito, incompleto o con valori aggiuntivi | negata |
| documento nuovo senza `courseModelV2 == true` | negata |
| modifica client di un corso storico Hey Mamma | negata |

Il confronto esatto del mirror è necessario perché il type tag deve essere il primo elemento per i client vecchi e perché nessun tag aggiuntivo deve tornare a influenzare l’accesso.

## Rollout e test

1. Deploy Functions tolleranti V1/V2 e nuovo catalogo.
2. Export Firestore.
3. Dry-run e revisione dei CSV.
4. Apply di 58 utenti e 1.964 corsi.
5. `--verify`.
6. Deploy nuova web app.
7. Deploy rules strette con breve freeze del CRUD corsi.
8. Nuovo `--verify`.
9. Bonifica manuale dei 71 utenti correnti esclusi, usando il CSV come lista di lavoro.
10. Gate: zero utenti attivi/correnti senza subscription valida o esclusione approvata.
11. Rimozione definitiva del ramo legacy e di `tipologiaCorsoTags` dall’eligibility.
12. Cleanup del dual-write sui corsi V2; gli 11 corsi esclusi restano storici e read-only.

Test obbligatori:

- ogni riga delle matrici e ogni `reason_code`;
- produzione del CSV con escaping di delimitatori, virgolette, Unicode e newline;
- protezione dei dati personali e permessi `0600`;
- sottrazione mesi Europe/Rome e casi DST;
- esclusione dei 20 `FUTURE_START`;
- dry-run senza scritture;
- seconda apply con zero scritture;
- `SOURCE_DRIFT` e `TARGET_CONFLICT`;
- transazione subscription/snapshot;
- rules sulle shape valide e invalide;
- Hey Mamma assente dalla UI e non modificabile;
- dopo il gate finale, nessun accesso tramite campi legacy.
