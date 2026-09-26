#!/usr/bin/env python3
"""Release tooling for Balatro Seed Suite (stdlib only). Normally run via make.

  release.py version            print the suite version; fail unless every mod agrees
  release.py dist [OUT]         zips for the current version into OUT (default dist/<version>/)
  release.py notes VERSION      the CHANGELOG section for VERSION, private lines dropped
  release.py export DEST [REF]  the public tree at REF (default HEAD) into DEST

Versions are lockstep: every mods/*/src/init.lua VERSION equals the suite version, and
every dependent boot.lua NEEDS equals its major.minor.

dist writes BalatroSeedSuite.zip and SHA256SUMS. The zip holds one lovely mod folder,
BalatroSeedSuite/, the way single mods ship: each mods/<Mod>/lovely.toml becomes
lovely/<Mod>.toml with its sources prefixed <Mod>/, next to <Mod>/src/. lovely loads
the folder, or the zip itself dropped into Mods/ (it finds one mod root per zip).
The asset name is stable, so releases/latest/download/BalatroSeedSuite.zip resolves.
Zips hold only git-tracked files, with fixed timestamps and modes, so the same tree
gives byte-identical zips. Every source a patch file names must be in the zip.

export copies the files matched by scripts/public.allowlist, drops every Markdown line
marked <!-- private -->, then fails if a personal identifier, or a
relative Markdown link to a file that is not exported, is left.
"""
import fnmatch
import hashlib
import io
import os
import re
import shutil
import socket
import subprocess
import sys
import tarfile
import tomllib
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUITE = 'BalatroSeedSuite'
PRIVATE = '<!-- private -->'
EPOCH = (1980, 1, 1, 0, 0, 0)


def die(msg):
    sys.exit(f'release: {msg}')


def git(*args, binary=False):
    out = subprocess.run(['git', '-C', ROOT, *args], check=True, capture_output=True).stdout
    return out if binary else out.decode()


def mods():
    return sorted(d for d in os.listdir(os.path.join(ROOT, 'mods'))
                  if os.path.isfile(os.path.join(ROOT, 'mods', d, 'lovely.toml')))


def read(path):
    with open(os.path.join(ROOT, path), encoding='utf-8') as f:
        return f.read()


def version():
    found = {}
    for m in mods():
        v = re.search(r"VERSION = '([^']+)'", read(f'mods/{m}/src/init.lua'))
        found[m] = v and v.group(1)
    versions = set(found.values())
    if len(versions) != 1 or None in versions:
        die('mod versions differ: ' + ', '.join(f'{m} {v}' for m, v in found.items()))
    v = versions.pop()
    if not re.fullmatch(r'\d+\.\d+\.\d+', v):
        die(f'version {v} is not X.Y.Z')
    major_minor = v.rsplit('.', 1)[0]
    for m in mods():
        needs = re.search(r"local NEEDS = '([^']+)'", read(f'mods/{m}/src/boot.lua'))
        if needs and needs.group(1) != major_minor:
            die(f'mods/{m}/src/boot.lua NEEDS {needs.group(1)}, but the suite is {v}')
    return v


def lovely_sources(toml_text):
    for patch in tomllib.loads(toml_text).get('patches', []):
        for kind, body in patch.items():
            if 'source' in body:
                yield body['source']
            yield from body.get('sources', [])


def prefix_sources(text, m):
    """mods/<m>/lovely.toml as lovely/<m>.toml: every source path gains <m>/."""
    out = re.sub(r'^(\s*source\s*=\s*")', rf'\g<1>{m}/', text, flags=re.M)
    out = re.sub(r'^(\s*sources\s*=\s*\[)([^\]]*)\]',
                 lambda mo: mo.group(1) + re.sub(r'"([^"]+)"', rf'"{m}/\1"', mo.group(2)) + ']',
                 out, flags=re.M)
    if list(lovely_sources(out)) != [f'{m}/{src}' for src in lovely_sources(text)]:
        die(f'mods/{m}/lovely.toml: could not rewrite its source paths')
    return out


def bundle_entries():
    """(archive path, bytes) for the BalatroSeedSuite/ folder, from tracked files."""
    entries, names = [], set()
    for m in mods():
        tracked = [p for p in git('ls-files', '-z', f'mods/{m}').split('\0') if p]
        if f'mods/{m}/lovely.toml' not in tracked:
            die(f'mods/{m}/lovely.toml is not tracked')
        for path in tracked:
            rel = path[len('mods/'):]
            if rel != f'{m}/lovely.toml':
                with open(os.path.join(ROOT, path), 'rb') as f:
                    entries.append((f'{SUITE}/{rel}', f.read()))
                names.add(rel)
        toml = prefix_sources(read(f'mods/{m}/lovely.toml'), m)
        missing = [src for src in lovely_sources(toml) if src not in names]
        if missing:
            die(f'{m}: lovely.toml names untracked or missing sources: {", ".join(missing)}')
        entries.append((f'{SUITE}/lovely/{m}.toml', toml.encode()))
    with open(os.path.join(ROOT, 'LICENSE'), 'rb') as f:
        entries.append((f'{SUITE}/LICENSE', f.read()))
    return entries


