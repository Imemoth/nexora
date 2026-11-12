#!/usr/bin/env python3
"""Documentation consistency check (stdlib only). Exit 1 on any finding.

Checks: (1) relative markdown links resolve; (2) repo paths written in backticks under docs/ exist
(only when they start with a known top-level directory and contain a file extension, no wildcards or
placeholders); (3) the status register lists exactly the migration files in supabase/migrations;
(4) banned stale phrases are absent outside files that quote them as history; (5) every docs/ markdown
file is listed in docs/README.md."""
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DOCS = os.path.join(ROOT, 'docs')
problems = []

def md_files():
    for d, _, fs in os.walk(DOCS):
        for f in fs:
            if f.endswith('.md'):
                yield os.path.join(d, f)

TOP = ('lib/', 'test/', 'supabase/', 'docs/', 'tools/', '.github/')
for path in md_files():
    text = open(path, encoding='utf-8').read()
    rel = os.path.relpath(path, ROOT)
    # (1) markdown links
    for m in re.finditer(r'\]\(([^)#\s]+)(#[^)]*)?\)', text):
        target = m.group(1)
        if re.match(r'[a-z]+:', target):
            continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(path), target))):
            problems.append(f'{rel}: broken link {target}')
    # (2) backticked repo paths
    for m in ([] if '/superpowers/plans/' in path.replace(os.sep, '/') else re.finditer(r'`([^`\s]+)`', text)):
        p = m.group(1).rstrip('.,;:')
        if p.startswith(TOP) and re.search(r'\.[a-z0-9]+$', p) and not re.search(r'[*<>{}|]|\.\.\.|…', p):
            p = p.split('#')[0]
            if not os.path.exists(os.path.join(ROOT, p)):
                # allow files explicitly described as hosted-only or not in repo
                ctx = text[max(0, m.start() - 120): m.end() + 120]
                if not re.search(r'not (stored )?(in|on) the repo|hosted-only|does not exist|not on `main`', ctx):
                    problems.append(f'{rel}: path does not exist: {p}')

# (3) migration table
reg = open(os.path.join(DOCS, 'coordination', 'status-register.md'), encoding='utf-8').read()
for f in sorted(os.listdir(os.path.join(ROOT, 'supabase', 'migrations'))):
    if f.endswith('.sql') and f'supabase/migrations/{f}' not in reg:
        problems.append(f'status-register: migration file not listed: {f}')

# (4) banned stale phrases (checked everywhere except the register/README/check script, which quote them)
BANNED = [
    (r'S1 is not applied', 'stale: S1 is applied to hosted'),
    (r'PR #13 \(Draft\)', 'stale: PR #13 is merged'),
    (r'No implementation has started', 'stale: Phase 2A is implemented'),
    (r'IMPLEMENTED LOCALLY, NOT APPLIED', 'stale: only S2 is unapplied'),
]
for path in md_files():
    rel = os.path.relpath(path, ROOT)
    text = open(path, encoding='utf-8').read()
    for pat, why in BANNED:
        for m in re.finditer(pat, text):
            ctx = text[max(0, m.start() - 80): m.end() + 80]
            if re.search(r'Original text|original text|said S1|~~|was written|stale|banned', ctx):
                continue
            problems.append(f'{rel}: {why}: "{m.group(0)}"')

# (5) inventory completeness
index = open(os.path.join(DOCS, 'README.md'), encoding='utf-8').read()
for path in md_files():
    rel = os.path.relpath(path, DOCS)
    if rel == 'README.md':
        continue
    base = rel.replace(os.sep, '/')
    if base not in index and not (base.startswith('superpowers/plans/') and 'superpowers/plans/*' in index):
        problems.append(f'docs/README.md: not listed: {base}')

if problems:
    print('\n'.join(sorted(set(problems))))
    print(f'{len(set(problems))} documentation problem(s)')
    sys.exit(1)
print('documentation check passed')
