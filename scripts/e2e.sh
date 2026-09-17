#!/usr/bin/env bash
# E2E Flutter contro Emulator Suite oppure staging. Non accetta production.
set -euo pipefail

# firebase-tools 15 richiede Java 21. Preferiamo l'installazione Homebrew
# locale quando quello della sessione non punta già a Java 21.
java_bin="${JAVA_HOME:-}/bin/java"
if [[ ! -x "$java_bin" || "$("$java_bin" -version 2>&1 | head -1)" != *'21.'* ]]; then
  for candidate in /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
                   /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home; do
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi
java_bin="${JAVA_HOME:-}/bin/java"
[[ -x "$java_bin" && "$("$java_bin" -version 2>&1 | head -1)" == *'21.'* ]] || {
  echo "Java 21 non disponibile: imposta JAVA_HOME su un JDK 21." >&2
  exit 1
}

target="${1:-}"
if [[ "$target" != "emulator" && "$target" != "staging" ]]; then
  echo "Usage: scripts/e2e.sh <emulator|staging>" >&2
  exit 2
fi

manifest="integration_test/e2e_manifest.json"
cleanup() {
  (cd functions && E2E_PROJECT_ID="$E2E_PROJECT_ID" APP_ENV="${APP_ENV:-}" npm run e2e:cleanup -- --manifest "../$manifest") || true
  [[ -n "${CHROMEDRIVER_PID:-}" ]] && kill "$CHROMEDRIVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$target" == "emulator" ]]; then
  export E2E_PROJECT_ID="${E2E_PROJECT_ID:-demo-fitrope}"
  export FIRESTORE_EMULATOR_HOST="127.0.0.1:18080"
  export FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:19099"
  export APP_ENV="emulator"
  export FUNCTIONS_EMULATOR=true
  (cd functions && npm run build)
  firebase emulators:start --config firebase.e2e.json --only auth,firestore,functions --project "$E2E_PROJECT_ID" > .context/e2e-emulator.log 2>&1 &
  EMULATOR_PID=$!
  trap 'kill "$EMULATOR_PID" 2>/dev/null || true; cleanup' EXIT
  until curl -fsS http://127.0.0.1:14000 >/dev/null; do sleep 1; done
  defines=(--dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=127.0.0.1 --dart-define=EMULATOR_PROJECT_ID="$E2E_PROJECT_ID" --dart-define=AUTH_EMULATOR_PORT=19099 --dart-define=FIRESTORE_EMULATOR_PORT=18080 --dart-define=FUNCTIONS_EMULATOR_PORT=15001)
else
  : "${E2E_PROJECT_ID:?E2E_PROJECT_ID staging richiesto}"
  [[ "$E2E_PROJECT_ID" == *staging* ]] || { echo "E2E_PROJECT_ID deve essere staging" >&2; exit 2; }
  export APP_ENV=staging
  defines=(--dart-define=APP_ENV=staging)
fi

(cd functions && npm run e2e:setup -- --manifest "../$manifest")
chromedriver --port=4444 > .context/e2e-chromedriver.log 2>&1 & CHROMEDRIVER_PID=$!
# ChromeDriver può impiegare alcuni secondi ad aprire la porta, soprattutto
# quando Chrome è stato appena aggiornato. Aspettiamo il suo endpoint di
# stato prima di invocare Flutter, evitando AppConnectionException dovute a
# una semplice race di avvio.
driver_ready=false
for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:4444/status >/dev/null 2>&1; then
    driver_ready=true
    break
  fi
  sleep 1
done
if [[ "$driver_ready" != true ]]; then
  echo "ChromeDriver non disponibile sulla porta 4444" >&2
  exit 1
fi
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/e2e_test.dart -d chrome \
  --dart-define-from-file="${manifest%.json}.defines.json" "${defines[@]}"
(cd functions && npm run e2e:assert -- --manifest "../$manifest")
