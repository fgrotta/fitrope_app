#!/usr/bin/env python3
"""Server statico per build/web che vieta la cache.

`http.server` risponde con `Last-Modified` e nessun `Cache-Control`, quindi il
browser riusa `main.dart.js` dalla cache. Dopo un rebuild i part file deferred
sono nuovi ma il bundle principale e' vecchio, e l'app muore con
`DeferredLoadException: main.dart.js_N.part.js not loaded`. Sembra un problema
di rete e invece basta un hard reload — meglio togliere il problema.
"""
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):  # meno rumore nel log
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5601
    directory = sys.argv[2] if len(sys.argv) > 2 else "build/web"
    handler = partial(NoCacheHandler, directory=directory)
    ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
