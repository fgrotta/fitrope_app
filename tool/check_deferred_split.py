#!/usr/bin/env python3
"""Verifica che il codice solo admin resti fuori dal percorso di un socio.

Uso: python3 tool/check_deferred_split.py build/web

Legge da main.dart.js la mappa dart2js libreria deferred -> part
(`deferredLibraryParts` / `deferredPartUris`) e controlla che ogni marcatore
admin (una stringa di UI che esiste solo in quella libreria):
  - non compaia in main.dart.js;
  - non compaia nei part che carica `protected` (cioè ogni utente loggato);
  - compaia in almeno un part (se sparisce, il marcatore va aggiornato: un
    gate che non trova niente passerebbe per sempre).

Serve la build dart2js (`flutter build web --release`). Una build --wasm
produce ANCHE main.dart.js con i suoi part (fallback per i browser non
Chromium), ma su Chromium carica main.dart.wasm, che contiene tutto il codice
admin: per questo la sola presenza di main.dart.wasm fa fallire il gate.
"""
import json
import os
import re
import sys

# libreria deferred -> stringa di UI che esiste solo lì.
MARKERS = {
    'admin_users': 'Nascondi filtri',
    'admin_dashboard': 'Tasso di riempimento medio',
    'user_list_drawer': 'Nessun utente da esportare',
    'admin_home': 'Caricamento certificati in scadenza',
}


def main(build_dir):
    if os.path.exists(os.path.join(build_dir, 'main.dart.wasm')):
        sys.exit('Build --wasm: su Chromium main.dart.wasm contiene tutto il codice '
                 'admin. Builda con `flutter build web --release`.')
    main_js_path = os.path.join(build_dir, 'main.dart.js')
    if not os.path.exists(main_js_path):
        sys.exit(f'Manca {main_js_path}: serve la build dart2js, non --wasm.')
    main_js = open(main_js_path, encoding='utf-8').read()
    uris_match = re.search(r'deferredPartUris:\[([^\]]*)\]', main_js)
    libs_match = re.search(r'deferredLibraryParts:\{([^}]*)\}', main_js)
    if not uris_match or not libs_match:
        sys.exit('Mappa dei part non trovata in main.dart.js (build senza deferred?).')
    uris = json.loads('[' + uris_match.group(1) + ']')
    libs = {
        m.group(1): [int(x) for x in m.group(2).split(',') if x]
        for m in re.finditer(r'"?([\w.]+)"?:\[([\d,]*)\]', libs_match.group(1))
    }
    # dart2js può dare lo stesso prefisso a più import (es. "protected" e
    # "protected.1"): il percorso di un socio è l'unione di tutti.
    protected_keys = [k for k in libs if k == 'protected' or k.startswith('protected.')]
    if not protected_keys:
        sys.exit('Libreria deferred "protected" non trovata nella mappa.')

    def read(uri):
        return open(os.path.join(build_dir, uri), encoding='utf-8').read()

    protected_parts = {uris[i] for k in protected_keys for i in libs[k]}
    if not protected_parts:
        sys.exit('I part di "protected" risultano vuoti: mappa non riconosciuta.')
    errors = []
    for lib, marker in MARKERS.items():
        if lib not in libs:
            errors.append(f'{lib}: non è più una libreria deferred.')
            continue
        if marker in main_js:
            errors.append(f'{lib}: "{marker}" è in main.dart.js.')
        leaked = sorted(u for u in protected_parts if marker in read(u))
        if leaked:
            errors.append(f'{lib}: "{marker}" è nei part di protected: {leaked}.')
        if not any(marker in read(uris[i]) for i in libs[lib]):
            errors.append(f'{lib}: "{marker}" non compare nei suoi part: aggiorna MARKERS.')
    if errors:
        print('Split deferred non valido:')
        for e in errors:
            print(f'  - {e}')
        sys.exit(1)
    print(f'Split deferred ok: {len(MARKERS)} librerie admin fuori dal percorso socio.')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/web')
