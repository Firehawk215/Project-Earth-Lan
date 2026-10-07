#!/usr/bin/env python3
# Fuegt die C#-Quelldateien zu EINEM Block zusammen (ein Add-Type): using-Zeilen einmal oben, dann der Code.
import sys
def merge(files):
    usings, body = [], []
    for f in files:
        for line in open(f, encoding='utf-8').read().split('\n'):
            if line.startswith('using ') and line.rstrip().endswith(';') and '(' not in line:
                if line.strip() not in usings: usings.append(line.strip())
            else:
                body.append(line.rstrip())
    text = '\n'.join(sorted(usings)) + '\n\n' + '\n'.join(body).strip('\n') + '\n'
    out = []
    blank = 0
    for l in text.split('\n'):
        blank = blank + 1 if l == '' else 0
        if blank <= 1: out.append(l)
    return '\n'.join(out)
if __name__ == '__main__':
    open(sys.argv[1], 'w', encoding='utf-8', newline='\n').write(merge(sys.argv[2:]))
