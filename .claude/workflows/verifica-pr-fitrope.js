export const meta = {
  name: 'verifica-pr-fitrope',
  description: 'Gate di verifica multi-agent per un PR FitRope (qualità, test, specifiche, adversariale, completezza). Tier scalabile per rischio.',
  whenToUse: 'Dopo aver committato un PR del piano Sale/pacchetti, prima di passare al successivo.',
  phases: [
    { title: 'Review', detail: 'Lane indipendenti per dimensione' },
    { title: 'Sintesi', detail: 'Aggregazione e verdetto' },
  ],
}

// args: { base?: string, head?: string, label?: string, tier?: 1|2|3, spec?: string }
const base = (args && args.base) || 'HEAD~1'
const head = (args && args.head) || 'HEAD'
const label = (args && args.label) || 'PR'
const tier = (args && args.tier) || 2 // default: include adversariale + completeness
const spec = (args && args.spec) || '(nessuna spec esplicita: deduci gli obiettivi dal messaggio di commit e dai file in .context/)'

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'verdict', 'findings', 'summary'],
  properties: {
    dimension: { type: 'string' },
    verdict: { type: 'string', enum: ['pass', 'pass_with_concerns', 'fail'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'title', 'detail'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] },
          title: { type: 'string' },
          detail: { type: 'string' },
          file: { type: 'string' },
          suggestion: { type: 'string' },
        },
      },
    },
    summary: { type: 'string' },
  },
}

const CTX = `App Flutter FitRope. Working dir = repo corrente.
PR in verifica: ${label}. Diff = \`git diff ${base} ${head}\` (oppure \`git show ${head}\`).
Piano e decisioni in .context/PIANO_DETTAGLIATO_opzione2.md e .context/PIANO_sale_pacchetti_abbonamenti.md.
SOLA LETTURA: non modificare file. Riporta findings concreti con severità/file/suggerimento.`

const lanes = [
  {
    dimension: 'code_quality',
    prompt: `${CTX}\n\nLane QUALITÀ DEL CODICE (effort alto). Correttezza, idiomaticità Dart/TS, coerenza con lo stile circostante, naming, null-safety, serializzazione, assenza di dead code/duplicazioni, robustezza. Esegui anche \`flutter analyze\` mentalmente sui file toccati e segnala regressioni (non i lint info preesistenti).`,
  },
  {
    dimension: 'test_integrity',
    prompt: `${CTX}\n\nLane INTEGRITÀ DEI TEST. I test nuovi/modificati verificano davvero il comportamento? Assert significativi (non tautologici)? Casi limite coperti? Comportamenti nuovi importanti SCOPERTI? Test fragili o che passerebbero con implementazione errata? Indica le lacune con esempi di test mancanti.`,
  },
  {
    dimension: 'functional_spec',
    prompt: `${CTX}\n\nLane CONFORMITÀ ALLE SPECIFICHE. Specifiche del PR:\n${spec}\nVerifica ogni requisito sul codice reale; segnala requisiti mancanti, parziali o deviati. Segnala anche scope creep (cose fatte fuori dallo scope del PR).`,
  },
]

if (tier >= 2) {
  lanes.push({
    dimension: 'adversarial',
    prompt: `${CTX}\n\nLane ADVERSARIALE. Il tuo obiettivo è ROMPERE la logica introdotta: trova input/edge case che producono comportamento errato (off-by-one nei conteggi, settimana a cavallo, illimitato vs null, scadenza al confine, doppio decremento ingressi, race, fallback legacy che non scatta, accesso per tag bypassabile). Per ogni rottura plausibile dai uno scenario concreto e dove fallisce.`,
  })
  lanes.push({
    dimension: 'completeness_critic',
    prompt: `${CTX}\n\nLane COMPLETENESS CRITIC. Cosa MANCA? Requisito del piano non implementato, caso non testato, file/consumer non aggiornato, doc/README non allineato, migrazione/fallback non gestito, incoerenza tra piano e codice. Elenca i buchi, non i pregi.`,
  })
}

if (tier >= 3) {
  lanes.push({
    dimension: 'security',
    prompt: `${CTX}\n\nLane SICUREZZA. Per le scritture server/regole: autenticazione e ruolo verificati nelle Cloud Functions? Il client può ancora scrivere campi critici (entrateDisponibili, subscribed, activeSubscriptions, fineIscrizione, role)? Le firestore.rules negano davvero le scritture sensibili? Transazioni atomiche e non spoofabili? Segreti non esposti? Segnala ogni superficie sfruttabile.`,
  })
}

phase('Review')
const results = (await parallel(
  lanes.map((l) => () =>
    agent(l.prompt, { label: `${label}:${l.dimension}`, phase: 'Review', schema: SCHEMA })
  )
)).filter(Boolean)

phase('Sintesi')
const blockers = results.flatMap((r) => r.findings.filter((f) => f.severity === 'blocker'))
const majors = results.flatMap((r) => r.findings.filter((f) => f.severity === 'major'))
const overall = blockers.length ? 'FAIL' : (majors.length ? 'PASS_WITH_MAJORS' : 'PASS')

return { label, tier, overall, blockers: blockers.length, majors: majors.length, results }
