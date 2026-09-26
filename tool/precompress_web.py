#!/usr/bin/env python3
"""Crea accanto ai file della build web le versioni precompresse brotli (.br).

Uso (dopo `flutter build web --release`, prima dell'upload su Hostinger):

    python3 tool/precompress_web.py build/web          # crea/aggiorna i .br
    python3 tool/precompress_web.py build/web --check  # verifica soltanto

Perché: la brotli dinamica di LiteSpeed su Hostinger comprime bene i file
piccoli (livello 6) ma crolla su quelli grandi, come se comprimesse a blocchi
indipendenti da ~2 KB. Il main.dart.js di produzione (4,9 MB) arrivava a
1,65 MB, più del gzip dello stesso server. Con i .br precompressi a livello 11
e le regole in web/.htaccess il server spedisce i byte già pronti.

Gli originali restano accanto ai .br per i client che non accettano brotli.
Le estensioni in EXTENSIONS devono coincidere con la RewriteRule di
web/.htaccess (lo verifica tool/hostinger/test_precompress_web.py).
Richiede il comando `brotli` (macOS: brew install brotli; Ubuntu: apt-get
install brotli).
"""
import argparse
import os
import shutil
import subprocess
import sys

# Solo formati testuali o binari non già compressi. Niente .html: index.html è
# piccolo (LiteSpeed lo comprime bene) e arriva spesso come "/" via
# DirectoryIndex, che la RewriteRule non vede. Niente png/jpg/woff2: già
# compressi.
EXTENSIONS = ('js', 'mjs', 'wasm', 'json', 'otf', 'ttf', 'bin')
# Sotto questa soglia il guadagno è trascurabile e LiteSpeed se la cava già.
MIN_SIZE = 1024
QUALITY = '11'
# canvaskit/ contiene copie locali del motore usate solo come riserva (il loader
# lo scarica da www.gstatic.com): comprimerle aggiungerebbe ~9 MB all'upload.
SKIP_DIRS = ('canvaskit',)


def candidates(root):
    for dirpath, dirs, files in os.walk(root):
        if dirpath == root:
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in sorted(files):
            ext = name.rsplit('.', 1)[-1] if '.' in name else ''
            if ext not in EXTENSIONS:
                continue
            path = os.path.join(dirpath, name)
            if os.path.getsize(path) < MIN_SIZE:
                continue
            yield path


def decompressed(br_path):
    return subprocess.run(['brotli', '-d', '-c', br_path], capture_output=True, check=True).stdout


def compress(path):
    subprocess.run(['brotli', '-q', QUALITY, '-f', '-o', path + '.br', path], check=True)
    with open(path, 'rb') as f:
        if decompressed(path + '.br') != f.read():
            raise RuntimeError(f'{path}.br non decomprime nell\'originale')


def check(path):
    br = path + '.br'
    if not os.path.exists(br):
        return 'manca il .br'
    with open(path, 'rb') as f:
        if decompressed(br) != f.read():
            return 'il .br non corrisponde all\'originale'
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('build_dir')
    parser.add_argument('--check', action='store_true', help='verifica i .br senza rigenerarli')
    args = parser.parse_args()

    if not os.path.isdir(args.build_dir):
        sys.exit(f'Directory non trovata: {args.build_dir}')
    if shutil.which('brotli') is None:
        sys.exit('Comando `brotli` non trovato (macOS: brew install brotli; Ubuntu: apt-get install brotli).')

    files = list(candidates(args.build_dir))
    if not files:
        sys.exit(f'Nessun file da comprimere in {args.build_dir}: è una build web?')

    if args.check:
        problems = [(p, err) for p in files if (err := check(p))]
        for p, err in problems:
            print(f'  {os.path.relpath(p, args.build_dir)}: {err}')
        if problems:
            sys.exit(f'{len(problems)} file senza .br valido: rilancia senza --check.')
        print(f'{len(files)} file .br verificati.')
        return

    raw = packed = 0
    for path in files:
        compress(path)
        raw += os.path.getsize(path)
        packed += os.path.getsize(path + '.br')
    print(f'{len(files)} file compressi con brotli {QUALITY}: '
          f'{raw / 1e6:.2f} MB -> {packed / 1e6:.2f} MB')
    main_js = os.path.join(args.build_dir, 'main.dart.js')
    if os.path.exists(main_js + '.br'):
        print(f'main.dart.js: {os.path.getsize(main_js) / 1e6:.2f} MB -> '
              f'{os.path.getsize(main_js + ".br") / 1e6:.2f} MB')


if __name__ == '__main__':
    main()
