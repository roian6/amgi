#!/usr/bin/env python3
"""Apply the preserved Anki transport delta, without touching any collection."""
from pathlib import Path
import hashlib,json,os,subprocess,sys
root=Path(__file__).resolve().parents[1]
spec=json.loads((root/'Preservation/anki-watch-sync.json').read_text())
repo=root/'anki-upstream'; patch=root/'Preservation/anki-watch-sync.patch'
env=dict(os.environ,GIT_OPTIONAL_LOCKS='0',GIT_NO_LAZY_FETCH='1',GIT_TERMINAL_PROMPT='0')
def git(*args):
 p=subprocess.run(['git','-c','core.hooksPath=/dev/null','-C',str(repo),*args],capture_output=True,env=env)
 if p.returncode:raise SystemExit('Anki preparation failed: '+args[0])
 return p.stdout.decode().strip()
if hashlib.sha256(patch.read_bytes()).hexdigest()!=spec['patch_sha256']:raise SystemExit('Patch checksum mismatch')
if git('rev-parse','HEAD')!=spec['base']:raise SystemExit('Initialize anki-upstream at the pinned public base first')
def matches():
 for path,data in spec['files'].items():
  p=repo/path
  if not p.is_file() or git('hash-object','--no-filters','--',str(p))!=data['blob']:return False
 return True
if matches():
 allowed=set(spec['files'])
 dirty={line[3:] for line in git('status','--porcelain=v1','--untracked-files=all').splitlines()}
 if not dirty<=allowed:raise SystemExit('Unrelated changes in Anki checkout; refusing')
 print('Preserved Anki transport patch already present');sys.exit(0)
if git('status','--porcelain=v1','--untracked-files=all'):raise SystemExit('Anki checkout must be clean before first apply')
git('apply','--check','--index',str(patch));git('apply','--index',str(patch))
if not matches():raise SystemExit('Applied Rust files do not match preserved source blobs')
print('Preserved Anki transport patch applied and six source blobs verified')
