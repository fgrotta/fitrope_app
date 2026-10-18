---
name: aggiorna-documentazione
description: Usa quando l'utente chiede di aggiornare la documentazione, le guide o la Guida Admin di FitRope, dopo uno o più merge su develop, o prima di aprire una PR che cambia schermate, etichette, messaggi o regole di business.
---

# Aggiornare documentazione e Guida Admin

Il registro `docs/stato-documentazione.json` dice, per ogni documento, quali file descrive (`sorgenti`) e fino a quale commit di develop è stato verificato (`verificato.sha`). Lo script confronta i due e ti dà la lista di cosa rileggere. Tu decidi cosa cambiare e poi sposti il watermark.

## Procedimento

1. **Rileva.** Lancia `git fetch origin develop` (aggiorna solo i riferimenti remoti, va bene), poi `python3 .claude/skills/aggiorna-documentazione/scripts/pendenti.py`. Il report elenca per ogni documento i commit su develop dopo la verifica e quelli del branch che toccano le sue sorgenti. Se il documento è già stato modificato su questo branch, il report lo dice: parti da lì. Le modifiche non committate sono solo informative. Se l'utente chiede un audit completo, o il documento compare fra i **watermark stimati**, usa `--da <ref>` (per esempio il commit di una data: `git rev-list -1 --before=2026-09-01 origin/develop`).
2. **Leggi ogni commit pendente.** Usa `git show --stat <sha>`, poi il diff dei file elencati. "Aggiornava anche il documento" vuol dire che probabilmente è già a posto: verificalo comunque. Le PR ancora aperte (`gh pr list --repo fgrotta/fitrope_app`) non si documentano qui.
3. **Confronta con il documento e decidi.** Ogni documento pendente finisce in uno di tre stati: **aggiornato**, **già corretto** oppure **da decidere** (serve una scelta dell'utente; non va segnato). Per le guide (`assets/guida/<id>.md`):
   - scrivi in italiano per staff non tecnico, con passi numerati e senza nomi di campi, collezioni o file;
   - copia le etichette esatte dal codice e controllale con `grep -rn "<etichetta>" lib/`;
   - se un'etichetta usata come selettore cambia, aggiorna anche `tool/guida/scenarios/<id>.mjs`.
4. **Gestisci i "Non coperti".** Sono file che nessun documento segue.
   - Se è una funzione Admin nuova, proponi all'utente una guida nuova o una sezione di una esistente, e chiedi prima di crearla. Se non puoi chiedere, mettila fra i **da decidere**. Una guida nuova richiede la voce in `guide_catalog.dart`, il `.md`, lo scenario, la riga `- assets/guida/img/<id>/` in `pubspec.yaml` e la voce `guida/<id>` nel registro.
   - Altrimenti aggiungi il file alle `sorgenti` del documento giusto, oppure a `copertura.ignora`.
   - Poi lancia `--segna copertura`. Se la sezione non compare, non serve.
5. **Aggiorna i documenti tecnici.**
   - Le regole di business vanno in `agents.md` e `lib/api/courses/README_ISCRIZIONI.md`.
   - Comandi, CI, rollout e trappole vanno in `CLAUDE.md`. Le lezioni nuove vanno anche nella memoria di progetto.
6. **Rigenera gli screenshot.** Lancia `./scripts/guida_screenshots.sh <id> <id>…` **solo** per le guide la cui schermata catturata è cambiata: quelle di cui hai toccato `.md` o scenario, e quelle con un commit pendente che cambia l'aspetto di una schermata fotografata, anche se il testo resta valido (circa 1–2 minuti ciascuna). Salta le guide già rigenerate in un commit successivo alla modifica. Poi apri un paio di PNG nuovi e controlla che mostrino la schermata giusta.
7. **Segna.** Lancia `pendenti.py --segna <chiave> …` su ogni documento pendente che hai verificato, sia quelli aggiornati sia quelli già corretti; i "da decidere" no. I documenti senza commit dopo la verifica non vanno segnati, a meno che tu non li abbia riletti con `--da`. Il watermark va al merge-base fra HEAD e develop, più l'HEAD del branch. Rilancia il report: quei documenti non devono più comparire. Dopo il merge della PR il commit di merge ricompare una volta su develop: rileggilo e risegna.
8. **Esegui i gate.**
   - Sempre: `flutter test test/guide_catalog_test.dart`.
   - Se hai toccato codice Dart: anche `flutter test`, `flutter analyze --no-fatal-infos` e `dart format --set-exit-if-changed .` (dopo `flutter pub get`).
   - Se hai toccato lo script: `python3 -m unittest discover -s .claude/skills/aggiorna-documentazione/scripts -p 'test_*.py'`.
9. **Chiudi con un report.** Prepara una tabella documento → aggiornato / già corretto / da decidere, con i commit che motivano ogni modifica e le guide rigenerate. Non fare commit se l'utente non lo chiede.

## Errori comuni

- **Segnare senza aver letto il diff.** Il watermark dichiara che il documento è stato verificato fino a quel commit. Se lo sposti senza leggere, nasconde per sempre la modifica.
- **Fidarsi di un commit che dice "guide allineate".** Verifica le etichette nel codice.
- **Considerare corretto un documento solo perché non ha pendenti.** "Nessun commit dopo la verifica" non copre la deriva precedente al watermark, soprattutto se è stimato: per quella serve `--da`.
- **Rigenerare tutte le guide.** Ci vogliono circa 12 minuti e cambiano le date in ogni immagine, quindi il diff diventa illeggibile.
- **Fare screenshot dalla produzione o dall'emulatore condiviso.** Lo script usa un emulatore suo: non aggirarlo.
- **Lasciare lo stesso file in più `sorgenti` senza motivo.** Ogni commit su quel file diventa rumore in più documenti.
