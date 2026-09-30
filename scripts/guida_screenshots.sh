#!/usr/bin/env bash
# Rigenera screenshot e animazioni della Guida Admin (assets/guida/img/), in
# un comando. Dettagli in tool/guida/README.md.
#
#   ./scripts/guida_screenshots.sh                 # tutte le guide
#   ./scripts/guida_screenshots.sh abbonamenti     # solo quelle indicate
#   KEEP=1 ./scripts/guida_screenshots.sh …        # lascia su emulatore e server
#   NO_BUILD=1 ./scripts/guida_screenshots.sh …    # riusa build/guida_web
#
# Usa un emulatore TUTTO SUO, su porte alte: ogni scenario azzera e risemina i
# dati, e farlo sull'emulatore condiviso (9099/8080) cancellerebbe il lavoro
# di chi lo sta usando da un altro worktree.
set -euo pipefail

PROJECT="fit-rope-app-1f575"   # lo stesso di seed e firebase_options: l'Auth
                               # emulator segrega gli account per progetto
AUTH_PORT=29099
FIRESTORE_PORT=28080
FUNCTIONS_PORT=25001
HTTP_PORT="${HTTP_PORT:-5621}"
JAVA_BIN="${JAVA_BIN:-/usr/local/opt/openjdk@21/bin}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/firebase.guida.json"
BUILD_DIR="build/guida_web"
LOG_DIR="$ROOT/build/guida_capture"
cd "$ROOT"
mkdir -p "$LOG_DIR"

say() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }
port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

