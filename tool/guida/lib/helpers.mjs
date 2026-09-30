// Primitive per pilotare l'app Flutter web e fotografarla.
//
// Flutter disegna su canvas: gli elementi si trovano nell'albero di semantica
// (`flt-semantics`), che l'engine crea solo dopo un click sul placeholder
// nascosto `flt-semantics-placeholder`. Da lì:
// - bottoni, tab, voci di menu → `getByRole('button', { name })`, dove `name`
//   è il testo visibile o il tooltip;
// - campi di testo → click sull'`<input>` di semantica (label = hint del
//   campo), poi `page.keyboard.type`. `locator.fill()` NON funziona: scrive
//   nell'input di semantica, che non è l'editor di Flutter, e il campo resta
//   vuoto.
import fs from 'node:fs';
import path from 'node:path';

// Desktop (≥ 900 px) ma non più largo: nella guida le immagini stanno in
// una colonna di 820 px, e a 1280 le pagine centrate (dettaglio utente)
// finivano rimpicciolite con metà dello spazio bianco ai lati.
export const VIEWPORT = { width: 1024, height: 768 };
export const ADMIN = { email: 'admin@test.it', password: 'test1234' };

// Pausa dopo ogni interazione: le transizioni Material durano ~300 ms, i
// dati arrivano dall'emulatore in qualche centinaio di ms.
const SETTLE_MS = 900;

const HIGHLIGHT_COLOR = '#ff6d00';

export class Guide {
  /**
   * @param {import('playwright').Page} page
   * @param {{ id: string, outDir: string, framesDir: string }} opts
   */
  constructor(page, { id, outDir, framesDir }) {
    this.page = page;
    this.id = id;
    this.outDir = outDir;
    this.framesDir = framesDir;
    this.shots = [];
    this.flows = new Map();
  }

  // ------------------------------------------------------------- semantica

  async semantics() {
    await this.page.evaluate(() => {
      const placeholder = document.querySelector('flt-semantics-placeholder');
      if (placeholder) placeholder.click();
    });
    await this.page.waitForTimeout(200);
  }

  async settle(ms = SETTLE_MS) {
    await this.page.waitForTimeout(ms);
    await this.semantics();
  }

  /** Bottone (o tab, o voce di menu) per testo visibile o tooltip. */
  button(name, { exact = true } = {}) {
    return this.page.getByRole('button', { name, exact }).first();
  }

  /**
   * Voce del rail (desktop) o della bottom bar: il nome accessibile include
   * anche la posizione ("Home Scheda 1 di 4"), quindi niente match esatto.
   */
  tab(name) {
    return this.page
      .getByRole('button', { name: new RegExp(`^${escapeRegex(name)}\\b`) })
      .first();
  }

  /** Nodo di semantica che contiene il testo. */
  text(value, { exact = false } = {}) {
    return this.page
      .locator('flt-semantics')
      .filter({ hasText: exact ? new RegExp(`^${escapeRegex(value)}$`) : value })
      .last();
  }

  /** Campo di testo per hint o label. */
  field(label) {
    // Per ruolo e non `getByLabel`: con un valore dentro, Flutter sposta
    // l'hint nel placeholder e `getByLabel` non trova più il campo.
    return this.page.getByRole('textbox', { name: label, exact: true }).first();
  }

  async waitFor(locator, timeout = 20000) {
    await this.semantics();
    await locator.waitFor({ state: 'visible', timeout });
    return locator;
  }

  /**
   * Il testo è sullo schermo? Flutter lo mette a volte nel contenuto del nodo
   * di semantica, a volte nell'`aria-label` di un gruppo che ne fonde
   * diversi: si guardano entrambi.
   */
  async hasText(value) {
    return this.page.evaluate(
      (v) =>
        [...document.querySelectorAll('flt-semantics, flt-semantics-host *')].some(
          (el) => (el.getAttribute('aria-label') ?? '').includes(v) ||
            (el.childElementCount === 0 && (el.textContent ?? '').includes(v)),
        ),
      value,
    );
  }

  async waitText(value, timeout = 20000) {
    const deadline = Date.now() + timeout;
    for (;;) {
      await this.semantics();
      if (await this.hasText(value)) return;
      if (Date.now() > deadline) {
        throw new Error(`Testo non trovato entro ${timeout} ms: "${value}"`);
      }
      await this.page.waitForTimeout(400);
    }
  }

