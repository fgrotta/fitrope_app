# Backup e ripristino Firestore

Questa procedura opera sul solo database Firestore. Un export **non** include
Firebase Auth, Security Rules, indici o TTL: rules e indici si ripristinano da
Git; Auth resta fuori scope. L'import sovrascrive documenti con lo stesso ID,
ma non elimina quelli estranei: un ripristino esatto richiede quindi di
svuotare prima il database destinazione.

## Parametri approvati

| Ambiente | Bucket | Location |
|---|---|---|
| Produzione | `gs://fit-rope-app-1f575-firestore-backups` | `eur3` |
| Staging | `gs://fit-rope-staging-firestore-backups` | `europe-west8` |

I bucket usano Storage Standard, Uniform Bucket-Level Access e Public Access
Prevention. Impostare retention minima di 30 giorni (senza lock nel primo
rollout), lifecycle delete a 90 giorni e soft delete a 7 giorni. Eseguire
questi comandi con un'identità autorizzata e mantenere sempre il project
esplicito:

```bash
gcloud storage buckets create gs://fit-rope-app-1f575-firestore-backups --location=eur3 --default-storage-class=STANDARD --uniform-bucket-level-access --public-access-prevention --project=fit-rope-app-1f575
gcloud storage buckets update gs://fit-rope-app-1f575-firestore-backups --retention-period=30d --project=fit-rope-app-1f575
gcloud storage buckets update gs://fit-rope-app-1f575-firestore-backups --soft-delete-duration=7d --project=fit-rope-app-1f575
gcloud iam service-accounts create fitrope-firestore-backup --project=fit-rope-app-1f575
gcloud projects add-iam-policy-binding fit-rope-app-1f575 --member=serviceAccount:fitrope-firestore-backup@fit-rope-app-1f575.iam.gserviceaccount.com --role=roles/datastore.importExportAdmin
gcloud storage buckets add-iam-policy-binding gs://fit-rope-app-1f575-firestore-backups --member=serviceAccount:fitrope-firestore-backup@fit-rope-app-1f575.iam.gserviceaccount.com --role=roles/storage.admin
```

Concedere inoltre al Firestore service agent l'accesso al bucket e al deployer
`iam.serviceAccounts.actAs` sul service account. Testare prima con un canary
eliminabile; aggiungere la lifecycle policy con la console o un file JSON
versionato nel runbook del change. Non attivare il retention lock nel rollout
iniziale.

## Export e controllo

La function `firestoreBackupDaily` viene esportata solo in PRD: alle 02:00 UTC
crea `automatic/YYYY/MM/DD/firestore-<timestamp>-attempt-N`, registra lo stato
in `_systemBackupRuns/YYYY-MM-DD` e salva il manifest
`_manifests/YYYY-MM-DD.json`. Il check delle 03:00 UTC fallisce se il run non è
`SUCCEEDED`. Staging ed Emulator non devono elencare queste funzioni.

```bash
gcloud firestore export gs://fit-rope-app-1f575-firestore-backups/manual/<run-id> --database='(default)' --project=fit-rope-app-1f575
gcloud firestore operations list --database='(default)' --project=fit-rope-app-1f575
gcloud firestore operations describe <operation-name> --project=fit-rope-app-1f575
gcloud storage ls gs://fit-rope-app-1f575-firestore-backups/automatic/
gcloud storage cat gs://fit-rope-app-1f575-firestore-backups/_manifests/YYYY-MM-DD.json
```

Per lanciare il job manualmente, individuarlo e forzarlo dal progetto PRD:

```bash
gcloud scheduler jobs list --location=europe-west8 --project=fit-rope-app-1f575
gcloud scheduler jobs run firebase-schedule-firestoreBackupDaily-europe-west8 --location=europe-west8 --project=fit-rope-app-1f575
```

Scaricare una copia locale con permessi privati e registrare checksum del
manifest (gli export e i CSV con PII non entrano mai in Git):

```bash
backup_dir=/Users/Frank/Backups/FitRope/firestore/prod/$(date +%F)
mkdir -p "$backup_dir" && chmod 700 "$backup_dir"
gcloud storage cp --recursive gs://fit-rope-app-1f575-firestore-backups/manual/<run-id> "$backup_dir/"
gcloud storage cp gs://fit-rope-app-1f575-firestore-backups/_manifests/YYYY-MM-DD.json "$backup_dir/manifest.json"
chmod -R go-rwx "$backup_dir"
shasum -a 256 "$backup_dir/manifest.json" > "$backup_dir/manifest.sha256"
chmod 600 "$backup_dir/manifest.sha256"
```

## Ripristino

Prima opzione: import non distruttivo in un database temporaneo
`restore-YYYYMMDD` creato nella stessa location `eur3`; verificare lì l'export
prima di toccare `(default)`.

```bash
gcloud firestore databases create --database=restore-YYYYMMDD --location=eur3 --project=fit-rope-app-1f575
gcloud firestore import gs://fit-rope-app-1f575-firestore-backups/manual/<run-id> --database=restore-YYYYMMDD --project=fit-rope-app-1f575
```

Per l'emergenza su `(default)`: 1) bloccare scritture, Scheduler e deploy; 2)
creare un export di sicurezza dello stato corrente; 3) svuotare tutte le
collection con uno script Admin SDK controllato; 4) importare l'**output URI
completo**; 5) attendere l'operazione; 6) ridistribuire rules e indici; 7)
eseguire smoke test e riaprire le scritture. Il comando di import è:

```bash
gcloud firestore import gs://fit-rope-app-1f575-firestore-backups/manual/<run-id> --database='(default)' --project=fit-rope-app-1f575
```

Non usare i backup schedulati nativi per questo requisito: non permettono né
l'orario esatto né il bucket richiesto. Restano un'alternativa futura per
snapshot point-in-time consistenti.
