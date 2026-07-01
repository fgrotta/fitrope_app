#!/usr/bin/env bash
#
# Build web di FitRope con cache-busting.
#
# Esegue il build web di produzione e "timbra" la versione in due punti:
#   - build/web/version.json      -> letto a runtime dal check di aggiornamento
#   - build/web/index.html        -> sostituisce il placeholder __APP_BUILD_VERSION__
#
# In questo modo una PWA con shell vecchia in cache rileva il mismatch di
# versione e si auto-aggiorna (vedi la logica in web/index.html).
#
# Uso:
#   bash tool/build_web.sh                 # base-href = /fitrope_app/
#   bash tool/build_web.sh /altro-base/    # base-href custom
#
set -euo pipefail

BASE_HREF="${1:-/fitrope_app/}"

flutter build web --release --base-href "$BASE_HREF"

# Id build = short SHA del commit corrente (cambia ad ogni rilascio).
BUILD_ID="$(git rev-parse --short HEAD)"

printf '{"build_number":"%s"}\n' "$BUILD_ID" > build/web/version.json

# perl -pi: portabile tra macOS (BSD sed) e Linux.
perl -pi -e "s/__APP_BUILD_VERSION__/$BUILD_ID/g" build/web/index.html

echo "Build web completata — build id: $BUILD_ID (base-href: $BASE_HREF)"
