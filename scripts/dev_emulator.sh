#!/usr/bin/env bash
# Porta l'app su un emulatore pronto al login, in un comando.
#
# Nasce da un giro fatto a mano troppe volte: ogni passaggio qui sotto
# corrisponde a un inciampo reale, annotato accanto.
#
#   ./scripts/dev_emulator.sh            # tutto: emulatore, seed, build, server
#   ./scripts/dev_emulator.sh --no-build # solo emulatore + seed
#   ./scripts/dev_emulator.sh --serve    # solo riservi build/web (dopo un rebuild)
#
# Nei modi che avviano il server, apri l'URL stampato in fondo. Con
# AUTOLOGIN_EMAIL valorizzata l'app entra da sola e non serve toccare il form.
set -euo pipefail

PROJECT="fit-rope-app-1f575"      # OBBLIGATORIO: senza, l'Auth emulator segrega
                                  # gli account su demo-no-project e il login
                                  # fallisce con "Email o password sbagliati"
PORT="${PORT:-5601}"
JAVA_BIN="/usr/local/opt/openjdk@21/bin"   # keg-only: va anteposto al PATH
AUTOLOGIN_EMAIL="${AUTOLOGIN_EMAIL:-abbonato@test.it}"
AUTOLOGIN_PASSWORD="${AUTOLOGIN_PASSWORD:-test1234}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DO_EMU=1; DO_SEED=1; DO_BUILD=1; DO_SERVE=1
case "${1:-}" in
  --no-build) DO_BUILD=0; DO_SERVE=0 ;;
  --serve)    DO_EMU=0; DO_SEED=0; DO_BUILD=0 ;;
  "") ;;
  *) echo "Uso: $0 [--no-build|--serve]"; exit 2 ;;
esac

say() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }

port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

# ---------------------------------------------------------------- emulatore
if [ "$DO_EMU" = 1 ]; then
  if port_busy 9099; then
    say "Emulatore gia' in ascolto su 9099, lo riuso"
  else
    say "Avvio Emulator Suite ($PROJECT)"
    # Le functions vanno compilate prima, altrimenti l'emulatore carica il JS
    # vecchio (o niente) e le callable rispondono 'not-found'.
    (cd functions && npm run build >/dev/null)
    PATH="$JAVA_BIN:$PATH" nohup firebase emulators:start --project "$PROJECT" \
      > /tmp/fitrope-emu.log 2>&1 < /dev/null &
    disown
    until grep -qE "All emulators ready|Error" /tmp/fitrope-emu.log; do sleep 2; done
    grep -q "All emulators ready" /tmp/fitrope-emu.log \
      || { echo "Emulatore non partito, vedi /tmp/fitrope-emu.log"; exit 1; }
  fi
fi

# --------------------------------------------------------------------- seed
if [ "$DO_SEED" = 1 ]; then
  say "Seed dati sintetici"
  (cd functions && npm run seed:emulator >/dev/null)

  # Il seed mette i corsi nella settimana SUCCESSIVA: il calendario si apre su
  # oggi e sembra vuoto, come se il seed fosse fallito. Qui ne aggiungo una
  # giornata su oggi, con stati diversi per avere qualcosa da guardare.
  say "Corsi di oggi ($(date +%Y-%m-%d))"
  node scripts/seed_today.js
fi

# -------------------------------------------------------------------- build
if [ "$DO_BUILD" = 1 ]; then
  say "Build web release (USE_EMULATOR=true)"
  # --release e non debug: il build DDC di debug carica ~700 moduli uno a uno e
  # in pratica non arriva a bootare in una tab pilotata.
  flutter build web --release \
    --dart-define=USE_EMULATOR=true \
    --dart-define=EMULATOR_AUTOLOGIN_EMAIL="$AUTOLOGIN_EMAIL" \
    --dart-define=EMULATOR_AUTOLOGIN_PASSWORD="$AUTOLOGIN_PASSWORD" \
    >/tmp/fitrope-build.log 2>&1 \
    || { tail -20 /tmp/fitrope-build.log; exit 1; }
fi

# ------------------------------------------------------------------- server
if [ "$DO_SERVE" = 1 ]; then
  # `flutter build web` ricrea build/web da zero: un server avviato prima resta
  # agganciato a una directory cancellata e risponde 404 su tutto.
  pkill -f "dev_server.py $PORT" 2>/dev/null || true
  sleep 1
  say "Servo build/web su :$PORT"
  # Server con no-store: senza, il browser riusa main.dart.js dalla cache e
  # dopo un rebuild i part file deferred non combaciano
  # (DeferredLoadException). Tutti i descrittori rediretti, altrimenti una pipe
  # a valle (`| tail`) non vede mai EOF e lo script sembra appeso.
  nohup python3 scripts/dev_server.py "$PORT" build/web \
      > /tmp/fitrope-http.log 2>&1 < /dev/null &
  disown
  sleep 2
  curl -sf -o /dev/null "http://localhost:$PORT/index.html" \
    || { echo "Il server non risponde"; exit 1; }
fi

if [ "$DO_SERVE" = 1 ]; then
  cat <<EOF

  Pronto:  http://localhost:$PORT/index.html?t=$(date +%s)
           (la query serve solo a bucare la cache del browser)

  Autologin: $AUTOLOGIN_EMAIL
  Emulator UI: http://localhost:4000

  PRIMA di fidarti, in console:
    performance.getEntriesByType('resource').map(r => new URL(r.name).host)
  Se compare identitytoolkit/securetoken .googleapis.com sei su PRODUZIONE.
  Se vedi solo localhost, sei sull'emulatore.

EOF
else
  cat <<EOF

  Emulator Suite e seed pronti. Nessun build o server avviato (--no-build).
  Per servire una build/web esistente:
    ./scripts/dev_emulator.sh --serve

  Emulator UI: http://localhost:4000

EOF
fi
