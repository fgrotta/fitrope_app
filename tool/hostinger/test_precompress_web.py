"""Test di tool/precompress_web.py e della coerenza con web/.htaccess.

    python3 -m unittest discover -s tool/hostinger -p 'test_*.py'

Richiede il comando `brotli` nel PATH (come lo script).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SCRIPT = os.path.join(ROOT, 'tool', 'precompress_web.py')
sys.path.insert(0, os.path.join(ROOT, 'tool'))
import precompress_web  # noqa: E402


def run(*args):
    return subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)


def read(path, mode='rb'):
    with open(path, mode) as f:
        return f.read()


def decompress(path):
    return subprocess.run(['brotli', '-d', '-c', path], capture_output=True, check=True).stdout


class PrecompressTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.js = os.path.join(self.dir, 'main.dart.js')
        with open(self.js, 'w') as f:
            f.write('function a(){return "fit house";}\n' * 2000)
        os.makedirs(os.path.join(self.dir, 'assets'))
        self.bin = os.path.join(self.dir, 'assets', 'AssetManifest.bin')
        with open(self.bin, 'wb') as f:
            f.write(b'asset-manifest ' * 400)
        self.small = os.path.join(self.dir, 'version.json')
        with open(self.small, 'w') as f:
            f.write('{"version":"1.3.0"}')
        self.png = os.path.join(self.dir, 'logo.png')
        with open(self.png, 'wb') as f:
            f.write(b'\x89PNG' + b'x' * 5000)

    def tearDown(self):
        shutil.rmtree(self.dir)

    def test_comprime_i_file_serviti_e_verifica_il_contenuto(self):
        res = run(self.dir)
        self.assertEqual(res.returncode, 0, res.stderr)
        for path in (self.js, self.bin):
            self.assertTrue(os.path.exists(path + '.br'), path)
            self.assertEqual(decompress(path + '.br'), read(path))
            self.assertLess(os.path.getsize(path + '.br'), os.path.getsize(path))

    def test_salta_file_piccoli_e_formati_gia_compressi(self):
        run(self.dir)
        self.assertFalse(os.path.exists(self.small + '.br'))
        self.assertFalse(os.path.exists(self.png + '.br'))

    def test_rigenera_un_br_non_aggiornato(self):
        run(self.dir)
        with open(self.js, 'a') as f:
            f.write('var nuovo = 1;\n')
        res = run(self.dir)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(decompress(self.js + '.br'), read(self.js))

    def test_check_fallisce_se_un_br_non_corrisponde(self):
        run(self.dir)
        with open(self.js, 'a') as f:
            f.write('var modificato = 1;\n')
        res = run(self.dir, '--check')
        self.assertNotEqual(res.returncode, 0)
        self.assertIn('main.dart.js', res.stdout + res.stderr)

    def test_check_passa_dopo_la_compressione(self):
        run(self.dir)
        res = run(self.dir, '--check')
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_salta_la_copia_locale_del_motore(self):
        # canvaskit/ è solo una riserva: il motore arriva da www.gstatic.com.
        ck = os.path.join(self.dir, 'canvaskit')
        os.makedirs(ck)
        with open(os.path.join(ck, 'canvaskit.js'), 'w') as f:
            f.write('var ck = 1;\n' * 500)
        run(self.dir)
        self.assertFalse(os.path.exists(os.path.join(ck, 'canvaskit.js.br')))

    def test_directory_inesistente(self):
        res = run(os.path.join(self.dir, 'manca'))
        self.assertNotEqual(res.returncode, 0)


class HtaccessCoherenceTest(unittest.TestCase):
    def test_htaccess_riscrive_esattamente_le_estensioni_compresse(self):
        htaccess = read(os.path.join(ROOT, 'web', '.htaccess'), 'r')
        m = re.search(r'RewriteRule \^\(\.\+\\\.\(([a-z|]+)\)\)\$', htaccess)
        self.assertIsNotNone(m, 'RewriteRule dei .br non trovata in web/.htaccess')
        self.assertEqual(set(m.group(1).split('|')), set(precompress_web.EXTENSIONS))

    def test_ogni_estensione_compressa_ha_il_suo_content_type(self):
        htaccess = read(os.path.join(ROOT, 'web', '.htaccess'), 'r')
        for ext in precompress_web.EXTENSIONS:
            self.assertRegex(htaccess, r'FilesMatch "[^"]*\b' + ext + r'\b[^"]*\\\.br\$"',
                             f'manca il blocco Content-Type per .{ext}.br')


if __name__ == '__main__':
    unittest.main()
