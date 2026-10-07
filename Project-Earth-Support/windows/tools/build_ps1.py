#!/usr/bin/env python3
# Baut Project-Earth-Support.ps1 aus den Teilen: PowerShell-Abschnitte + ein C#-Block + Woerterbuch.
# Ausgabe: UTF-8 mit BOM, CRLF. Prueft nebenbei Kopiersicherheit und Vollstaendigkeit des Woerterbuchs.
import re, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from merge_cs import merge
W = os.path.join(os.path.dirname(__file__), '..', 'win')
src = lambda *p: os.path.join(W, 'src', *p)
cs = merge([src('PesCoreHead.cs'), src('PesEngine.cs'), src('PesSession.cs'), src('PesWin.cs')])
assert "\n'@" not in cs
parts = [open(src('ps', n), encoding='utf-8').read() for n in ('10_kopf.ps1', '20_helfer.ps1', '30_gui.ps1', '40_fenster.ps1', '50_start.ps1')]
ps = ''.join(parts)

# ---- Woerterbuch ----
dict_lines = [l for l in open(src('ps', 'dict_en.tsv'), encoding='utf-8').read().split('\n') if l.strip() and not l.startswith('#')]
d = {}
for l in dict_lines:
    assert l.count('\t') == 1, 'Woerterbuchzeile ohne genau einen Tab: %r' % l
    de, en = l.split('\t')
    assert de not in d, 'doppelt: %r' % de
    d[de] = en
    assert sorted(re.findall(r'\{\d\}', de)) == sorted(re.findall(r'\{\d\}', en)), 'Platzhalter verschieden: %r' % l

# Alle deutschen Texte im PowerShell-Teil einsammeln: T '...', -Text '...', Reg(x, '...'), Text = '...' in Tabellen
found = set()
for m in re.finditer(r"\bT\s+'((?:[^']|'')*)'", ps): found.add(m.group(1).replace("''", "'"))
for m in re.finditer(r"-(?:Text|ExitText)\s+'((?:[^']|'')+)'", ps): found.add(m.group(1).replace("''", "'"))
for m in re.finditer(r"\[PesI18n\]::Reg\(\$\w+,\s*'((?:[^']|'')+)'\)", ps): found.add(m.group(1).replace("''", "'"))
for m in re.finditer(r"@\{\s*Text\s*=\s*'((?:[^']|'')+)'", ps): found.add(m.group(1).replace("''", "'"))
for m in re.finditer(r"foreach \(\$q in @\(([^)]*)\)\)", ps):
    for x in re.findall(r"'([^']+)'", m.group(1)): found.add(x)
found.discard('')
skip = {'OK', 'English', 'Deutsch', 'Project Earth Support ...'}
prefixes = [k[:-1] for k in d if k.endswith('*')]
missing = sorted(x for x in found if x not in d and x not in skip and not any(x.startswith(p) for p in prefixes))
unused = sorted(k for k in d if k not in found and not k.endswith('*') and not k.startswith('~'))
if missing:
    print('FEHLENDE Uebersetzungen (%d):' % len(missing))
    for x in missing: print('  ' + x)
dict_text = '\n'.join('%s\t%s' % (k.lstrip('~'), v) for k, v in d.items())
assert "\n'@" not in dict_text

ps = ps.replace('#@@CSHARP@@', cs.rstrip('\n'))
ps = ps.replace('#@@DICTDE@@', open(src('ps', 'dict_de.tsv'), encoding='utf-8').read().strip('\n'))
ps = ps.replace('#@@DICT@@', dict_text)
assert '#@@' not in ps

# ---- Kopiersicherheit ----
bad = {0x201c: 'typogr. Anfuehrungszeichen', 0x201d: 'typogr. Anfuehrungszeichen', 0x201e: 'typogr. Anfuehrungszeichen', 0x2018: 'typogr. Apostroph',
       0x2019: 'typogr. Apostroph', 0x2013: 'Halbgeviertstrich', 0x2014: 'Geviertstrich', 0x00a0: 'geschuetztes Leerzeichen', 0x200b: 'unsichtbares Leerzeichen', 0xfeff: 'BOM mitten in Datei'}
problems = 0
for n, line in enumerate(ps.split('\n'), 1):
    for c, name in bad.items():
        if chr(c) in line: print('Zeile %d: %s' % (n, name)); problems += 1
    if line.rstrip().endswith('`'): print('Zeile %d: Backtick-Zeilenfortsetzung' % n); problems += 1
    if '`' in line: print('Zeile %d: Backtick: %s' % (n, line.strip()[:90])); problems += 1
out = os.path.join(W, 'out', 'Project-Earth-Support.ps1')
data = ps.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8')
open(out, 'wb').write(b'\xef\xbb\xbf' + data)
print('geschrieben: %s (%d Zeilen, %d KB), Woerterbuch %d Eintraege, ungenutzt %d, Kopierprobleme %d' % (out, ps.count('\n') + 1, len(data) // 1024, len(d), len(unused), problems))
if unused and '-v' in sys.argv:
    for x in unused: print('  ungenutzt: ' + x)
sys.exit(1 if (missing or problems) else 0)
