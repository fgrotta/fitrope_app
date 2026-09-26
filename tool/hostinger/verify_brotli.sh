#!/usr/bin/env bash
# Verifica che un server serva correttamente un file precompresso brotli.
#
#   tool/hostinger/verify_brotli.sh https://app.fithousemonza.it main.dart.js
#   tool/hostinger/verify_brotli.sh https://app.fithousemonza.it/brotli-probe main.dart.js
#
# Controlla, per il file indicato:
#   1. con Accept-Encoding: br -> 200, UN solo "Content-Encoding: br", il
#      Content-Type del file originale, "Vary: Accept-Encoding", e un corpo
#      che decompresso è identico all'originale (niente doppia compressione);
#   2. con Accept-Encoding: identity -> nessuna codifica, stesso contenuto;
#   3. con Accept-Encoding: gzip -> niente brotli (il .br va solo a chi lo accetta).
# Con EXPECT_CACHE="max-age=1800" controlla anche che Cache-Control lo contenga
# (le regole di cache devono valere anche per il file .br servito al posto
# dell'originale). Stampa i byte trasferiti. Esce con 1 se un controllo fallisce.
# Richiede curl, brotli e shasum.
set -uo pipefail

BASE="${1:?Uso: $0 <base-url> <file> [content-type atteso]}"
FILE="${2:?Uso: $0 <base-url> <file> [content-type atteso]}"
URL="${BASE%/}/$FILE"
case "$FILE" in
  *.js|*.mjs) DEFAULT_TYPE="application/javascript" ;;
  *.wasm) DEFAULT_TYPE="application/wasm" ;;
  *.json) DEFAULT_TYPE="application/json" ;;
  *.otf) DEFAULT_TYPE="font/otf" ;;
  *.ttf) DEFAULT_TYPE="font/ttf" ;;
  *) DEFAULT_TYPE="" ;;
esac
EXPECT_TYPE="${3:-$DEFAULT_TYPE}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok() { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
ko() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=1; }
hdr() { grep -i "^$1:" "$2" | tr -d '\r' | sed -E "s/^[^:]+:[[:space:]]*//"; }

echo "Verifica brotli: $URL"

# 1. brotli
code=$(curl -s -o "$TMP/br.body" -D "$TMP/br.h" -w '%{http_code}' -H 'Accept-Encoding: br' "$URL")
[ "$code" = 200 ] && ok "HTTP 200 con Accept-Encoding: br" || ko "HTTP $code con Accept-Encoding: br"
enc=$(hdr content-encoding "$TMP/br.h" | tr '\n' ',' | sed 's/,$//')
[ "$enc" = "br" ] && ok "Content-Encoding: br (una volta sola)" || ko "Content-Encoding atteso 'br', ricevuto '${enc:-<nessuno>}'"
ctype=$(hdr content-type "$TMP/br.h" | head -1)
if [ -n "$EXPECT_TYPE" ]; then
  case "$ctype" in
    "$EXPECT_TYPE"*) ok "Content-Type: $ctype" ;;
    *) ko "Content-Type atteso $EXPECT_TYPE, ricevuto '${ctype:-<nessuno>}'" ;;
  esac
fi
vary=$(hdr vary "$TMP/br.h" | tr '\n' ',')
echo "$vary" | grep -qi 'accept-encoding' && ok "Vary contiene Accept-Encoding" || ko "Vary senza Accept-Encoding ('${vary:-<nessuno>}')"
cache=$(hdr cache-control "$TMP/br.h" | head -1)
if [ -n "${EXPECT_CACHE:-}" ]; then
  case "$cache" in
    *"$EXPECT_CACHE"*) ok "Cache-Control: $cache" ;;
    *) ko "Cache-Control atteso con '$EXPECT_CACHE', ricevuto '${cache:-<nessuno>}'" ;;
  esac
else
  echo "       Cache-Control: ${cache:-<nessuno>}"
fi

# 2. originale
code=$(curl -s -o "$TMP/id.body" -D "$TMP/id.h" -w '%{http_code}' -H 'Accept-Encoding: identity' "$URL")
[ "$code" = 200 ] && ok "HTTP 200 senza compressione" || ko "HTTP $code senza compressione"
idenc=$(hdr content-encoding "$TMP/id.h")
[ -z "$idenc" ] && ok "senza compressione: nessun Content-Encoding" || ko "senza compressione: Content-Encoding '$idenc'"

if brotli -d -c "$TMP/br.body" > "$TMP/br.decoded" 2>/dev/null; then
  if cmp -s "$TMP/br.decoded" "$TMP/id.body"; then
    ok "il corpo brotli decompresso è identico all'originale"
  else
    ko "il corpo brotli decompresso NON coincide con l'originale (doppia compressione?)"
  fi
else
  ko "il corpo ricevuto non è brotli valido (doppia compressione o header sbagliato)"
fi

# 3. solo gzip
curl -s -o /dev/null -D "$TMP/gz.h" -H 'Accept-Encoding: gzip' "$URL"
gzenc=$(hdr content-encoding "$TMP/gz.h")
[ "$gzenc" != "br" ] && ok "con solo gzip non arriva brotli (${gzenc:-nessuna codifica})" || ko "con solo gzip arriva comunque brotli"

raw=$(wc -c < "$TMP/id.body" | tr -d ' ')
packed=$(wc -c < "$TMP/br.body" | tr -d ' ')
echo "       byte: originale $raw, brotli $packed ($(( packed * 100 / (raw > 0 ? raw : 1) ))%)"
[ $FAIL = 0 ] && echo "ESITO: OK" || echo "ESITO: FALLITO"
exit $FAIL
