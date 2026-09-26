#!/usr/bin/env python3
"""Prepara una cartella di prova da caricare su Hostinger PRIMA del deploy vero.

    flutter build web --release
    python3 tool/precompress_web.py build/web
    python3 tool/hostinger/make_brotli_probe.py build/web /tmp/brotli-probe

Poi caricare il CONTENUTO di /tmp/brotli-probe in una cartella del sito, per
esempio public_html/brotli-probe/, e verificare con:

    tool/hostinger/verify_brotli.sh https://app.fithousemonza.it/brotli-probe main.dart.js

La cartella contiene la stessa .htaccess della build e main.dart.js con il suo
.br: se lì tutto passa, le regole funzionano anche su LiteSpeed; se falliscono,
il sito vero non viene toccato. A prova finita la cartella va cancellata.
"""
import os
import shutil
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build, out = sys.argv[1], sys.argv[2]
    needed = ['.htaccess', 'main.dart.js', 'main.dart.js.br']
    missing = [n for n in needed if not os.path.exists(os.path.join(build, n))]
    if missing:
        sys.exit(f'Mancano in {build}: {", ".join(missing)} (hai lanciato tool/precompress_web.py?)')
    os.makedirs(out, exist_ok=True)
    for n in needed:
        shutil.copy2(os.path.join(build, n), os.path.join(out, n))
    with open(os.path.join(out, 'LEGGIMI.txt'), 'w') as f:
        f.write('Cartella di prova brotli: si può cancellare dopo la verifica.\n'
                'Verifica: tool/hostinger/verify_brotli.sh <url-di-questa-cartella> main.dart.js\n')
    print(f'Cartella di prova pronta in {out}: caricala su Hostinger e lancia verify_brotli.sh.')


if __name__ == '__main__':
    main()
