"""Test di pendenti.py su un repo git temporaneo.

    python3 -m unittest discover -s .claude/skills/aggiorna-documentazione/scripts -p 'test_*.py'
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pendenti.py')


class PendentiTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = self._tmp.name
        self.git('init', '-q', '-b', 'develop')
        self.git('config', 'user.email', 'test@example.com')
        self.git('config', 'user.name', 'Test')
        self.write('docs/guida.md', 'v1')
        self.write('lib/pagina.dart', 'v1')
        self.write('lib/altro.dart', 'v1')
        self.registro({'sha': None, 'data': None})
        self.commit('iniziale')
        self.registro({'sha': self.head(), 'data': '2026-01-01'})
        self.commit('registro')
        self.publish()

    def tearDown(self):
        self._tmp.cleanup()

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout

    def write(self, path, text):
        full = os.path.join(self.repo, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'w') as f:
            f.write(text)

    def registro(self, verificato, cop=None):
        self.write('docs/stato-documentazione.json', json.dumps({
            'copertura': {'radici': ['lib/'], 'ignora': [],
                          'verificato': cop or verificato},
            'documenti': {'guida-test': {'file': 'docs/guida.md',
                                         'sorgenti': ['lib/pagina.dart'],
                                         'verificato': verificato}},
        }))

    def commit(self, msg):
        self.git('add', '-A')
        self.git('commit', '-q', '-m', msg)

    def head(self):
        return self.git('rev-parse', 'HEAD').strip()

    def publish(self):
        self.git('update-ref', 'refs/remotes/origin/develop', 'HEAD')

    def run_script(self, *args):
        r = subprocess.run([sys.executable, SCRIPT, *args], cwd=self.repo,
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def test_allineato_senza_commit_nuovi(self):
        out = self.run_script()
        self.assertIn('Nessun commit dopo la verifica: `guida-test`', out)
        self.assertNotIn('Non coperti', out)

    def test_commit_su_develop_che_tocca_una_sorgente_e_pendente(self):
        self.write('lib/pagina.dart', 'v2')
        self.commit('feat: nuova etichetta')
        self.publish()
        out = self.run_script()
        self.assertIn('## guida-test', out)
        self.assertIn('feat: nuova etichetta', out)

    def test_segnalato_se_il_commit_aggiornava_anche_il_doc(self):
        self.write('lib/pagina.dart', 'v2')
        self.write('docs/guida.md', 'v2')
        self.commit('feat: etichetta e guida')
        self.publish()
        self.assertIn('aggiornava anche il documento', self.run_script())

    def test_commit_del_branch_e_working_tree(self):
        self.git('checkout', '-q', '-b', 'feature')
        self.write('lib/pagina.dart', 'v2')
        self.commit('wip')
        self.write('lib/pagina.dart', 'v3')
        out = self.run_script()
        self.assertIn('Sul branch:', out)
        self.assertIn('- guida-test: `lib/pagina.dart`', out)

    def test_segna_azzera_i_pendenti(self):
        self.write('lib/pagina.dart', 'v2')
        self.commit('feat')
        self.publish()
        self.run_script('--segna', 'guida-test')
        self.commit('segnato')
        self.publish()
        self.assertIn('Nessun commit dopo la verifica: `guida-test`', self.run_script())

    def test_file_fuori_dalle_sorgenti_finisce_fra_i_non_coperti(self):
        self.write('lib/altro.dart', 'v2')
        self.commit('feat: schermata senza guida')
        self.publish()
        out = self.run_script()
        self.assertIn('Non coperti', out)
        self.assertIn('lib/altro.dart', out)
        self.run_script('--segna', 'copertura')
        self.commit('segnato')
        self.publish()
        self.assertNotIn('Non coperti', self.run_script())

    def test_watermark_non_antenato_ripiega_sull_ultimo_commit_del_doc(self):
        self.registro({'sha': 'f' * 40, 'data': '2026-01-01'})
        self.commit('watermark rotto')
        self.publish()
        out = self.run_script()
        self.assertIn("uso l'ultimo commit che ha toccato docs/guida.md", out)

    def test_da_ignora_il_watermark(self):
        primo = self.git('rev-list', '--max-parents=0', 'HEAD').strip()
        self.write('lib/pagina.dart', 'v2')
        self.commit('feat')
        self.publish()
        self.run_script('--segna', 'guida-test')
        self.commit('segnato')
        self.publish()
        self.assertNotIn('## guida-test', self.run_script())
        self.assertIn('## guida-test', self.run_script('--da', primo))

    def test_mostra_il_documento_gia_modificato_sul_branch(self):
        self.write('lib/pagina.dart', 'v2')
        self.commit('feat')
        self.publish()
        self.git('checkout', '-q', '-b', 'feature')
        self.write('docs/guida.md', 'v2')
        self.commit('docs: guida allineata')
        out = self.run_script()
        self.assertIn('già stato modificato su questo branch', out)
        self.assertIn('docs: guida allineata', out)

    def test_segna_su_feature_branch_non_ripropone_i_commit_letti(self):
        self.git('checkout', '-q', '-b', 'feature')
        self.write('lib/pagina.dart', 'v2')
        self.commit('feat sul branch')
        self.run_script('--segna', 'guida-test')
        self.commit('segnato')
        self.assertNotIn('## guida-test', self.run_script())
        self.write('lib/pagina.dart', 'v3')
        self.commit('altro commit')
        out = self.run_script()
        self.assertIn('altro commit', out)
        self.assertNotIn('feat sul branch', out)

    def test_watermark_stimato_segnalato_finche_non_si_segna(self):
        self.registro({'sha': self.head(), 'data': '2026-01-01', 'stimato': True})
        self.commit('stimato')
        self.publish()
        self.assertIn('Watermark stimati', self.run_script())
        self.run_script('--segna', 'guida-test')
        self.assertNotIn('Watermark stimati', self.run_script())

    def test_chiave_sconosciuta(self):
        r = subprocess.run([sys.executable, SCRIPT, '--segna', 'boh'], cwd=self.repo,
                           capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('chiave sconosciuta', r.stderr)


if __name__ == '__main__':
    unittest.main()