def write_zip(path, entries):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(entries):
            info = zipfile.ZipInfo(name, EPOCH)
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)


def dist(out=None):
    v = version()
    out = out or os.path.join(ROOT, 'dist', v)
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, f'{SUITE}.zip')
    write_zip(path, bundle_entries())
    with open(path, 'rb') as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    with open(os.path.join(out, 'SHA256SUMS'), 'w') as f:
        f.write(f'{digest}  {SUITE}.zip\n')
    print(f'dist: {SUITE} {v}, {len(mods())} mods in one folder -> {os.path.relpath(path, ROOT)}')


def notes(v):
    text = read('CHANGELOG.md')
    m = re.search(rf'^## {re.escape(v)}\b[^\n]*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    if not m:
        die(f'CHANGELOG.md has no "## {v}" section')
    body = ''.join(l for l in m.group(1).splitlines(True) if PRIVATE not in l)
    sys.stdout.write(body.strip() + '\n')


def allowlisted(path, rules):
    keep = False
    for neg, pat in rules:
        if fnmatch.fnmatchcase(path, pat):
            keep = not neg
    return keep


def export(dest, ref='HEAD'):
    rules = []
    for line in read('scripts/public.allowlist').splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            rules.append((line.startswith('!'), line.lstrip('!')))
    tar = tarfile.open(fileobj=io.BytesIO(git('archive', '--format=tar', ref, binary=True)))
    files = {}
    for member in tar.getmembers():
        if member.isfile() and allowlisted(member.name, rules):
            data = tar.extractfile(member).read()
            if member.name.endswith('.md'):
                data = b''.join(l for l in data.splitlines(True) if PRIVATE.encode() not in l)
            files[member.name] = (data, member.mode)

    # Gates, before anything is written.
    # The public repo lives under an account that must not lead back to the maintainer:
    # no home path, email (or its local part), login name in any form (it prefixes the
    # personal GitHub handle), words of the git user.name, or this machine's name.
    home, email = os.path.expanduser('~'), git('config', 'user.email').strip()
    vdf = os.path.join(home, '.local/share/Steam/steamapps/libraryfolders.vdf')
    libraries = re.findall(r'"path"\s+"([^"]+)"', open(vdf).read()) if os.path.isfile(vdf) else []
    words = [home, email, email.split('@')[0], os.path.basename(home), socket.gethostname(),
             *libraries] + [w for w in git('config', 'user.name').split() if len(w) > 2]
    personal = re.compile('|'.join(re.escape(w) for w in words if w).encode(), re.I)
    problems = []
    for name, (data, _) in files.items():
        if name == 'scripts/release.py':
            continue
        for i, line in enumerate(data.splitlines(), 1):
            if personal.search(line):
                problems.append(f'{name}:{i}: personal identifier')
        if name.endswith('.md'):
            prose = re.sub(rb'```.*?```|`[^`\n]*`', b'', data, flags=re.S)
            for target in re.findall(rb'\]\(([^)\s]+)\)', prose):
                t = target.decode().split('#')[0]
                if not t or re.match(r'[a-z]+:', t):
                    continue
                resolved = os.path.normpath(os.path.join(os.path.dirname(name), t))
                if resolved not in files and not any(f.startswith(resolved + '/') for f in files):
                    problems.append(f'{name}: link to {t}, which is not exported')
    if problems:
        die('export blocked:\n  ' + '\n  '.join(problems))

    # DEST is emptied except for .git, so it must be an empty dir or another checkout.
    dest = os.path.abspath(dest)
    if os.path.commonpath([dest, ROOT]) in (dest, ROOT):
        die(f'{dest} overlaps this repo')
    if os.path.isdir(dest) and os.listdir(dest) and not os.path.isdir(os.path.join(dest, '.git')):
        die(f'{dest} is neither empty nor a git checkout')
    os.makedirs(dest, exist_ok=True)
    for entry in os.listdir(dest):
        if entry == '.git':
            continue
        p = os.path.join(dest, entry)
        shutil.rmtree(p) if os.path.isdir(p) and not os.path.islink(p) else os.remove(p)
    for name, (data, mode) in files.items():
        p = os.path.join(dest, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(data)
        os.chmod(p, mode & 0o777)
    print(f'export: {len(files)} files at {ref} -> {dest}')


def main(argv):
    cmd, args = (argv[0] if argv else ''), argv[1:]
    if cmd == 'version':
        print(version())
    elif cmd == 'dist':
        dist(*args[:1])
    elif cmd == 'notes' and args:
        notes(args[0])
    elif cmd == 'export' and args:
        export(*args[:2])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
