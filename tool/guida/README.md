# Guida Admin: cattura di screenshot e animazioni

La Guida Admin è una wiki dentro l'app, visibile solo agli Admin: icona **?** nel rail (desktop) o nell'header della Home (mobile), route `/guida`. I testi sono in `assets/guida/<id>.md`, le immagini in `assets/guida/img/<id>/`, il catalogo in `lib/pages/protected/guide/guide_catalog.dart`. Questa cartella rigenera le immagini dall'app vera, contro l'emulatore e i dati sintetici del seed.

## Rigenerare

```bash
./scripts/guida_screenshots.sh                  # tutte le guide (~12 min, build compresa)
./scripts/guida_screenshots.sh abbonamenti      # solo quelle indicate
KEEP=1 ./scripts/guida_screenshots.sh corsi     # lascia su emulatore e server
KEEP=1 NO_BUILD=1 ./scripts/guida_screenshots.sh corsi   # riusa build/guida_web
```

Lo script:

1. installa le dipendenze mancanti, cioè `npm ci` in `functions/` e qui, più il Chromium di Playwright;
2. avvia un emulatore **dedicato** su porte alte (auth 29099, firestore 28080, functions 25001) con una config temporanea `firebase.guida.json`. Riusa solo un emulatore avviato dallo stesso worktree: se le porte sono di un altro, si ferma. Il `.secret.local` è **sempre** fittizio, così nessuna email o WhatsApp parte davvero. Un eventuale file dello sviluppatore viene messo da parte in `.secret.guida-backup.local` e rimesso a posto alla fine;
3. compila la web in `build/guida_web`, contro quelle porte e **senza autologin**;
4. la serve su `:5621`;
5. lancia `capture.mjs`.

Richiede Java 21 (`/usr/local/opt/openjdk@21/bin`, oppure `JAVA_BIN=…`), Node ≥ 20 e Pillow (`python3 -m pip install Pillow`).

Ogni scenario riparte da un emulatore **azzerato e riseminato** (`seedEmulator.js` + `seed_today.js`), quindi gli scenari sono indipendenti e rilanciabili. Le immagini vengono scritte in `build/guida_capture/<id>/` e sostituiscono `assets/guida/img/<id>/` solo se lo scenario finisce senza errori. Le date cambiano a ogni run, perché il seed è relativo a oggi: il diff degli asset serve a vedere cosa è cambiato, non a confrontare pixel.

Le richieste verso gli host di produzione (`identitytoolkit`, `firestore.googleapis.com`, …) vengono **bloccate**, e lo scenario fallisce: negli screenshot finiscono solo dati sintetici.

## Scrivere uno scenario

`scenarios/<id>.mjs` esporta `async function (g, { db, url })`. `g` è un `Guide` (`lib/helpers.mjs`), `db` scrive sull'emulatore Firestore (`lib/firestore.mjs`) per preparare i casi che il seed non copre.

```js
export default async function (g, { db }) {
  await db.patch('users/mensile-test', { fineIscrizione: daysFromNow(20, 23) });
  await g.login();                          // admin@test.it
  await g.openUser('Mario Mensile');
  await g.shot('01-dettaglio', { highlight: 'Modifica profilo' });  // → img/<id>/01-dettaglio.png
  await g.frame('flusso', { highlight: 'Modifica profilo' });      // → img/<id>/flusso.webp
}
```

- `shot(name)` vuole il formato `NN-descrizione`. `highlight` accetta un testo (bottone), un locator, un array o un rettangolo `{x, y, width, height}`. Gli elementi evidenziati vengono portati a schermo da soli.
- `frame(flow)` aggiunge un passo all'animazione. `compose_anim.py` compone i frame in un WebP in loop (1,6 s per passo) e riduce i PNG a 256 colori.
- In caso di errore restano `build/guida_capture/<id>-errore.png` e `<id>-errore.aria.txt`, l'albero di semantica con i **nomi accessibili veri** da copiare nello scenario. `g.dump('etichetta')` scrive lo stesso albero in qualunque punto.

### Trappole di Flutter web (tutte già gestite negli helper)

- La semantica si accende con un click su `flt-semantics-placeholder`. `g.semantics()` lo fa prima di ogni ricerca.
- **`locator.fill()` non funziona**: scrive nell'input di semantica, non nell'editor di Flutter. Serve click sul campo e poi `keyboard.type` (`g.type`).
- Un campo già compilato può perdere il nome accessibile: la ricerca Utenti si trova come primo textbox (`g.searchUsers`).
- Le voci del rail si chiamano "Home Scheda 1 di 4": si usa `g.tab('Home')`.
- `AlertDialog` ha ruolo `alertdialog`, `Dialog` e date picker `dialog`: `g.dialogButton` li copre entrambi.
- Il testo fuso in un gruppo sta nell'`aria-label`, non nel `textContent`: `g.waitText` guarda entrambi.
- Una riga dell'agenda con il pulsante di prenotazione è un `group`, non un `button` (`g.agendaRow`).
- La barra arancione della simulazione **non è nell'albero di semantica**: si clicca a coordinate (`g.exitSimulation`).
- Date e ore: `g.pickDate` e `g.pickTime` passano alla digitazione ("Inserisci data", "Ora" / "Minuto").
- Lo scroll si fa con la rotella (`g.scroll`, `g.reveal`): `scrollIntoView` non muove Flutter.
- Due elementi con la stessa scadenza non hanno un ordine stabile: rendi deterministico lo stato con `db.patch` invece di contare su `nth()`.

## Aggiornare la guida

La regola completa è nella sezione "Guida Admin" di `CLAUDE.md`. In breve: chi cambia una schermata, un'etichetta o una regola descritta in una guida aggiorna il `.md` e rilancia lo scenario. `grep -rl "<etichetta>" assets/guida tool/guida/scenarios` trova le guide coinvolte.