SECRET=functions/.secret.local
# Copia del .secret.local dello sviluppatore mentre gira quello fittizio.
# Finisce in *.local, quindi è gitignored come l'originale.
SECRET_BACKUP=functions/.secret.guida-backup.local
FAKE_MARKER=guida-fittizia
HTTP_PID=""
STARTED_EMU=0
cleanup() {
  if [ "${KEEP:-0}" != 1 ]; then
    [ -n "$HTTP_PID" ] && kill "$HTTP_PID" 2>/dev/null || true
    [ "$STARTED_EMU" = 1 ] && pkill -f "emulators:start --config $CONFIG" 2>/dev/null || true
    # Rimette il .secret.local dello sviluppatore (o nessuno, se non c'era).
    if grep -q "$FAKE_MARKER" "$SECRET" 2>/dev/null; then
      if [ -f "$SECRET_BACKUP" ]; then mv "$SECRET_BACKUP" "$SECRET"; else rm -f "$SECRET"; fi
    fi
    rm -f "$CONFIG"
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------- dipendenze
if [ ! -d functions/node_modules ]; then
  say "npm ci in functions/"
  (cd functions && npm ci >/dev/null)
fi
if [ ! -d tool/guida/node_modules ]; then
  say "npm ci in tool/guida/ + Chromium di Playwright"
  (cd tool/guida && npm ci >/dev/null && npx playwright install chromium >/dev/null)
fi
python3 -c "import PIL" 2>/dev/null \
  || { echo "Serve Pillow: python3 -m pip install Pillow"; exit 1; }

# -------------------------------------------------------------- emulatore
if pgrep -f "emulators:start --config $CONFIG" >/dev/null \
    && port_busy "$AUTH_PORT" && port_busy "$FIRESTORE_PORT"; then
  say "Emulatore della guida di questo worktree gia' in ascolto, lo riuso"
elif port_busy "$AUTH_PORT" || port_busy "$FIRESTORE_PORT" || port_busy "$FUNCTIONS_PORT"; then
  # Le porte sono le stesse in ogni worktree: un emulatore che non è nostro
  # gira il codice functions di un altro branch, e il reseed di ogni scenario
  # gli cancellerebbe i dati a metà lavoro.
  echo "Porte $AUTH_PORT/$FIRESTORE_PORT/$FUNCTIONS_PORT occupate da un emulatore che non e' di questo worktree."
  echo "Probabilmente un'altra cattura della guida (KEEP=1) in un altro worktree: fermala prima."
  exit 1
else
  say "Avvio Emulator Suite dedicata ($AUTH_PORT/$FIRESTORE_PORT/$FUNCTIONS_PORT)"
  python3 - "$CONFIG" "$AUTH_PORT" "$FIRESTORE_PORT" "$FUNCTIONS_PORT" <<'EOF'
import json, sys
out, auth, firestore, functions = sys.argv[1], *map(int, sys.argv[2:])
config = json.load(open("firebase.json"))
emu = config["emulators"]
emu["auth"]["port"] = auth
emu["firestore"]["port"] = firestore
emu["firestore"]["websocketPort"] = firestore + 1
emu["functions"]["port"] = functions
emu["ui"] = {"enabled": False}
emu["hub"] = {"port": 24400}
emu["logging"] = {"port": 24500}
json.dump(config, open(out, "w"), indent=2)
EOF
  # Con --project di produzione, senza .secret.local l'emulatore leggerebbe i
  # secret VERI da Secret Manager. Valori fittizi: nessuna email o WhatsApp
  # parte davvero durante la cattura.
  # Sempre fittizi, anche se lo sviluppatore ne ha uno con chiavi vere: il suo
  # file viene messo da parte e rimesso a posto alla fine.
  if [ -f "$SECRET" ] && ! grep -q "$FAKE_MARKER" "$SECRET"; then
    mv "$SECRET" "$SECRET_BACKUP"
  fi
  printf 'ONESIGNAL_REST_API_KEY=%s\nMAKE_WEBHOOK_URL=http://127.0.0.1:9/guida\nMAKE_WEBHOOK_KEY=%s\n' \
    "$FAKE_MARKER" "$FAKE_MARKER" > "$SECRET"
  (cd functions && npm run build >/dev/null)
  STARTED_EMU=1
  PATH="$JAVA_BIN:$PATH" nohup firebase emulators:start --config "$CONFIG" \
    --only auth,firestore,functions --project "$PROJECT" \
    > "$LOG_DIR/emulatore.log" 2>&1 < /dev/null &
  disown
  for _ in $(seq 1 90); do   # al massimo 3 minuti
    grep -qE "All emulators ready|Error:" "$LOG_DIR/emulatore.log" && break
    sleep 2
  done
  grep -q "All emulators ready" "$LOG_DIR/emulatore.log" \
    || { tail -20 "$LOG_DIR/emulatore.log"; exit 1; }
fi

# ------------------------------------------------------------------ build
if [ "${NO_BUILD:-0}" = 1 ] && [ -f "$BUILD_DIR/index.html" ]; then
  say "Riuso $BUILD_DIR"
else
  say "Build web release contro l'emulatore della guida"
  # Senza autologin: gli scenari entrano dal form, e la guida alla
  # registrazione deve poter fotografare le pagine di benvenuto.
  flutter build web --release -o "$BUILD_DIR" \
    --dart-define=USE_EMULATOR=true \
    --dart-define=AUTH_EMULATOR_PORT="$AUTH_PORT" \
    --dart-define=FIRESTORE_EMULATOR_PORT="$FIRESTORE_PORT" \
    --dart-define=FUNCTIONS_EMULATOR_PORT="$FUNCTIONS_PORT" \
    > "$LOG_DIR/build.log" 2>&1 \
    || { tail -20 "$LOG_DIR/build.log"; exit 1; }
fi

# ----------------------------------------------------------------- server
# Si ferma solo un server lasciato da una cattura precedente di QUESTO
# worktree (stessa directory di lavoro): quello di un altro worktree resta.
OLD_HTTP=$(lsof -tiTCP:"$HTTP_PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true)
if [ -n "$OLD_HTTP" ] \
    && [ "$(lsof -a -p "$OLD_HTTP" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" = "$ROOT" ]; then
  kill "$OLD_HTTP" 2>/dev/null || true
  sleep 1
fi
if port_busy "$HTTP_PORT"; then
  echo "Porta $HTTP_PORT occupata da un altro processo: rilancia con HTTP_PORT=<porta libera>."
  exit 1
fi
nohup python3 scripts/dev_server.py "$HTTP_PORT" "$BUILD_DIR" \
  > "$LOG_DIR/http.log" 2>&1 < /dev/null &
HTTP_PID=$!
disown
sleep 2
curl -sf -o /dev/null "http://localhost:$HTTP_PORT/index.html" \
  || { echo "Il server non risponde su :$HTTP_PORT"; exit 1; }

# ---------------------------------------------------------------- cattura
say "Cattura"
GUIDA_URL="http://localhost:$HTTP_PORT/index.html" \
GUIDA_AUTH_PORT="$AUTH_PORT" GUIDA_FIRESTORE_PORT="$FIRESTORE_PORT" \
  node tool/guida/capture.mjs "$@"

say "Fatto. Controlla il diff di assets/guida/img/ prima del commit."
