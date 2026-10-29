-- Report legacy sample limitations; never change their provenance or relax the shipping gate.
local E=require("./env")
local serde=require("@lune/serde")
local Clip,Collision=E.load("R6Clip"),E.load("R6Collision")
local report={total=0,clear=0,blocked=0,clips={}}
for _,module in {"CombatMoves","Locomotion"} do
 for name,item in E.load(module).build() do
  local a=Collision.audit(Clip.world(item.baked))
  report.total+=1
  if a.ok then
   report.clear+=1
  else
   report.blocked+=1
  end
  report.clips[module.."."..name]=a
 end
end
local out=E.args[1] or "legacy-body-report.json"
E.fs.writeFile(out,serde.encode("json",report,true))
print(string.format("[legacy body] %d checked / %d clear / %d blocked / %s",report.total,report.clear,report.blocked,out))
