# Report E2E emulator — 2026-09-17

## Esito

**Non eseguito fino alla suite Flutter.** I tentativi hanno correttamente
usato OpenJDK 21.0.12.1 da `/usr/local/opt/openjdk@21` e ha avviato gli
emulatori isolati, ma ChromeDriver non ha aperto la porta 4444: `flutter drive`
è rimasto in attesa del debug service. Non ci sono quindi asserzioni
UI/backend da considerare superate.

Le fixture create dal control plane sono state eliminate manualmente e il file
manifest è stato rimosso; il cleanup è stato verificato.

## Run

- Project previsto: `demo-fitrope` (emulatore)
- Run ID: `e2e_1789626782363`
- Corso fixture: `e2e_e2e_1789626782363_course`

## Utenti creati e rimossi

| Ruolo | UID | Email |
| --- | --- | --- |
| Admin | `e2e_e2e_1789626782363_admin` | `e2e_e2e_1789626782363_admin@example.test` |
| Trainer | `e2e_e2e_1789626782363_trainer` | `e2e_e2e_1789626782363_trainer@example.test` |
| Socio | `e2e_e2e_1789626782363_member` | `e2e_e2e_1789626782363_member@example.test` |
| Socio waitlist | `e2e_e2e_1789626782363_waiter` | `e2e_e2e_1789626782363_waiter@example.test` |

## Abbonamenti creati e rimossi

| Utente | Subscription ID | Piano | Famiglia | Limite |
| --- | --- | --- | --- | --- |
| Socio | `e2e_e2e_1789626782363_member_open_2x_1m` | `open_2x_1m` | OPEN | 2 volte/settimana, 1 mese |
| Socio waitlist | `e2e_e2e_1789626782363_waiter_open_2x_1m` | `open_2x_1m` | OPEN | 2 volte/settimana, 1 mese |

## Azione necessaria

Riparare o reinstallare una versione di ChromeDriver compatibile e nativa con
Chrome/macOS, verificando prima che apra davvero la porta:

```bash
chromedriver --port=4444
lsof -nP -iTCP:4444 -sTCP:LISTEN
```

Il probe ChromeDriver ora riesce e apre la porta 4444. L'ultimo run ha però
avviato Chrome 152.0.7977.83 con ChromeDriver 150.0.7871.24 e `flutter drive`
è rimasto in attesa del debug service per oltre due minuti, senza avviare una
sessione WebDriver. Allineare ChromeDriver alla major 152, poi rieseguire
`scripts/e2e.sh emulator`.
