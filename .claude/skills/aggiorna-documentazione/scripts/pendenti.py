#!/usr/bin/env python3
"""Cosa manca alla documentazione: commit arrivati dopo l'ultima verifica.

    python3 .claude/skills/aggiorna-documentazione/scripts/pendenti.py
    python3 .claude/skills/aggiorna-documentazione/scripts/pendenti.py --segna guida/corsi claude-md
    python3 .claude/skills/aggiorna-documentazione/scripts/pendenti.py --segna copertura
    python3 .claude/skills/aggiorna-documentazione/scripts/pendenti.py --da <ref>   # audit

Il registro è docs/stato-documentazione.json. Ogni documento ha le sue
`sorgenti` (pathspec git: file, cartelle con `/` finale, glob con `*`) e un
watermark `verificato.sha`, un commit di develop. Pendente = un commit fra il
watermark e develop, o del branch corrente, o una modifica nel working tree, che
tocca una sorgente.

`copertura` ha lo stesso watermark per i file sotto `radici` che nessun
documento elenca: sono le feature che nessuna guida segue ancora.

`--segna` sposta il watermark sul merge-base fra HEAD e develop (e ricorda
l'HEAD del branch, per non riproporne i commit già letti): si usa dopo aver
letto i commit pendenti, anche quando il documento era già corretto.
Solo libreria standard.
"""
import argparse
import datetime
import fnmatch
import json
import os
import re
import subprocess
import sys

REGISTRO = 'docs/stato-documentazione.json'
CATALOGO = 'lib/pages/protected/guide/guide_catalog.dart'
SEP = '\x1f'