  async tap(target, opts = {}) {
    const locator = typeof target === 'string' ? this.button(target, opts) : target;
    await this.waitFor(locator);
    await locator.click();
    await this.settle();
  }

  /** Bottone dentro il dialog aperto (es. "Disattiva" di conferma). */
  dialogButton(name) {
    // AlertDialog ha ruolo `alertdialog`, Dialog e date picker `dialog`.
    return this.page
      .getByRole('dialog')
      .or(this.page.getByRole('alertdialog'))
      .getByRole('button', { name, exact: true })
      .last();
  }

  /**
   * Date picker Material: apre [trigger], passa alla digitazione e scrive
   * [date]. Con `before` si può fotografare il calendario aperto.
   */
  async pickDate(trigger, date, { before } = {}) {
    await this.tap(trigger);
    if (before) await before();
    await this.tap('Passa alla modalità di immissione');
    await this.type('Inserisci data', formatShortDate(date));
    await this.tap(this.dialogButton('OK'));
  }

  /** Time picker Material: modalità testo, poi Ora e Minuto. */
  async pickTime(trigger, hour, minute, { before } = {}) {
    await this.tap(trigger);
    if (before) await before();
    await this.tap('Passa alla modalità immissione testo');
    await this.type('Ora', String(hour).padStart(2, '0'));
    await this.type('Minuto', String(minute).padStart(2, '0'));
    await this.tap(this.dialogButton('OK'));
  }

  /**
   * Nel calendario (vista mese) seleziona il giorno [date], passando al mese
   * successivo se serve. I giorni si chiamano "1, giovedì 1 ottobre 2026".
   */
  async selectCalendarDay(date) {
    const long = date.toLocaleDateString('it-IT', {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    });
    const day = this.page.getByRole('button', { name: `${date.getDate()}, ${long}`, exact: true });
    await this.semantics();
    if (!(await day.isVisible())) await this.tap('Mese successivo');
    await this.tap(day);
  }

  /** Riga dell'agenda del giorno per il corso [title]: "07:00 - 08:00 <title> …". */
  agendaRow(title) {
    // `button` se la riga è solo cliccabile, `group` se contiene anche il
    // pulsante di prenotazione (es. "Abbonamento scaduto" per l'Admin).
    const name = new RegExp(`^\\d\\d:\\d\\d - \\d\\d:\\d\\d ${escapeRegex(title)}\\b`);
    return this.page
      .getByRole('button', { name })
      .or(this.page.getByRole('group', { name }))
      .first();
  }

  /** Campo a tendina (DropdownButtonFormField): nome = "<label> <valore>". */
  dropdown(label) {
    return this.page
      .getByRole('button', { name: new RegExp(`^${escapeRegex(label)}( |$)`) })
      .first();
  }

  /** Voce di un menu aperto (tendina, popup). */
  option(name) {
    return this.page
      .getByRole('menuitem', { name, exact: true })
      .or(this.page.getByRole('option', { name, exact: true }))
      .or(this.page.getByRole('button', { name, exact: true }))
      .last();
  }

  /** Apre la tendina [label] e sceglie [value]. */
  async select(label, value, { before } = {}) {
    await this.tap(this.dropdown(label));
    if (before) await before();
    await this.tap(this.option(value));
  }

  /**
   * Scorre la pagina con la rotella, con il puntatore su [at] (default: il
   * centro dell'area contenuti). Flutter web non scorre con scrollIntoView.
   */
  async scroll(dy, at = { x: 700, y: 450 }) {
    await this.page.mouse.move(at.x, at.y);
    await this.page.mouse.wheel(0, dy);
    await this.settle(600);
  }

  /** Scorre finché [locator] non è tutto dentro lo schermo. */
  async reveal(locator) {
    await this.waitFor(locator);
    const { height } = this.page.viewportSize();
    for (let i = 0; i < 10; i++) {
      const box = await locator.boundingBox();
      if (!box) return;
      if (box.y >= 60 && box.y + box.height <= height - 20) return;
      // Porta l'elemento a circa un terzo dello schermo.
      await this.scroll(box.y - height / 3, { x: box.x + box.width / 2, y: height / 2 });
    }
  }

