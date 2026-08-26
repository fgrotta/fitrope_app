# Migrazione modello corsi V2 e abbonamenti legacy

Questa cartella conserva in Git il contesto completo della migrazione introdotta
dalla PR dedicata al modello corsi V2.

- [PIANO.md](PIANO.md): baseline di produzione del 26 agosto 2026, matrici di
  conversione, scelte di modello, vincoli e sequenza di rollout.
- [RUNBOOK.md](RUNBOOK.md): procedura operativa passo passo per preparare,
  simulare, applicare e verificare la migrazione.

Il codice eseguibile si trova in:

- `scripts/backfillCourseModel.js`: runner e protezioni operative;
- `functions/src/migration/`: trasformatori puri e generazione CSV;
- `functions/src/__tests__/migration*.test.ts`: test unitari;
- `functions/src/__integration__/migrationRunner.integration.test.ts`: test del
  runner contro Firestore Emulator.

## Separazione tra documentazione e dati operativi

Questa cartella non deve contenere manifest o report generati dal runner. Quei
file possono includere dati personali e vengono accettati esclusivamente sotto:

```text
.context/migrations/<run-id>/
```

La directory `.context` è esclusa dal versionamento. Non copiare CSV, manifest,
export Firestore o credenziali dentro `docs/` e non allegarli a issue o PR.

I numeri in `PIANO.md` descrivono una fotografia read-only del 26 agosto 2026:
sono una baseline di controllo, non un valore atteso immutabile. Prima di ogni
apply occorre produrre e revisionare un nuovo dry-run.
