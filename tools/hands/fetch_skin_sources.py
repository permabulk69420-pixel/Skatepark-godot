"""Fetch CC0 inputs for the hand UV bake; all downloaded bytes are hash-checked.
Usage: python3 tools/hands/fetch_skin_sources.py /workspace/hand-work
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = json.loads((ROOT / 'assets/hands/skin/source.json').read_text())
CACHE = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('/workspace/hand-work')
CACHE.mkdir(parents=True, exist_ok=True)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fetch(url, destination, expected):
    if destination.exists() and digest(destination) == expected:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + '.download')
    subprocess.run(['curl', '-fL', '--retry', '2', '--connect-timeout', '20', '--max-time', '180',
                    url, '-o', str(temporary)], check=True)
    if digest(temporary) != expected:
        temporary.unlink()
        raise RuntimeError('Source SHA256 verification failed: ' + destination.name)
    temporary.replace(destination)


base = MANIFEST['base_repository'].replace('https://github.com/', 'https://raw.githubusercontent.com/')
base += '/' + MANIFEST['base_commit'] + '/makehuman/data/'
for filename, relative in [('source-base.obj', '3dobjs/base.obj'),
                           ('source-weights.json', 'rigs/default_weights.mhw')]:
    fetch(base + relative, CACHE / filename, MANIFEST['sha256'][filename])
archive = CACHE / 'mh_system_CC0.zip'
fetch(MANIFEST['skin_pack_url'], archive, MANIFEST['sha256'][archive.name])
entry = MANIFEST['skin_pack_entry']
with ZipFile(archive) as source:
    data = source.read(entry)  # ZipFile also checks this entry's CRC.
if hashlib.sha256(data).hexdigest() != MANIFEST['sha256']['skin_diffuse.png']:
    raise RuntimeError('Skin texture SHA256 verification failed')
destination = CACHE / 'source' / entry
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(data)
print('Verified CC0 inputs ready:', CACHE)
