#!/usr/bin/env python3
"""Applica il branding "TEST" a una build web gia' compilata.

Serve a riconoscere a colpo d'occhio le PWA non di produzione installate sui
dispositivi: icona con banda arancione e nome "Fit House TEST" sotto l'icona.

    python3 tool/apply_test_branding.py build/web

Perche' post-build e non un --dart-define: `manifest.json` e `index.html` sono
file statici copiati tali e quali dal build, i define di Dart non li vedono.
Lo script e' idempotente (rilanciarlo sulla stessa directory non cambia nulla)
e usa solo la standard library, cosi' gira in CI senza dipendenze. Le icone
sorgente stanno in `tool/test_icons/`, generate da `tool/make_test_icons.py`.

La build di produzione non chiama questo script: l'assenza e' il default.
"""

import hashlib
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_ICONS = os.path.join(ROOT, "tool", "test_icons")

APP_NAME = "Fit House TEST"

# sorgente in tool/test_icons/ -> destinazione dentro la build
ICONS = [
    ("Icon-192.png", "icons/Icon-192.png"),
    ("Icon-512.png", "icons/Icon-512.png"),
    ("Icon-maskable-192.png", "icons/Icon-maskable-192.png"),
    ("Icon-maskable-512.png", "icons/Icon-maskable-512.png"),
    ("favicon.png", "favicon.png"),
    ("favicon.ico", "favicon.ico"),
]


def stamp():
    """Cache-buster derivato dal contenuto delle icone di test.

    Le icone mantengono il nome di produzione, quindi senza cambiare il
    query-param una PWA staging gia' installata continuerebbe a mostrare la
    vecchia icona presa dalla cache. Legandolo all'hash, lo stamp cambia solo
    quando cambiano davvero le icone e lo script resta idempotente.
    """
    digest = hashlib.sha1()
    for name, _ in ICONS:
        with open(os.path.join(SRC_ICONS, name), "rb") as handle:
            digest.update(handle.read())
    return "test-" + digest.hexdigest()[:8]


def copy_icons(build_dir):
    for name, dest in ICONS:
        src = os.path.join(SRC_ICONS, name)
        dst = os.path.join(build_dir, dest)
        if not os.path.exists(dst):
            sys.exit("Atteso ma non trovato nella build: " + dest)
        shutil.copyfile(src, dst)


def rewrite(path, replacements):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    for pattern, repl in replacements:
        text = re.sub(pattern, repl, text)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def main():
    if len(sys.argv) != 2:
        sys.exit("Uso: tool/apply_test_branding.py <build-dir>")
    build_dir = sys.argv[1]
    manifest = os.path.join(build_dir, "manifest.json")
    index = os.path.join(build_dir, "index.html")
    for path in (manifest, index):
        if not os.path.isfile(path):
            sys.exit("Non sembra una build web: manca " + path)

    version = stamp()
    copy_icons(build_dir)

    # Il nome di produzione compare in name/short_name del manifest e nei meta
    # di index.html; `?v=` sta sui riferimenti a icone e manifest.
    bump = (r'\?v=[^"\'\s>]+', "?v=" + version)
    rewrite(
        manifest,
        [
            (r'("(?:short_name|name)"\s*:\s*)"[^"]*"', r'\1"%s"' % APP_NAME),
            bump,
        ],
    )
    rewrite(
        index,
        [
            (r'(<meta name="title" content=)"[^"]*"', r'\1"%s"' % APP_NAME),
            (
                r'(<meta name="apple-mobile-web-app-title" content=)"[^"]*"',
                r'\1"%s"' % APP_NAME,
            ),
            (r"<title>[^<]*</title>", "<title>%s</title>" % APP_NAME),
            bump,
        ],
    )
    print("Branding TEST applicato a %s (stamp %s)" % (build_dir, version))


if __name__ == "__main__":
    main()
