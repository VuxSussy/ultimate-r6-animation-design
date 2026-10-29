local E=require("./env")
local R=E.roblox
local C,V=R.CFrame,R.Vector3
local Collision,Clip,Rig,Quality=E.load("R6Collision"),E.load("R6Clip"),E.load("R6Rig"),E.load("R6Quality")
local count=0
local function test(ok,label)
 assert(ok,label)
 count+=1
end
local size=V.new(2,2,2)
test(Collision.boxDepth(C.identity,size,C.new(2,0,0),size)==0,"touching boxes must pass")
test(math.abs(Collision.boxDepth(C.identity,size,C.new(1.5,0,0),size)-.5)<1e-5,"known overlap depth")
local a=C.Angles(0,0,math.rad(45))
local b=C.new(-.4,.4,0)*a
test(Collision.boxDepth(a,V.new(4,.2,.2),b,V.new(4,.2,.2))==0,"OBB must reject AABB false positive")
local rest=Rig.fk({})
test(Collision.legTorso(rest)["Right Leg"]==0,"rest pose clear")
local seam=table.clone(rest)
seam["Right Leg"]*=C.new(0,.12,0)
test(Collision.legTorso(seam)["Right Leg"]==0,"small hip joint seam allowed")
-- Representative regressions for the user's screenshots: buried upper thigh and folded leg in body.
local buried=table.clone(rest)
buried["Left Leg"]=C.new(-.45,-1.3,0)*C.Angles(.3,0,0)
local folded=table.clone(rest)
folded["Right Leg"]=C.new(.2,-.2,0)*C.Angles(math.rad(85),0,0)
test(Collision.legTorso(buried)["Left Leg"]>.1,"buried thigh must fail")
test(Collision.legTorso(folded)["Right Leg"]>.1,"folded leg inside torso must fail")
local clear=table.clone(rest)
clear["Right Leg"]=C.new(.5,-.8,-2)*C.Angles(math.rad(90),0,0)
test(Collision.legTorso(clear)["Right Leg"]==0,"a raised leg clear in front must pass")
local world={{frame=0,parts=rest},{frame=1,parts=folded},{frame=2,parts=rest}}
local audit=Collision.audit(world)
test(not audit.ok and audit.legs["Right Leg"].frame==1,"sample every frame, including in-betweens")
local rotated={}
local global=C.new(4,3,-2)*C.Angles(.6,.8,-.3)
for n,cf in folded do
 rotated[n]=global*cf
end
test(math.abs(Collision.legTorso(rotated)["Right Leg"]-Collision.legTorso(folded)["Right Leg"])<1e-4,"rotation/translation invariant")
local c=Clip.new("BuriedAirborne",{meta={airborne=true}})
c:key(0,{RightLeg={raise=85,pos={up=1.2}}})
c:key(6,{RightLeg={raise=85,pos={up=1.2}}})
local baked=c:bake()
test(Clip.audit(baked,{airborne=true}).ok,"regression fixture passes the old motion-only audit")
local q=Quality.audit(baked,{airborne=true})
test(not q.ok and q.metrics.bodyLegs["Right Leg"].depth>.025,"airborne does not disable torso check")
test(not Quality.audit(baked,{airborne=true,stride=true,legsMayCross=true}).ok,"leg-crossing/stride flags cannot bypass body check")
local function stance(drop)
 local clip=Clip.new("GroundedStance")
 local pose={Torso={pos={up=drop}},RightLeg={space="root",ground=true},LeftLeg={space="root",ground=true}}
 clip:key(0,pose)
 clip:key(8,pose)
 return clip:bake()
end
local deep=stance(-.6)
test(Clip.audit(deep,{}).ok,"grounded legal-budget buried thighs pass old audit")
test(not Quality.audit(deep,{}).ok,"grounding cannot hide buried thighs")
test(Quality.audit(stance(-.05),{}).ok,"shallower stance repairs the body and retains floor/socket checks")
local sizes={Torso=V.new(2,2,3),["Right Leg"]=V.new(1,2,1),["Left Leg"]=V.new(1,2,1)}
local custom=table.clone(rest)
custom["Right Leg"]=C.new(.5,-.6,-1.5)
test(Collision.legTorso(custom)["Right Leg"]==0 and Collision.legTorso(custom,sizes)["Right Leg"]>.1,"use real body sizes for custom rigs")
print(string.format("[quality] %d passed, 0 failed",count))
