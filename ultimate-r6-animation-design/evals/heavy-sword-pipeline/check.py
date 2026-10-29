from pathlib import Path
import subprocess,tempfile,json,shutil,hashlib
import argparse
parser=argparse.ArgumentParser(description='Run the heavy-sword pipeline acceptance and rejection cases.')
parser.add_argument('--out',type=Path);options=parser.parse_args()
case=Path(__file__).resolve().parent;tools=case.parents[1]/'tools';provider=case/'files/HeavyMoves.luau'
root=case
source=provider.read_text();results=[]
def run(args):return subprocess.run(['lune','run',*map(str,args)],cwd=tools,text=True,capture_output=True)
with tempfile.TemporaryDirectory(prefix='r6-pack-check-',dir=None) as temp:
 d=Path(temp);shutil.copy2(provider.parent/'slash-reference.json',d/'slash-reference.json');shutil.copy2(provider.parent/'heavy-reference.json',d/'heavy-reference.json')
 positive=d/'good';p=run(['pack',provider,positive]);assert p.returncode==0,p.stdout+p.stderr
 cases=[
  ('missing_heavy_visual',source.replace('visualBrief = "heavy-reference.json",',''),'requires watched heavy-specific'),
  ('tip_geometry',source.replace('Vector3.new(0, -1, -5.5)','Vector3.new(0, -1, -99)',1),'meta.tip disagree'),
  ('hit_metadata',source.replace('hit = hit,','hit = hit + 1,'),'meta.hit disagrees'),
  ('missing_hit',source.replace('c:marker(hit, "Hit")','c:marker(hit, "Touch")'),'exactly one Hit'),
  ('broken_seam',source.replace('begin("Heavy02_ReturnSweep", dragL)','begin("Heavy02_ReturnSweep", G)'),'seam before'),
  ('offhand',source.replace('raise = raise - 22','raise = raise + 30'),'off-hand leaves grip'),
  ('body_overlap',source.replace('up = up, forward = lunge','up = -0.9, forward = lunge'),'penetrates Torso'),
 ]
 for name,text,reason in cases:
  assert text!=source, 'fixture replacement missing: '+name
  p=d/(name+'.luau');p.write_text(text)
  dest=d/(name+'-out');dest.mkdir();sentinel=dest/'keep.txt';sentinel.write_text('previous successful artifact');prior=dest/'HeavySwordCombo4.rbxm';shutil.copy2(positive/'HeavySwordCombo4.rbxm',prior);prior_hash=hashlib.sha256(prior.read_bytes()).hexdigest()
  r=run(['pack',p,dest]);ok=r.returncode!=0 and reason in r.stdout+r.stderr and sentinel.read_text()=='previous successful artifact' and [p.name for p in dest.glob('*.rbxm')]==['HeavySwordCombo4.rbxm'] and hashlib.sha256(prior.read_bytes()).hexdigest()==prior_hash
  results.append({'name':name,'passed':ok,'expectedReason':reason})
  if not ok:raise AssertionError(name+'\n'+r.stdout+r.stderr)
 # Cache hit and invalidation must be observable, not assumed from metadata alone.
 ref=case/'files/SourceReference.rbxm';cache=d/'cache.json'
 args=['measure',ref,cache,'SwordSlash','--tip=Right Arm:0,-1,-4']
 first=run(args);assert first.returncode==0 and 'saved' in first.stdout
 second=run(args);assert second.returncode==0 and 'cache HIT' in second.stdout
 results.append({'name':'cache_hit','passed':True})
 changed=run(['measure',ref,cache,'SwordSlash','--tip=Right Arm:0,-1,-5']);assert changed.returncode==0 and 'saved' in changed.stdout
 results.append({'name':'cache_grip_invalidation','passed':True})
 mutation=d/'mutate.luau';different=d/'changed.rbxm'
 mutation.write_text('local R=require("@lune/roblox")\nlocal fs=require("@lune/fs")\nlocal roots=R.deserializeModel(fs.readFile('+json.dumps(str(ref))+'))\nroots[1].Name..="_changed"\nfs.writeFile('+json.dumps(str(different))+',R.serializeModel(roots))\n')
 assert run([mutation]).returncode==0
 changed=run(['measure',different,cache,'SwordSlash','--tip=Right Arm:0,-1,-5']);assert changed.returncode==0 and 'saved' in changed.stdout
 results.append({'name':'cache_source_invalidation','passed':True})
 report=run(['study',ref,'SwordSlash','--tip=Right Arm:0,-1,-4']);assert report.returncode==0
 short=run(args);assert short.returncode==0
 results.append({'name':'measured_stdout_characters','old':len(report.stdout),'new':len(short.stdout),'note':'Same source and selection; not billed-token measurements.'})
if options.out:
 options.out.parent.mkdir(parents=True,exist_ok=True)
 options.out.write_text(json.dumps(results,indent=2)+'\n')
print('[pipeline] 10 passed / rejection gates + previous artifact intact + cache invalidation')
