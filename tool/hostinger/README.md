# Hostinger: brotli precompresso

La brotli dinamica di LiteSpeed (Hostinger) comprime bene i file piccoli (livello 6) ma crolla
su quelli grandi, come se comprimesse a blocchi indipendenti da ~2 KB: il `main.dart.js` di
produzione (4,9 MB) arrivava a 1,65 MB, più del gzip dello stesso server (1,35 MB) e quasi il
doppio di una brotli livello 11 (0,90 MB). La soluzione è caricare i file già compressi.

| File | A cosa serve |
|---|---|
| `../precompress_web.py` | crea i `.br` (livello 11) accanto ai file della build |
| `../../web/.htaccess` | serve il `.br` a chi accetta brotli, con Content-Type e Vary giusti |
| `htaccess.backup` | la `.htaccess` precedente (solo cache): per tornare indietro |
| `verify_brotli.sh` | controlla con `curl` un file servito da un server qualsiasi |
| `make_brotli_probe.py` | prepara una cartella di prova da caricare su Hostinger |
| `local_apache_test.sh` | prova la `.htaccess` su un Apache locale (anche in CI) |
| `test_precompress_web.py` | test dello script e della coerenza con la `.htaccess` |

## Deploy in produzione

```bash
flutter build web --release
python3 tool/precompress_web.py build/web          # crea i .br
python3 tool/precompress_web.py build/web --check  # facoltativo: riverifica
# upload di build/web (con i .br e la .htaccess) su Hostinger
tool/hostinger/verify_brotli.sh https://app.fithousemonza.it main.dart.js
```

`verify_brotli.sh` deve chiudere con `ESITO: OK`: un solo `Content-Encoding: br`,
`Content-Type: application/javascript`, `Vary: Accept-Encoding`, corpo decompresso identico
all'originale, niente brotli per chi chiede solo gzip.

## Prima volta: prova isolata

LiteSpeed legge la sintassi Apache ma non è Apache. Prima del primo deploy con i `.br`:

```bash
flutter build web --release && python3 tool/precompress_web.py build/web
python3 tool/hostinger/make_brotli_probe.py build/web /tmp/brotli-probe
# caricare il CONTENUTO di /tmp/brotli-probe in public_html/brotli-probe/
tool/hostinger/verify_brotli.sh https://app.fithousemonza.it/brotli-probe main.dart.js
# poi cancellare public_html/brotli-probe/
```

La cartella ha la sua `.htaccess`, quindi il sito vero non viene toccato. Esiti possibili:

- **OK**: si può fare il deploy completo.
- **"il corpo ricevuto non è brotli valido"**: LiteSpeed ricomprime il `.br` (doppia codifica).
  Non fare il deploy con questa `.htaccess`; ripiego: rimettere `htaccess.backup`.
- **Content-Encoding assente**: la regola di rewrite non scatta (mod_rewrite o la condizione su
  `Accept-Encoding`): il sito funziona come prima, senza guadagno.

## Tornare indietro

Ricopiare `tool/hostinger/htaccess.backup` in `web/.htaccess` (oppure caricarla direttamente
come `public_html/.htaccess`). I file `.br` rimasti sul server sono inerti senza la regola.
