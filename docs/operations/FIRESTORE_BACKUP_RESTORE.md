# Backup e ripristino Firestore

Questa procedura opera sul solo database Firestore. Un export **non** include
Firebase Auth, Security Rules, indici o TTL: rules e indici si ripristinano da
Git; Auth resta fuori scope. L'import sovrascrive documenti con lo stesso ID,
ma non elimina quelli estranei: un ripristino esatto richiede quindi di
svuotare prima il database destinazione.

## Parametri approvati

| Ambiente | Bucket | Location |
|---|---|---|
| Produzione | `gs://fit-rope-app-1f575-firestore-backups` | `EU` (vicino a Firestore `eur3`) |
| Staging | `gs://fit-rope-staging-firestore-backups` | `europe-west8` |

I bucket usano Storage Standard, Uniform Bucket-Level Access e Public Access
Prevention. Impostare retention minima di 30 giorni (senza lock nel primo
rollout), lifecycle delete a 90 giorni e soft delete a 7 giorni. Eseguire
questi comandi con un'identità autorizzata e mantenere sempre il project
esplicito. Il file lifecycle versionato è
[`firestore-backup-lifecycle.json`](firestore-backup-lifecycle.json).

### Creazione e canary

```bash
gcloud storage buckets create gs://fit-rope-app-1f575-firestore-backups --location=EU --default-storage-class=STANDARD --uniform-bucket-level-access --public-access-prevention --project=fit-rope-app-1f575
gcloud storage buckets create gs://fit-rope-staging-firestore-backups --location=europe-west8 --default-storage-class=STANDARD --uniform-bucket-level-access --public-access-prevention --project=fit-rope-staging

canary_dir=$(mktemp -d)
printf 'fitrope-backup-canary\n' > "$canary_dir/canary.txt"
shasum -a 256 "$canary_dir/canary.txt" > "$canary_dir/expected.sha256"
gcloud storage cp "$canary_dir/canary.txt" gs://fit-rope-app-1f575-firestore-backups/canary/canary.txt --project=fit-rope-app-1f575
gcloud storage cp gs://fit-rope-app-1f575-firestore-backups/canary/canary.txt "$canary_dir/downloaded.txt" --project=fit-rope-app-1f575
cmp "$canary_dir/canary.txt" "$canary_dir/downloaded.txt"
gcloud storage rm gs://fit-rope-app-1f575-firestore-backups/canary/canary.txt --project=fit-rope-app-1f575
```

Ripetere il canary sul bucket staging. Solo dopo upload/download/delete riusciti
applicare retention, soft delete e lifecycle:

```bash
gcloud storage buckets update gs://fit-rope-app-1f575-firestore-backups --retention-period=30d --soft-delete-duration=7d --lifecycle-file=docs/operations/firestore-backup-lifecycle.json --project=fit-rope-app-1f575
gcloud storage buckets update gs://fit-rope-staging-firestore-backups --retention-period=30d --soft-delete-duration=7d --lifecycle-file=docs/operations/firestore-backup-lifecycle.json --project=fit-rope-staging
```

Non aggiungere `--lock-retention-period`. Verificare la configurazione restituita
prima di procedere:

```bash
gcloud storage buckets describe gs://fit-rope-app-1f575-firestore-backups --format=json --project=fit-rope-app-1f575
gcloud storage buckets describe gs://fit-rope-staging-firestore-backups --format=json --project=fit-rope-staging
```

La sintassi dei flag e del lifecycle JSON è quella documentata da
[Google Cloud Storage](https://cloud.google.com/sdk/gcloud/reference/storage/buckets/update).

### IAM

```bash
gcloud iam service-accounts create fitrope-firestore-backup --project=fit-rope-app-1f575
gcloud projects add-iam-policy-binding fit-rope-app-1f575 --member=serviceAccount:fitrope-firestore-backup@fit-rope-app-1f575.iam.gserviceaccount.com --role=roles/datastore.importExportAdmin
gcloud storage buckets add-iam-policy-binding gs://fit-rope-app-1f575-firestore-backups --member=serviceAccount:fitrope-firestore-backup@fit-rope-app-1f575.iam.gserviceaccount.com --role=roles/storage.admin
gcloud storage buckets add-iam-policy-binding gs://fit-rope-app-1f575-firestore-backups --member=serviceAccount:service-30076380522@gcp-sa-firestore.iam.gserviceaccount.com --role=roles/storage.admin
gcloud storage buckets add-iam-policy-binding gs://fit-rope-staging-firestore-backups --member=serviceAccount:service-289611080024@gcp-sa-firestore.iam.gserviceaccount.com --role=roles/storage.admin --project=fit-rope-staging
```

Concedere al deployer `roles/iam.serviceAccountUser` limitato al service account
runtime (include `iam.serviceAccounts.actAs`). I managed export usano il
[Firestore service agent](https://cloud.google.com/firestore/docs/manage-data/export-import#service_agent_permissions)
per l'accesso effettivo al bucket.

## Export e controllo

La function `firestoreBackupDaily` viene esportata solo in PRD: alle 02:00 UTC
crea `automatic/YYYY/MM/DD/firestore-<timestamp>-attempt-N`, registra lo stato
in `_systemBackupRuns/YYYY-MM-DD` e salva il manifest
`_manifests/YYYY/MM/DD.json`. Il check delle 03:00 UTC fallisce se il run non è
`SUCCEEDED`. Staging ed Emulator non devono elencare queste funzioni.

```bash
gcloud firestore export gs://fit-rope-app-1f575-firestore-backups/manual/<run-id> --database='(default)' --project=fit-rope-app-1f575
gcloud firestore operations list --database='(default)' --project=fit-rope-app-1f575
gcloud firestore operations describe <operation-name> --project=fit-rope-app-1f575
gcloud storage ls gs://fit-rope-app-1f575-firestore-backups/automatic/
gcloud storage cat gs://fit-rope-app-1f575-firestore-backups/_manifests/YYYY/MM/DD.json
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
gcloud storage cp gs://fit-rope-app-1f575-firestore-backups/_manifests/YYYY/MM/DD.json "$backup_dir/manifest.json"
chmod -R go-rwx "$backup_dir"
(cd "$backup_dir" && find . -type f ! -name checksums.sha256 -print0 | sort -z | xargs -0 shasum -a 256 > checksums.sha256)
chmod 600 "$backup_dir/checksums.sha256"
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
