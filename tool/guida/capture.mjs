#!/usr/bin/env node
// Rigenera screenshot e animazioni della Guida Admin dall'emulatore.
//
// Di norma non si lancia a mano: `scripts/guida_screenshots.sh [id…]` avvia
// emulatore, build e server, poi chiama questo file. Lanciarlo da solo serve
// quando quei tre sono già su (vedi README.md):
//
//   node tool/guida/capture.mjs              # tutte le guide
//   node tool/guida/capture.mjs abbonamenti  # una sola
//
// Ogni scenario riparte da un emulatore azzerato e riseminato, quindi non
// dipende dagli altri e si può rilanciare quante volte si vuole. Le immagini
// vengono scritte in una cartella temporanea e sostituiscono
// `assets/guida/img/<id>/` solo se lo scenario va a buon fine.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from 'playwright';
import { EmulatorFirestore } from './lib/firestore.mjs';
import { Guide, HIDE_EMULATOR_BANNER, VIEWPORT } from './lib/helpers.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const SCENARIOS = path.join(HERE, 'scenarios');
const ASSETS = path.join(ROOT, 'assets', 'guida', 'img');
const WORK = path.join(ROOT, 'build', 'guida_capture');

const PROJECT = 'fit-rope-app-1f575';
const APP_URL = process.env.GUIDA_URL ?? 'http://localhost:5621/index.html';
const AUTH_PORT = process.env.GUIDA_AUTH_PORT ?? '29099';
const FIRESTORE_PORT = process.env.GUIDA_FIRESTORE_PORT ?? '28080';

// Host che l'app contatterebbe se NON fosse agganciata all'emulatore. Uno solo
// di questi basta a fermare tutto: gli screenshot devono mostrare solo dati
// sintetici, mai quelli dei soci.
const PRODUCTION_HOSTS = [
  'identitytoolkit.googleapis.com',
  'securetoken.googleapis.com',
  'firestore.googleapis.com',
  'cloudfunctions.net',
];

function run(cmd, args, opts = {}) {
  const res = spawnSync(cmd, args, { stdio: 'inherit', ...opts });
  if (res.status !== 0) throw new Error(`${cmd} ${args.join(' ')} → exit ${res.status}`);
}

async function wipeEmulator() {
  const firestore =
    `http://localhost:${FIRESTORE_PORT}/emulator/v1/projects/${PROJECT}` +
    '/databases/(default)/documents';
  const auth = `http://localhost:${AUTH_PORT}/emulator/v1/projects/${PROJECT}/accounts`;
  for (const url of [firestore, auth]) {
    const res = await fetch(url, { method: 'DELETE' });
    if (!res.ok) throw new Error(`Azzeramento fallito (${res.status}): ${url}`);
  }
}

async function reseed() {
  await wipeEmulator();
  const env = {
    ...process.env,
    SEED_FIRESTORE_PORT: FIRESTORE_PORT,
    SEED_AUTH_PORT: AUTH_PORT,
    FIRESTORE_EMULATOR_HOST: `localhost:${FIRESTORE_PORT}`,
  };
  run('node', ['scripts/seedEmulator.js'], {
    cwd: path.join(ROOT, 'functions'),
    env,
    stdio: 'ignore',
  });
  run('node', ['scripts/seed_today.js'], { cwd: ROOT, env, stdio: 'ignore' });
}

function listScenarios() {
  return fs
    .readdirSync(SCENARIOS)
    .filter((f) => f.endsWith('.mjs'))
    .map((f) => f.replace(/\.mjs$/, ''))
    .sort();
}

async function capture(browser, id) {
  const outDir = path.join(WORK, id, 'img');
  const framesDir = path.join(WORK, id, 'frames');
  fs.rmSync(path.join(WORK, id), { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const { default: scenario } = await import(
    pathToFileURL(path.join(SCENARIOS, `${id}.mjs`)).href
  );

  await reseed();
  const context = await browser.newContext({
    viewport: VIEWPORT,
    locale: 'it-IT',
    timezoneId: 'Europe/Rome',
  });
  await context.addInitScript(HIDE_EMULATOR_BANNER);
  const page = await context.newPage();

  // Le richieste verso la produzione vengono BLOCCATE, non solo notate: con
  // una build non agganciata all'emulatore il login partirebbe davvero.
  let leak = null;
  await context.route(
    (url) => PRODUCTION_HOSTS.some((h) => url.host.endsWith(h)),
    (route) => {
      leak ??= route.request().url();
      return route.abort('blockedbyclient');
    },
  );

  const guide = new Guide(page, { id, outDir, framesDir });
  try {
    await guide.open(APP_URL);
    // `db` prepara i dati che il seed non copre; lo stato viene letto
    // dall'app solo dopo il login, quindi le patch possono stare in testa
    // allo scenario.
    await scenario(guide, { url: APP_URL, db: new EmulatorFirestore(FIRESTORE_PORT) });
    if (leak) throw new Error(`L'app ha contattato la produzione: ${leak}`);
  } catch (error) {
    const failure = path.join(WORK, `${id}-errore.png`);
    await page.screenshot({ path: failure }).catch(() => {});
    // Albero di semantica al momento dell'errore: i nomi accessibili veri, da
    // copiare nello scenario.
    const aria = await page.locator('body').ariaSnapshot().catch(() => '');
    fs.writeFileSync(failure.replace(/\.png$/, '.aria.txt'), aria);
    error.message += `\n  screenshot del punto di errore: ${path.relative(ROOT, failure)}`;
    throw error;
  } finally {
    await context.close();
  }

  for (const flow of guide.flows.keys()) {
    run('python3', [
      path.join(HERE, 'compose_anim.py'),
      path.join(framesDir, flow),
      path.join(outDir, `${flow}.webp`),
    ]);
  }
  run('python3', [path.join(HERE, 'compose_anim.py'), '--optimize', outDir]);

  const target = path.join(ASSETS, id);
  fs.rmSync(target, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.cpSync(outDir, target, { recursive: true });
  return fs.readdirSync(target).length;
}

async function main() {
  const available = listScenarios();
  const wanted = process.argv.slice(2);
  const unknown = wanted.filter((id) => !available.includes(id));
  if (unknown.length) {
    console.error(`Scenario sconosciuto: ${unknown.join(', ')}`);
    console.error(`Disponibili: ${available.join(', ')}`);
    process.exit(2);
  }
  const ids = wanted.length ? wanted : available;

  const browser = await chromium.launch();
  const failed = [];
  try {
    for (const id of ids) {
      const started = Date.now();
      process.stdout.write(`▸ ${id} … `);
      try {
        const count = await capture(browser, id);
        console.log(`ok, ${count} immagini (${Math.round((Date.now() - started) / 1000)} s)`);
      } catch (error) {
        console.log('ERRORE');
        console.error(`  ${error.message}`);
        failed.push(id);
      }
    }
  } finally {
    await browser.close();
  }
  if (failed.length) {
    console.error(`\nScenari falliti: ${failed.join(', ')} (immagini precedenti lasciate intatte)`);
    process.exit(1);
  }
}

await main();