def git(*args, check=True):
    r = subprocess.run(['git', *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f'git {" ".join(args)}: {r.stderr.strip()}')
    return r.stdout


def corrisponde(path, sorgenti):
    for s in sorgenti:
        if s.endswith('/'):
            if path.startswith(s):
                return True
        elif any(c in s for c in '*?['):
            if fnmatch.fnmatch(path, s):
                return True
        elif path == s or path.startswith(s + '/'):
            return True
    return False


def commit(rng, paths, doc=None):
    """Commit non-merge di `rng` che toccano `paths`, con i file toccati.

    Con `doc`, `con_doc` dice se lo stesso commit ha aggiornato anche il
    documento: probabile, non garantito, che sia già allineato.
    """
    if not paths:
        return []
    if doc:
        trovati = commit(rng, [*paths, doc])
        for c in trovati:
            c['con_doc'] = doc in c['file']
        return [c for c in trovati if c['file'] != [doc]]
    out = git('log', '--no-merges', '--name-only',
              f'--format={SEP}%h{SEP}%cs{SEP}%s', rng, '--', *paths)
    risultato = []
    corrente = None
    for riga in out.splitlines():
        if riga.startswith(SEP):
            _, sha, data, titolo = riga.split(SEP, 3)
            corrente = {'sha': sha, 'data': data, 'titolo': titolo, 'file': []}
            risultato.append(corrente)
        elif riga.strip() and corrente is not None:
            corrente['file'].append(riga.strip())
    return risultato


def antenato(sha, base):
    return subprocess.run(['git', 'merge-base', '--is-ancestor', sha, base],
                          capture_output=True).returncode == 0


def watermark(voce, base, file_doc=None, da=None):
    """(sha, nota). Ripiega sull'ultimo commit di base che ha toccato il doc."""
    if da:
        return git('rev-parse', da).strip(), None
    sha = (voce.get('verificato') or {}).get('sha')
    if sha and git('rev-parse', '--verify', '--quiet', f'{sha}^{{commit}}', check=False).strip() \
            and antenato(sha, base):
        return sha, None
    if file_doc:
        ultimo = git('log', '-1', '--format=%H', base, '--', file_doc).strip()
        if ultimo:
            return ultimo, f'watermark {sha or "assente"} non valido: uso l\'ultimo commit che ha toccato {file_doc}'
    return None, f'watermark {sha or "assente"} non valido'


def range_branch(verificato, base, da=None):
    """Commit del branch ancora da leggere: dopo l'HEAD segnato, se è nella storia."""
    head = verificato.get('head')
    if not da and head and antenato(head, 'HEAD') and not antenato(head, base):
        return f'{head}..HEAD'
    return f'{base}..HEAD'


def working_tree():
    out = git('status', '--porcelain', '--untracked-files=all')
    paths = []
    for riga in out.splitlines():
        p = riga[3:]
        if ' -> ' in p:
            p = p.split(' -> ', 1)[1]
        paths.append(p.strip('"'))
    return paths


def id_catalogo():
    if not os.path.exists(CATALOGO):
        return set()
    with open(CATALOGO, encoding='utf-8') as f:
        return set(re.findall(r"id: '([a-z0-9-]+)'", f.read()))


def stampa_commit(lista, sorgenti=None):
    for c in lista:
        toccati = [f for f in c['file'] if sorgenti is None or corrisponde(f, sorgenti)]
        extra = f'  ({", ".join(toccati[:4])}{" …" if len(toccati) > 4 else ""})' if toccati else ''
        if c.get('con_doc'):
            extra += ' — aggiornava anche il documento'
        print(f'- `{c["sha"]}` {c["data"]} {c["titolo"]}{extra}')


def report(reg, base, da=None):
    branch = git('rev-parse', '--abbrev-ref', 'HEAD').strip()
    wt = working_tree()
    print(f'# Documentazione pendente (base `{base}`, branch `{branch}`)\n')
    if da:
        print(f'> Audit da `{da}`: watermark del registro ignorati.\n')

    aggiornati, non_committati, stimati = [], [], []
    for chiave, voce in reg['documenti'].items():
        sorgenti, doc = voce['sorgenti'], voce['file']
        verificato = voce.get('verificato') or {}
        if verificato.get('stimato') and not da:
            stimati.append(chiave)
        sha, nota = watermark(voce, base, doc, da)
        rng_branch = range_branch(verificato, base, da)
        su_base = commit(f'{sha}..{base}', sorgenti, doc) if sha else []
        su_branch = commit(rng_branch, sorgenti, doc)
        locali = [p for p in wt if corrisponde(p, sorgenti)]
        if locali:
            non_committati.append((chiave, locali))
        if not (su_base or su_branch or nota):
            aggiornati.append(chiave)
            continue
        print(f'## {chiave} — `{doc}`')
        print(f'Verificato il {verificato.get("data", "?")} (`{(sha or "?")[:7]}`).')
        if nota:
            print(f'> {nota}')
        if su_base:
            print(f'\nSu `{base}` dopo la verifica:')
            stampa_commit(su_base, sorgenti)
        if su_branch:
            print('\nSul branch:')
            stampa_commit(su_branch, sorgenti)
        lavoro = [c for c in commit(rng_branch, [doc]) if doc in c['file']]
        if lavoro or doc in wt:
            print('\nIl documento è già stato modificato su questo branch:')
            stampa_commit(lavoro, [doc])
            if doc in wt:
                print('- modifiche non committate nel working tree')
        print()

    cop = reg['copertura']
    tutte = [s for v in reg['documenti'].values() for s in v['sorgenti']] + cop.get('ignora', [])
    sha, nota = watermark(cop, base, da=da)
    scoperti = []
    for rng in ([f'{sha}..{base}'] if sha else []) + [f'{base}..HEAD']:
        for c in commit(rng, cop['radici']):
            c['file'] = [f for f in c['file']
                         if corrisponde(f, cop['radici']) and not corrisponde(f, tutte)]
            if c['file']:
                scoperti.append(c)
    locali = [p for p in wt if corrisponde(p, cop['radici']) and not corrisponde(p, tutte)]
    if scoperti or locali or nota:
        print('## Non coperti da nessun documento')
        print('File sotto le radici che nessuna `sorgente` elenca: feature forse non '
              'documentate. Decidi e poi `--segna copertura`.')
        if nota:
            print(f'> {nota}')
        stampa_commit(scoperti)
        if locali:
            print('\nNel working tree: ' + ', '.join(f'`{p}`' for p in locali))
        print()

    ids = id_catalogo()
    registrate = {k.split('/', 1)[1] for k in reg['documenti'] if k.startswith('guida/')}
    if ids - registrate or registrate - ids:
        print('## Registro e catalogo non coincidono')
        for i in sorted(ids - registrate):
            print(f'- guida `{i}` nel catalogo ma non nel registro: aggiungi `guida/{i}`')
        for i in sorted(registrate - ids):
            print(f'- `guida/{i}` nel registro ma non nel catalogo')
        print()

    if non_committati:
        print('## Sorgenti con modifiche non committate')
        print('Solo informativo: rilancia dopo il commit per vederle fra i pendenti.')
        for chiave, locali in non_committati:
            print(f'- {chiave}: ' + ', '.join(f'`{p}`' for p in locali))
        print()

    if aggiornati:
        print('Nessun commit dopo la verifica: ' + ', '.join(f'`{k}`' for k in aggiornati))
    if stimati:
        print('\nWatermark stimati dall\'ultima modifica del file, mai verificati davvero '
              '(la deriva precedente si vede solo con `--da`): '
              + ', '.join(f'`{k}`' for k in stimati))


def segna(reg, base, chiavi):
    sha = git('merge-base', 'HEAD', base).strip()
    head = git('rev-parse', 'HEAD').strip()
    oggi = datetime.date.today().isoformat()
    for k in chiavi:
        voce = reg['copertura'] if k == 'copertura' else reg['documenti'].get(k)
        if voce is None:
            sys.exit(f'chiave sconosciuta: {k} (vedi {REGISTRO})')
        voce['verificato'] = {'sha': sha, 'data': oggi}
        if head != sha:
            # Commit del branch già letti: dopo il merge ricompaiono su develop
            # (lo squash crea un commit nuovo) e si risegnano.
            voce['verificato']['head'] = head
    with open(REGISTRO, 'w', encoding='utf-8') as f:
        json.dump(reg, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f'Segnati su {sha[:7]} ({oggi}): {", ".join(chiavi)}')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--base', default='origin/develop')
    ap.add_argument('--segna', nargs='+', metavar='CHIAVE')
    ap.add_argument('--da', metavar='REF',
                    help='audit: ignora i watermark e parti da REF per tutti')
    a = ap.parse_args()
    os.chdir(git('rev-parse', '--show-toplevel').strip())
    with open(REGISTRO, encoding='utf-8') as f:
        reg = json.load(f)
    if a.segna:
        segna(reg, a.base, a.segna)
    else:
        report(reg, a.base, a.da)


if __name__ == '__main__':
    main()
