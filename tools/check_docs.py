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

# ---- policy rules (owner directions of 2026-11-12, status register OD-7 to OD-9) -------------------------------
# Each rule: (name, regex, exempt-context regex). A match is a problem unless the surrounding text says the
# statement is withdrawn, replaced, negated or quoted as history.
POLICY_RULES = [
    ('OD-7 outbox order must be the v1 rowid order, not created_at_utc',
     r'created_at_utc\s*,\s*rowid|order\s+by\s+created_at_utc|follows the[^.\n]{0,40}created_at_utc',
     r'[Rr]eplaces|not [`]?created_at_utc|never [`]?created_at_utc|first draft|rather than|withdrawn|corrected'),
    ('OD-8 no automatic backup deletion (retention is owner-controlled)',
     r'keep one|then keep|automatic(?:ally)? (?:delet|remov|prun|rotat|purg)|(?:delete|remove|prune|rotate|purge)s?\b[^.\n]{0,60}\bbackups?\b|\bbackups?\b[^.\n]{0,60}\b(?:deleted|removed|pruned|rotated|purged)\b',
     r'[Nn]ever|[Nn]o automatic|not automatic|OD-8|must not|no deletion|[Rr]eplaces|first draft|owner-controlled|withdrawn|asserts every backup'),
    ('OD-9 ambiguous v1 states (sent, failed) must not be replayed or mapped away automatically',
     r"[`']?sent[`']?(?:\s+rows?)?\s+(?:becomes|become|to|->|→)\s+[`']?pending|WHEN\s+'sent'\s+THEN\s+'pending'",
     r'[Rr]eplaces|automatic replay|withdrawn|must not|not executed|[Cc]orrected|no automatic replay|never'),
]

def policy_problems(text, rel):
    out = []
    for name, pat, exempt in POLICY_RULES:
        for m in re.finditer(pat, text):
            ctx = text[max(0, m.start() - 200): m.end() + 200]
            if re.search(exempt, ctx):
                continue
            out.append(f'{rel}: policy contradiction ({name}): "{m.group(0)}"')
    return out

def self_test():
    bad = {
        'order': 'ORDER BY created_at_utc, rowid;',
        'order2': 'The migration copies rows in created_at_utc order, so seq follows the v1 created_at_utc order.',
        'backup': 'Keep one backup and delete older backups after the next start.',
        'backup2': 'Old backups are deleted automatically after 30 days.',
        'replay': "WHEN 'sent' THEN 'pending'",
        'replay2': 'A sent row becomes pending after migration.',
    }
    good = {
        'order': 'The order is the verified v1 rowid order, never created_at_utc.',
        'backup': 'The app never deletes, rotates, prunes or overwrites a backup on its own (OD-8).',
        'replay': 'sent and failed rows are preserved with no automatic replay.',
    }
    failures = []
    for k, t in bad.items():
        if not policy_problems(t, 'self-test'):
            failures.append(f'rule did not fire on bad sample "{k}"')
    for k, t in good.items():
        if policy_problems(t, 'self-test'):
            failures.append(f'rule fired on good sample "{k}"')
    if failures:
        print('\n'.join(failures)); print('self-test failed'); sys.exit(1)
    print(f'self-test passed ({len(bad)} bad samples caught, {len(good)} good samples accepted)')

if '--self-test' in sys.argv:
    self_test()
    sys.exit(0)

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

# (4b) policy contradictions
for path in md_files():
    problems.extend(policy_problems(open(path, encoding='utf-8').read(), os.path.relpath(path, ROOT)))

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