  /**
   * Il pulsante "Esci dalla simulazione" della barra arancione. La barra vive
   * sopra il Navigator e non compare nell'albero di semantica, quindi si
   * trova per posizione: alta 48 px, pulsante a destra (layout ≥ 600 px).
   */
  simulationExit() {
    const { width } = this.page.viewportSize();
    return { x: width - 200, y: 6, width: 188, height: 36 };
  }

  async exitSimulation() {
    const r = this.simulationExit();
    await this.page.mouse.click(r.x + r.width / 2, r.y + r.height / 2);
    await this.settle(1500);
  }

  async check(name) {
    const box = this.page.getByRole('checkbox', { name, exact: true }).first();
    await this.tap(box);
  }

  async type(label, value) {
    const input = typeof label === 'string' ? this.field(label) : label;
    await this.waitFor(input);
    await input.click();
    await this.page.waitForTimeout(250);
    await this.page.keyboard.press('ControlOrMeta+a');
    await this.page.keyboard.press('Backspace');
    if (value) await this.page.keyboard.type(value, { delay: 15 });
    await this.page.waitForTimeout(250);
  }

  // ------------------------------------------------------------- percorsi

  async open(url = this.url) {
    this.url = url;
    await this.page.goto(url);
    await this.page.waitForSelector('flt-semantics-placeholder', {
      state: 'attached',
      timeout: 60000,
    });
    await this.settle();
  }

  /**
   * Entra dal form. Se non si è sulla pagina di benvenuto (dopo un'altra
   * sezione dello scenario) ricarica l'app: la build dell'emulatore azzera la
   * sessione a ogni caricamento, quindi si riparte sempre da "Entra".
   */
  async login({ email, password } = ADMIN) {
    await this.semantics();
    if (!(await this.button('Entra').isVisible())) await this.open();
    await this.tap('Entra');
    await this.type('Inserisci la tua email', email);
    await this.type('Inserisci la tua password', password);
    await this.tap('Login');
    await this.waitFor(this.tab('Home'), 30000);
    await this.settle(1500);
  }

  /**
   * Scrive l'albero di semantica corrente (nomi accessibili veri) accanto
   * agli screenshot di lavoro: serve mentre si scrive uno scenario.
   */
  async dump(label) {
    await this.semantics();
    const aria = await this.page.locator('body').ariaSnapshot();
    const file = path.join(path.dirname(this.outDir), `${label}.aria.txt`);
    fs.writeFileSync(file, aria);
    return file;
  }

  /**
   * Apre la voce [name] del rail, tornando indietro dalle pagine aperte
   * sopra (dettaglio utente, form del corso…) finché il rail non è visibile.
   */
  async goTab(name, timeout = 30000) {
    const deadline = Date.now() + timeout;
    for (;;) {
      await this.semantics();
      if (await this.tab(name).isVisible()) break;
      if (await this.button('Indietro').isVisible()) {
        await this.tap('Indietro');
      } else if (Date.now() > deadline) {
        throw new Error(`Voce "${name}" del menu non trovata entro ${timeout} ms`);
      } else {
        // Subito dopo il login le voci Admin compaiono solo quando il profilo
        // è caricato: con l'emulatore appena avviato può volerci qualche
        // secondo.
        await this.page.waitForTimeout(500);
      }
    }
    await this.tap(this.tab(name));
  }

  /**
   * Scrive nella ricerca della pagina Utenti. Il campo è il primo textbox:
   * una volta riempito, il suo nome accessibile a volte sparisce.
   */
  async searchUsers(query) {
    await this.type(this.page.getByRole('textbox').first(), query);
    await this.settle();
  }

  /** Riga della tabella Utenti che contiene [name]. */
  userRow(name) {
    return this.page.getByRole('row', { name: new RegExp(`^${escapeRegex(name)}\\b`) }).first();
  }

  /** Utenti → cerca [name] → Dettagli della sua riga. */
  async openUser(name) {
    await this.goTab('Utenti');
    await this.searchUsers(name);
    await this.tap(this.userRow(name).getByRole('button', { name: 'Dettagli', exact: true }));
    await this.waitText('Informazioni Personali');
    await this.settle();
  }

  // ------------------------------------------------------------- immagini

