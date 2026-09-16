# Dry-run produzione — 16 settembre 2026

Esecuzione read-only sul progetto `fit-rope-app-1f575` con il supporto V2 per
Prova e Pacchetti. Gli artefatti completi, contenenti dati personali, restano
fuori da Git sotto `.context/migrations/`.

## Risultato generale

| Entità | Totale | Convertibili | Ignorati |
|---|---:|---:|---:|
| Corsi | 2.052 | 2.041 | 11 |
| Utenti | 561 | 234 | 327 |

Piani target dei 234 utenti convertibili:

| Gruppo | Quantità |
|---|---:|
| Prova `open_trial_1i_30d` | 53 |
| Pacchetto Open `open_10i_3m` | 84 |
| Pacchetto PT `pt_10i_3m` | 15 |
| Piani Open a frequenza | 82 |

Per tutti i 152 target a ingressi il dry-run ha verificato:

- zero differenze tra `entrateDisponibili` e `remainingEntries`;
- zero differenze tra `fineIscrizione` ed `endDate`;
- zero conflitti con subscription V2 esistenti;
- 233 prenotazioni future controllate sull'intera popolazione convertibile;
- zero esclusioni `FUTURE_BOOKING_NOT_COVERED`.

## Utenti attivi con scadenza corrente/futura

Sono automaticamente convertibili:

- 29 Prova Open;
- 31 Pacchetti Open;
- 11 Pacchetti PT.

Restano da revisionare tra gli utenti attivi/correnti:

- Prova: 7 saldi negativi/invalidi, 1 saldo oltre il massimale, 2 finestre con
  start futuro e 2 ruoli non User;
- Pacchetti: 3 saldi oltre il massimale, 4 finestre con start futuro e 3 shape
  di tag non univoche.

## Esclusioni complessive

| Codice | Quantità |
|---|---:|
| `MISSING_END_DATE` | 177 |
| `ROLE_NOT_USER` | 55 |
| `INVALID_TAG_SHAPE` | 52 |
| `FUTURE_START` | 14 |
| `INVALID_ENTRY_BALANCE` | 8 |
| `HEY_MAMMA` | 8 |
| `ENTRY_BALANCE_EXCEEDS_PLAN` | 7 |
| `INVALID_WEEKLY_FREQUENCY` | 5 |
| `INVALID_LEGACY_TYPE` | 1 |

## Audit integrità

L'audit ha prodotto 1 blocker e 1.539 warning preesistenti:

- 1 `SUBSCRIBED_COUNT_MISMATCH` su un corso futuro (`subscribed=7`, riferimenti
  utenti=6);
- 1.189 riferimenti a corsi storici mancanti;
- 50 disiscrizioni riferite a corsi mancanti;
- 300 mismatch storici del contatore iscritti.

Il blocker impedisce un apply conforme al runbook finché non viene corretto o
formalmente approvato. Il dry-run non ha effettuato alcuna scrittura.

## Artefatti privati

Directory locale:

```text
.context/migrations/prod-2026-09-16-1600-entries-v2-dry-run/
```

SHA-256 del manifest:

```text
a3b612b405d106849242f72d3eafe03e845c987550d3c21fe26fa91e7237a1d8
```

Directory `0700`, file `0600`.
