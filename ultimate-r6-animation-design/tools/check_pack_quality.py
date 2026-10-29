"""Exercise the real pack CLI: a prior successful export survives a rejected body pose."""
from pathlib import Path
import json, subprocess, tempfile
here = Path(__file__).resolve().parent
provider = '''local Clip=require(script.Parent.R6Clip)
local M={PACK="GateTest",LIST={"TestPose"},REFERENCE={brief="reference.json",adaptations="Synthetic quality-gate regression fixture; not an animation reference."}}
function M.build()
 local c=Clip.new("TestPose",{meta={airborne=true,hit=2}})
 local pose=__POSE__
 c:key(0,pose)
 c:key(6,pose)
 c:marker(2,"Hit")
 return {TestPose={baked=c:bake(),meta=c.meta}}
end
return M
'''
with tempfile.TemporaryDirectory(prefix='r6-body-gate-') as scratch:
    base = Path(scratch)
    (base/'reference.json').write_text(json.dumps({'schema':1,'sourceHash':'synthetic-test-only','clips':['TestPose']}))
    source = base/'Moves.luau'
    output = base/'out'
    def run(pose):
        source.write_text(provider.replace('__POSE__', pose))
        return subprocess.run(['lune','run','pack',str(source),str(output)],cwd=here,text=True,capture_output=True)
    good=run('{}')
    assert good.returncode==0,good.stdout+good.stderr
    artifact=output/'GateTest.rbxm'
    previous=artifact.read_bytes()
    bad=run('{RightLeg={raise=85,pos={up=1.2}}}')
    assert bad.returncode!=0,'buried thigh unexpectedly exported'
    assert 'body: Right Leg penetrates Torso' in bad.stdout+bad.stderr,bad.stdout+bad.stderr
    assert artifact.read_bytes()==previous,'rejected build overwrote a previous valid asset'
    legacy=base/'legacy'
    rejected=subprocess.run(['lune','run','build',str(legacy),'Stance'],cwd=here,text=True,capture_output=True)
    assert rejected.returncode!=0,'legacy builder bypassed body gate'
    assert 'body:' in rejected.stdout+rejected.stderr,'legacy failed before a body diagnostic:\n'+rejected.stdout+rejected.stderr
    assert not (legacy/'R6CombatPack.rbxm').exists(),'legacy builder wrote an invalid pack'
print('[pack quality] 4 passed: valid export, buried-thigh rejection, prior export preserved, legacy builder blocked')
