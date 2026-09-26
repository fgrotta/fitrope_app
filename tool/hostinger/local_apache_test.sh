#!/usr/bin/env bash
# Prova web/.htaccess su un Apache locale, prima di caricarla su Hostinger.
#
#   flutter build web --release && python3 tool/precompress_web.py build/web
#   tool/hostinger/local_apache_test.sh build/web
#
# Avvia Apache su 127.0.0.1:${PORT:-8799} con la build come DocumentRoot e
# AllowOverride All (come Hostinger), più la cartella di prova in /brotli-probe/,
# e lancia verify_brotli.sh sui file principali. LiteSpeed legge la sintassi
# Apache ma non è Apache: questo test prende gli errori di sintassi e di logica
# (un .htaccess rotto su Hostinger dà errore 500 su tutto il sito); il
# comportamento di LiteSpeed si verifica con la cartella di prova
# (make_brotli_probe.py).
#
# HOLD_SECONDS=300 tiene Apache acceso dopo i controlli, per aprire l'app in
# un browser su http://127.0.0.1:${PORT:-8799}/.
set -euo pipefail
trap 'echo "local_apache_test.sh: errore alla riga $LINENO (comando: $BASH_COMMAND)" >&2' ERR

BUILD="$(cd "${1:?Uso: $0 <build-dir>}" && pwd)"
PORT="${PORT:-8799}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTTPD="${HTTPD:-$(command -v httpd || command -v apache2 || true)}"
[ -n "$HTTPD" ] || { echo "Apache non trovato (macOS: brew install httpd o /usr/sbin/httpd; Ubuntu: apt-get install apache2)"; exit 2; }
# Su Debian/Ubuntu `apache2 -V` esce con errore se mancano le variabili di
# /etc/apache2/envvars, pur stampando le informazioni: niente pipefail qui.
INFO="$("$HTTPD" -V 2>/dev/null || true)"
ROOT="$(printf '%s\n' "$INFO" | sed -n 's/.*HTTPD_ROOT="\(.*\)"/\1/p')"
CONFFILE="$(printf '%s\n' "$INFO" | sed -n 's/.*SERVER_CONFIG_FILE="\(.*\)"/\1/p')"
CONFDIR="$(dirname "${CONFFILE:-.}")"
for d in "$ROOT/lib/httpd/modules" "$ROOT/libexec/apache2" "$ROOT/modules" /usr/lib/apache2/modules /usr/lib64/httpd/modules; do
  [ -f "$d/mod_rewrite.so" ] && MODS="$d" && break
done
[ -n "${MODS:-}" ] || { echo "Moduli Apache non trovati per $HTTPD"; exit 2; }
for m in "$ROOT/$CONFDIR/mime.types" "$CONFDIR/mime.types" /usr/local/etc/httpd/mime.types /etc/apache2/mime.types /private/etc/apache2/mime.types /etc/mime.types; do
  [ -f "$m" ] && MIME="$m" && break
done
# I moduli già compilati nel binario (httpd -l) non vanno ricaricati.
STATIC="$("$HTTPD" -l 2>/dev/null || true)"
echo "Apache: $HTTPD · moduli: $MODS · mime: ${MIME:-<nessuno>}"
load() { echo "$STATIC" | grep -q "mod_$1.c\|^ *$1.c" || echo "LoadModule ${1}_module $MODS/mod_$1.so"; }

TMP="$(mktemp -d)"
cleanup() { [ -f "$TMP/httpd.pid" ] && kill "$(cat "$TMP/httpd.pid")" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/www"
cp -R "$BUILD/." "$TMP/www/"
python3 "$HERE/make_brotli_probe.py" "$BUILD" "$TMP/www/brotli-probe" >/dev/null

cat > "$TMP/httpd.conf" <<CONF
ServerRoot "$TMP"
Listen 127.0.0.1:$PORT
ServerName localhost
PidFile "$TMP/httpd.pid"
ErrorLog "$TMP/error.log"
DefaultRuntimeDir "$TMP"
Mutex file:$TMP default
$(echo "$STATIC" | grep -q "prefork.c" || echo "LoadModule mpm_prefork_module $MODS/mod_mpm_prefork.so")
$(load unixd)
$(load authz_core)
$(load dir)
$(load mime)
$(load rewrite)
$(load headers)
$(load env)
TypesConfig "$MIME"
DocumentRoot "$TMP/www"
DirectoryIndex index.html
<Directory "$TMP/www">
  AllowOverride All
  Require all granted
</Directory>
CONF

"$HTTPD" -t -f "$TMP/httpd.conf"
"$HTTPD" -f "$TMP/httpd.conf" -k start
for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

BASE="http://127.0.0.1:$PORT"
FAIL=0
run() { "$HERE/verify_brotli.sh" "$@" || FAIL=1; }
EXPECT_CACHE="max-age=1800" run "$BASE" main.dart.js
part="$(cd "$TMP/www" && ls main.dart.js_*.part.js 2>/dev/null | head -1 || true)"
[ -n "$part" ] && EXPECT_CACHE="max-age=1800" run "$BASE" "$part"
# Build --wasm: il modulo wasm deve arrivare con Content-Type application/wasm,
# altrimenti WebAssembly.instantiateStreaming lo rifiuta.
[ -f "$TMP/www/main.dart.wasm.br" ] && run "$BASE" main.dart.wasm
[ -f "$TMP/www/main.dart.mjs.br" ] && run "$BASE" main.dart.mjs
[ -f "$TMP/www/assets/AssetManifest.bin.json.br" ] && run "$BASE" assets/AssetManifest.bin.json
[ -f "$TMP/www/assets/fonts/MaterialIcons-Regular.otf.br" ] && run "$BASE" assets/fonts/MaterialIcons-Regular.otf
EXPECT_CACHE="max-age=1800" run "$BASE/brotli-probe" main.dart.js
# index.html resta servito normalmente
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")
[ "$code" = 200 ] && echo "  OK   / risponde 200" || { echo "  FAIL / risponde $code"; FAIL=1; }
if grep -qiE "error|alert" "$TMP/error.log"; then
  echo "error.log di Apache:"; cat "$TMP/error.log"; FAIL=1
fi
[ $FAIL = 0 ] && echo "APACHE LOCALE: TUTTO OK" || echo "APACHE LOCALE: FALLITO"
if [ -n "${HOLD_SECONDS:-}" ]; then
  echo "Apache resta acceso ${HOLD_SECONDS}s su $BASE/"
  sleep "$HOLD_SECONDS"
fi
exit $FAIL
