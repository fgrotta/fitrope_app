# Report E2E emulator — 2026-09-17

## Esito

**Superato.** La suite E2E su Emulator Suite ha completato i 3 scenari Flutter
e l'assert backend finale. Il run ha usato OpenJDK 21, Chrome 152 e
ChromeDriver 152.0.7977.83.

Le fixture sono state eliminate allo shutdown degli emulatori; non sono rimasti
processi Firebase o ChromeDriver attivi.

## Run

- Project: `demo-fitrope` (emulatore)
- Run ID: `e2e_1789648066755`
- Corso v2: `e2e_e2e_1789648066755_course`
- Corso legacy: `e2e_e2e_1789648066755_legacy_course`

## Utenti creati e rimossi

| Ruolo | UID | Email |
| --- | --- | --- |
| Admin | `e2e_e2e_1789648066755_admin` | `e2e_e2e_1789648066755_admin@example.test` |
| Trainer | `e2e_e2e_1789648066755_trainer` | `e2e_e2e_1789648066755_trainer@example.test` |
| Socio | `e2e_e2e_1789648066755_member` | `e2e_e2e_1789648066755_member@example.test` |
| Socio waitlist | `e2e_e2e_1789648066755_waiter` | `e2e_e2e_1789648066755_waiter@example.test` |
| Socio legacy | `e2e_e2e_1789648066755_legacy` | `e2e_e2e_1789648066755_legacy@example.test` |
| Registrazione | creato durante il test e poi eliminato | `e2e_e2e_1789648066755_registration@example.test` |

## Abbonamenti creati e rimossi

| Utente | Subscription ID | Piano | Famiglia | Limite |
| --- | --- | --- | --- | --- |
| Socio | `e2e_e2e_1789648066755_member_open_2x_1m` | `open_2x_1m` | OPEN | 2 volte/settimana, 1 mese |
| Socio waitlist | `e2e_e2e_1789648066755_waiter_open_2x_1m` | `open_2x_1m` | OPEN | 2 volte/settimana, 1 mese |

L'utente legacy ha usato il modello `PACCHETTO_ENTRATE` con 2 crediti (nessun
documento `subscriptions`); il test ha verificato decremento a 1 e rimborso a
2 dopo la disiscrizione.

## Assert finale

```json
{"courseId":"e2e_e2e_1789648066755_course","subscribed":1,"waitlist":[],"memberCourses":[],"waiterCourses":["e2e_e2e_1789648066755_course"]}
```

Scenari coperti: iscrizione socio, lista d'attesa con conferma, rilascio posto
e subentro del socio in waitlist; registrazione con prova e verifica email;
iscrizione/disiscrizione legacy con rimborso.

Test automatici: Flutter **541** test superati; Cloud Functions **400** test
superati.

## Comando di ripetizione

```bash
export PATH="/tmp/chromedriver-152.0.7977.83.ChzD4r/chromedriver-mac-x64:$PATH"
scripts/e2e.sh emulator
```