  /**
   * Screenshot della pagina, con un riquadro arancione sopra gli elementi da
   * toccare. Il nome diventa `img/<id>/<name>.png`.
   */
  async shot(name, { highlight, clip } = {}) {
    if (!/^\d\d-[a-z0-9-]+$/.test(name)) {
      throw new Error(`Nome screenshot non valido: "${name}" (atteso NN-descrizione)`);
    }
    const file = path.join(this.outDir, `${name}.png`);
    await this.#withHighlight(highlight, () =>
      this.page.screenshot({ path: file, clip }),
    );
    this.shots.push(file);
  }

  /** Un passo di un'animazione: i frame vengono composti in `<flow>.webp`. */
  async frame(flow, { highlight } = {}) {
    if (!/^[a-z0-9-]+$/.test(flow)) throw new Error(`Flusso non valido: "${flow}"`);
    const dir = path.join(this.framesDir, flow);
    fs.mkdirSync(dir, { recursive: true });
    const n = (this.flows.get(flow) ?? 0) + 1;
    this.flows.set(flow, n);
    const file = path.join(dir, `${String(n).padStart(3, '0')}.png`);
    await this.#withHighlight(highlight, () => this.page.screenshot({ path: file }));
  }

  async #withHighlight(highlight, capture) {
    const targets = highlight ? [highlight].flat() : [];
    // Un rettangolo {x, y, width, height} si evidenzia così com'è: serve per
    // ciò che non ha semantica (la barra della simulazione).
    const isRect = (t) => typeof t === 'object' && typeof t.width === 'number' && !('click' in t);
    const locators = targets.map((t) => (typeof t === 'string' ? this.button(t) : t));
    for (const locator of locators) if (!isRect(locator)) await this.reveal(locator);
    // Le misure si prendono dopo TUTTI gli scroll: portare a schermo l'ultimo
    // elemento può aver spostato (o nascosto) i primi.
    const { width, height } = this.page.viewportSize();
    const boxes = [];
    for (const locator of locators) {
      const box = isRect(locator) ? locator : await locator.boundingBox();
      if (!box || box.y < 0 || box.x < 0 || box.y + box.height > height || box.x + box.width > width) {
        throw new Error(`Elemento da evidenziare fuori dallo schermo: ${locator}`);
      }
      boxes.push(box);
    }
    if (boxes.length) {
      await this.page.evaluate(
        ({ boxes, color }) => {
          for (const b of boxes) {
            const el = document.createElement('div');
            el.className = 'guida-highlight';
            const pad = 5;
            // Dentro lo schermo anche per i pulsanti attaccati al bordo.
            const left = Math.max(3, b.x - pad);
            const top = Math.max(3, b.y - pad);
            const right = Math.min(window.innerWidth - 3, b.x + b.width + pad);
            const bottom = Math.min(window.innerHeight - 3, b.y + b.height + pad);
            Object.assign(el.style, {
              position: 'fixed',
              left: `${left}px`,
              top: `${top}px`,
              width: `${right - left}px`,
              height: `${bottom - top}px`,
              border: `3px solid ${color}`,
              borderRadius: '10px',
              // Anello bianco + ombra: il riquadro si vede anche su uno
              // sfondo arancione (la card con il conteggio da correggere).
              boxShadow: '0 0 0 2px #ffffff, 0 0 10px 2px rgba(0, 0, 0, 0.45)',
              pointerEvents: 'none',
              zIndex: '2147483647',
              boxSizing: 'border-box',
            });
            document.body.appendChild(el);
          }
        },
        { boxes, color: HIGHLIGHT_COLOR },
      );
    }
    try {
      await capture();
    } finally {
      await this.page.evaluate(() =>
        document.querySelectorAll('.guida-highlight').forEach((el) => el.remove()),
      );
    }
  }
}

/**
 * Script iniettato in ogni pagina: nasconde il banner "Running in emulator
 * mode" di Firebase Auth, che altrimenti finirebbe in ogni screenshot.
 */
export const HIDE_EMULATOR_BANNER = `
  (() => {
    const css = '.firebase-emulator-warning { display: none !important; }';
    const add = () => {
      const style = document.createElement('style');
      style.textContent = css;
      document.head.appendChild(style);
    };
    if (document.head) add();
    else document.addEventListener('DOMContentLoaded', add);
  })();
`;

/** `dd/MM/yyyy`, come le date mostrate dall'app. */
export function formatDate(date) {
  const dd = String(date.getDate()).padStart(2, '0');
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  return `${dd}/${mm}/${date.getFullYear()}`;
}

/** `g/m/aaaa`, il formato del campo "Inserisci data" del date picker. */
export function formatShortDate(date) {
  return `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()}`;
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
