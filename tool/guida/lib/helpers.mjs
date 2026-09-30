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

export const VIEWPORT = { width: 1280, height: 800 };
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
    return this.page.getByLabel(label, { exact: true }).first();
  }

  async waitFor(locator, timeout = 20000) {
    await this.semantics();
    await locator.waitFor({ state: 'visible', timeout });
    return locator;
  }

  async waitText(value, timeout = 20000) {
    const deadline = Date.now() + timeout;
    for (;;) {
      await this.semantics();
      if (await this.text(value).count()) return;
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

  async type(label, value) {
    const input = typeof label === 'string' ? this.field(label) : label;
    await this.waitFor(input);
    await input.click();
    await this.page.waitForTimeout(250);
    await this.page.keyboard.press('ControlOrMeta+a');
    await this.page.keyboard.type(value, { delay: 15 });
    await this.page.waitForTimeout(250);
  }

  // ------------------------------------------------------------- percorsi

  async open(url) {
    await this.page.goto(url);
    await this.page.waitForSelector('flt-semantics-placeholder', {
      state: 'attached',
      timeout: 60000,
    });
    await this.settle();
  }

  async login({ email, password } = ADMIN) {
    await this.tap('Entra');
    await this.type('Inserisci la tua email', email);
    await this.type('Inserisci la tua password', password);
    await this.tap('Login');
    await this.waitFor(this.tab('Home'), 30000);
    await this.settle(1500);
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
    const boxes = [];
    for (const target of targets) {
      const locator = typeof target === 'string' ? this.button(target) : target;
      await this.waitFor(locator);
      const box = await locator.boundingBox();
      if (!box) throw new Error(`Elemento da evidenziare senza bounding box: ${locator}`);
      boxes.push(box);
    }
    if (boxes.length) {
      await this.page.evaluate(
        ({ boxes, color }) => {
          for (const b of boxes) {
            const el = document.createElement('div');
            el.className = 'guida-highlight';
            const pad = 5;
            Object.assign(el.style, {
              position: 'fixed',
              left: `${b.x - pad}px`,
              top: `${b.y - pad}px`,
              width: `${b.width + pad * 2}px`,
              height: `${b.height + pad * 2}px`,
              border: `3px solid ${color}`,
              borderRadius: '10px',
              boxShadow: `0 0 0 4px ${color}33`,
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

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
